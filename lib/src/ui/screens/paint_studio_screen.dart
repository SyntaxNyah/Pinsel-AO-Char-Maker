import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';

import '../../imaging/color_ops.dart' show formatHexColor;
import '../../imaging/paint.dart';
import '../app_state.dart';

/// The active paint tool. Brush is a freehand drag; the fills are tap-to-apply
/// (a magic-wand region at the tapped point, or the whole sprite).
enum _Tool { brush, fill, gradient, eyedropper }

extension _ToolInfo on _Tool {
  IconData get icon => switch (this) {
        _Tool.brush => Icons.brush_rounded,
        _Tool.fill => Icons.format_color_fill_rounded,
        _Tool.gradient => Icons.gradient_rounded,
        _Tool.eyedropper => Icons.colorize_rounded,
      };
  String get label => switch (this) {
        _Tool.brush => 'Brush',
        _Tool.fill => 'Bucket',
        _Tool.gradient => 'Gradient',
        _Tool.eyedropper => 'Pick',
      };
}

/// # Paint Studio
///
/// Advanced region/paint editing for the selected sprite: a freehand **brush**
/// (paint / erase / dodge / burn / smudge), a **bucket** that floods a
/// magic-wand region (or the whole sprite) with a solid colour through any
/// **blend mode** (pick *Color* to recolour the clothes while keeping their
/// shading), a **gradient** fill with a full multi-stop **gradient editor**, and
/// an **eyedropper**. Every edit is a journalled [PaintOp] (per-op undo); nothing
/// touches the real sprite until you hit **Apply**, which bakes the journal into
/// every animation frame losslessly. See docs/PAINT.md.
class PaintStudioScreen extends StatefulWidget {
  const PaintStudioScreen({super.key});

  @override
  State<PaintStudioScreen> createState() => _PaintStudioScreenState();
}

class _PaintStudioScreenState extends State<PaintStudioScreen> {
  late final AppState app;

  _Tool _tool = _Tool.brush;

  // Brush settings.
  final BrushSpec _brush = BrushSpec(argb: 0xFFEC407A, size: 0.06);

  // Fill / selection settings.
  int _fillColor = 0xFFEC407A;
  PaintBlend _blend = PaintBlend.normal;
  double _opacity = 1.0;
  bool _preserveAlpha = true;
  bool _wholeSprite = false;
  double _tolerance = 48;
  bool _contiguous = true;
  int _feather = 1;
  int _grow = 0;

  // Gradient.
  PaintGradient _gradient = PaintGradient.fromColors(
      <int>[0xFF22223B, 0xFF9A348E, 0xFFEE6C4D, 0xFFFFD166],
      name: 'Sunset', category: 'Fire');

  Uint8List? _preview;
  double _aspect = 1;
  bool _busy = false;
  int _lastEmote = -1;
  int _lastRev = -1;
  Timer? _debounce;

  // The in-progress freehand stroke, in normalized 0..1 coords.
  final List<Offset> _live = <Offset>[];

  @override
  void initState() {
    super.initState();
    app = Provider.of<AppState>(context, listen: false);
    app.addListener(_onApp);
    _reseed();
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    _debounce?.cancel();
    super.dispose();
  }

  void _onApp() {
    if (!mounted) return;
    if (app.selectedEmote != _lastEmote || app.spriteRevision != _lastRev) {
      _reseed();
    } else {
      _schedule();
    }
  }

  Future<void> _reseed() async {
    _lastEmote = app.selectedEmote;
    _lastRev = app.spriteRevision;
    final double? a = await app.currentSpriteAspect();
    if (!mounted) return;
    setState(() => _aspect = (a == null || a <= 0) ? 1 : a);
    _schedule(immediate: true);
  }

  void _schedule({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: immediate ? 0 : 120), () async {
      final String? rel = _rel();
      if (rel == null) {
        if (mounted) setState(() => _preview = null);
        return;
      }
      final Uint8List? b = await app.previewPaint(rel);
      if (mounted) setState(() => _preview = b);
    });
  }

  String? _rel() {
    final e = app.current;
    if (e == null) return null;
    return app.spriteRelFor(e);
  }

  // ---- gesture handlers (coords already normalized 0..1) ----

  void _onTap(Offset n) {
    switch (_tool) {
      case _Tool.eyedropper:
        _pickAt(n);
      case _Tool.fill:
        _commitFill(n, gradient: false);
      case _Tool.gradient:
        _commitFill(n, gradient: true);
      case _Tool.brush:
        // A tap with the brush = a single dot.
        app.addPaintOp(PaintOp(PaintOpKind.brush,
            brush: _brush.copy(), stroke: <double>[n.dx, n.dy]));
    }
  }

  Future<void> _pickAt(Offset n) async {
    final int? c = await app.pickColorAt(n.dx, n.dy);
    if (c == null || !mounted) return;
    setState(() {
      _fillColor = c;
      _brush.argb = c;
    });
  }

  PaintSelection _selection(Offset n) => _wholeSprite
      ? PaintSelection(SelectionKind.whole, feather: _feather, grow: _grow)
      : PaintSelection(SelectionKind.wand,
          x: n.dx,
          y: n.dy,
          tolerance: _tolerance,
          contiguous: _contiguous,
          feather: _feather,
          grow: _grow);

  void _commitFill(Offset n, {required bool gradient}) {
    app.addPaintOp(PaintOp(
      gradient ? PaintOpKind.fillGradient : PaintOpKind.fillSolid,
      selection: _selection(n),
      argb: _fillColor,
      gradient: _gradient.copy(),
      blend: _blend,
      opacity: _opacity,
      preserveAlpha: _preserveAlpha,
    ));
  }

  void _onPanStart(Offset n) {
    if (_tool != _Tool.brush) return;
    setState(() => _live
      ..clear()
      ..add(n));
  }

  void _onPanUpdate(Offset n) {
    if (_tool != _Tool.brush) return;
    setState(() => _live.add(n));
  }

  void _onPanEnd() {
    if (_tool != _Tool.brush || _live.length < 2) {
      _live.clear();
      return;
    }
    final List<double> stroke = <double>[
      for (final Offset o in _live) ...<double>[o.dx, o.dy],
    ];
    app.addPaintOp(
        PaintOp(PaintOpKind.brush, brush: _brush.copy(), stroke: stroke));
    _live.clear();
  }

  Future<void> _apply({required bool allSprites}) async {
    setState(() => _busy = true);
    final int n = await app.applyPaint(allSprites: allSprites);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Painted $n sprite file(s).')));
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSprite = _rel() != null;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            children: <Widget>[
              _toolbar(),
              const Divider(height: 1),
              Expanded(
                child: hasSprite
                    ? _canvas()
                    : const Center(
                        child: Text('Select an emote with a sprite to paint.')),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(width: 320, child: _sidebar()),
      ],
    );
  }

  Widget _toolbar() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: <Widget>[
          for (final _Tool t in _Tool.values) ...<Widget>[
            _ToolButton(
              tool: t,
              selected: _tool == t,
              onTap: () => setState(() => _tool = t),
            ),
            const SizedBox(width: 6),
          ],
          const Spacer(),
          Consumer<AppState>(
            builder: (_, AppState a, __) => Text('${a.paintOps.length} edit(s)'),
          ),
          IconButton(
            tooltip: 'Undo last edit',
            onPressed: app.hasPaintOps ? app.undoPaintOp : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Clear all edits (does not touch the sprite)',
            onPressed: app.hasPaintOps ? app.clearPaintOps : null,
            icon: const Icon(Icons.layers_clear_rounded),
          ),
        ],
      ),
    );
  }

  Widget _canvas() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AspectRatio(
          aspectRatio: _aspect,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final Size size = Size(c.maxWidth, c.maxHeight);
              Offset norm(Offset local) => Offset(
                    (local.dx / size.width).clamp(0.0, 1.0),
                    (local.dy / size.height).clamp(0.0, 1.0),
                  );
              return GestureDetector(
                onTapUp: (TapUpDetails d) => _onTap(norm(d.localPosition)),
                onPanStart: (DragStartDetails d) => _onPanStart(norm(d.localPosition)),
                onPanUpdate: (DragUpdateDetails d) => _onPanUpdate(norm(d.localPosition)),
                onPanEnd: (_) => _onPanEnd(),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    const _Checker(),
                    if (_preview != null)
                      Image.memory(_preview!,
                          fit: BoxFit.fill, gaplessPlayback: true),
                    CustomPaint(
                      painter: _StrokePainter(
                        List<Offset>.of(_live),
                        Color(_brush.argb),
                        _brush.size,
                        _brush.mode == BrushMode.erase,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sidebar() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        if (_tool == _Tool.brush) ..._brushControls(),
        if (_tool == _Tool.fill) ..._fillControls(),
        if (_tool == _Tool.gradient) ..._gradientControls(),
        if (_tool == _Tool.eyedropper)
          const Text('Tap the sprite to grab a colour.'),
        const Divider(height: 24),
        FilledButton.icon(
          onPressed: _busy || !app.hasPaintOps ? null : () => _apply(allSprites: false),
          icon: const Icon(Icons.check_rounded),
          label: const Text('Apply to this sprite'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy || !app.hasPaintOps ? null : () => _apply(allSprites: true),
          icon: const Icon(Icons.done_all_rounded),
          label: const Text('Apply to ALL sprites'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  List<Widget> _brushControls() => <Widget>[
        _heading('Brush'),
        _ColorRow(
          label: 'Colour',
          color: _brush.argb,
          onPick: () => _pick(_brush.argb).then((int? c) {
            if (c != null) setState(() => _brush.argb = c);
          }),
        ),
        _dropdown<BrushMode>(
          'Mode',
          _brush.mode,
          BrushMode.values,
          (BrushMode m) => m.label,
          (BrushMode? m) => setState(() => _brush.mode = m ?? BrushMode.paint),
        ),
        if (_brush.mode == BrushMode.paint)
          _blendDropdown(_brush.blend, (PaintBlend b) => setState(() => _brush.blend = b)),
        _slider('Size', _brush.size, 0.01, 0.6,
            (double v) => setState(() => _brush.size = v)),
        _slider('Hardness', _brush.hardness, 0, 1,
            (double v) => setState(() => _brush.hardness = v)),
        _slider('Opacity', _brush.opacity, 0.05, 1,
            (double v) => setState(() => _brush.opacity = v)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Stay inside the sprite'),
          subtitle: const Text("Don't paint over transparent pixels"),
          value: _brush.clipToOpaque,
          onChanged: (bool v) => setState(() => _brush.clipToOpaque = v),
        ),
      ];

  List<Widget> _fillControls() => <Widget>[
        _heading('Bucket fill'),
        _ColorRow(
          label: 'Colour',
          color: _fillColor,
          onPick: () => _pick(_fillColor).then((int? c) {
            if (c != null) setState(() => _fillColor = c);
          }),
        ),
        _blendDropdown(_blend, (PaintBlend b) => setState(() => _blend = b)),
        Text('Tip: pick the "Color" blend to recolour while keeping shading.',
            style: Theme.of(context).textTheme.bodySmall),
        _slider('Strength', _opacity, 0.05, 1, (double v) => setState(() => _opacity = v)),
        ..._selectionControls(),
      ];

  List<Widget> _gradientControls() => <Widget>[
        _heading('Gradient fill'),
        _GradientEditor(
          gradient: _gradient,
          app: app,
          onChanged: (PaintGradient g) => setState(() => _gradient = g),
          pick: _pick,
        ),
        _blendDropdown(_blend, (PaintBlend b) => setState(() => _blend = b)),
        _slider('Strength', _opacity, 0.05, 1, (double v) => setState(() => _opacity = v)),
        ..._selectionControls(),
      ];

  List<Widget> _selectionControls() => <Widget>[
        const Divider(height: 20),
        _heading('Region'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Whole sprite'),
          subtitle: const Text('Off = tap a part (magic wand)'),
          value: _wholeSprite,
          onChanged: (bool v) => setState(() => _wholeSprite = v),
        ),
        if (!_wholeSprite) ...<Widget>[
          _slider('Wand tolerance', _tolerance, 1, 200,
              (double v) => setState(() => _tolerance = v)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Connected only'),
            value: _contiguous,
            onChanged: (bool v) => setState(() => _contiguous = v),
          ),
        ],
        _slider('Feather', _feather.toDouble(), 0, 12,
            (double v) => setState(() => _feather = v.round()),
            divisions: 12),
        _slider('Grow / shrink', _grow.toDouble(), -12, 12,
            (double v) => setState(() => _grow = v.round()),
            divisions: 24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Keep alpha'),
          subtitle: const Text("Recolour only; don't fill transparent areas"),
          value: _preserveAlpha,
          onChanged: (bool v) => setState(() => _preserveAlpha = v),
        ),
      ];

  // ---- small reusable bits ----

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged, {int? divisions}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: 96, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: value.toStringAsFixed(divisions == null ? 2 : 0),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(String label, T value, List<T> items, String Function(T) name,
      ValueChanged<T?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(width: 96, child: Text(label)),
          Expanded(
            child: DropdownButton<T>(
              isExpanded: true,
              value: value,
              items: <DropdownMenuItem<T>>[
                for (final T i in items)
                  DropdownMenuItem<T>(value: i, child: Text(name(i))),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _blendDropdown(PaintBlend value, ValueChanged<PaintBlend> onChanged) =>
      _dropdown<PaintBlend>('Blend', value, PaintBlend.values,
          (PaintBlend b) => b.label, (PaintBlend? b) => onChanged(b ?? PaintBlend.normal));

  Future<int?> _pick(int current) async {
    Color c = Color(current);
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Pick a colour'),
            content: SingleChildScrollView(
              child: ColorPicker(
                pickerColor: c,
                enableAlpha: true,
                paletteType: PaletteType.hueWheel,
                hexInputBar: true,
                labelTypes: const <ColorLabelType>[
                  ColorLabelType.hex,
                  ColorLabelType.rgb,
                  ColorLabelType.hsv,
                ],
                onColorChanged: (Color v) => c = v,
              ),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('OK')),
            ],
          ),
        ) ??
        false;
    return ok ? c.value : null;
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tool, required this.selected, required this.onTap});
  final _Tool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tool.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(tool.icon,
                  size: 18,
                  color: selected ? cs.onPrimaryContainer : cs.onSurface),
              const SizedBox(width: 6),
              Text(tool.label,
                  style: TextStyle(
                      color: selected ? cs.onPrimaryContainer : cs.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.label, required this.color, required this.onPick});
  final String label;
  final int color;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(width: 96, child: Text(label)),
          InkWell(
            onTap: onPick,
            child: Container(
              width: 36,
              height: 24,
              decoration: BoxDecoration(
                color: Color(color),
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(formatHexColor(color), style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

/// A multi-stop gradient editor: a ramp preview, per-stop colour + position,
/// add/remove stops, type/angle/reverse, and a preset picker + save.
class _GradientEditor extends StatelessWidget {
  const _GradientEditor({
    required this.gradient,
    required this.app,
    required this.onChanged,
    required this.pick,
  });

  final PaintGradient gradient;
  final AppState app;
  final ValueChanged<PaintGradient> onChanged;
  final Future<int?> Function(int) pick;

  @override
  Widget build(BuildContext context) {
    final List<GradientStop> sorted = <GradientStop>[...gradient.stops]
      ..sort((GradientStop a, GradientStop b) => a.pos.compareTo(b.pos));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Ramp preview (linear visual regardless of mapping type).
        Container(
          height: 24,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.black26),
            gradient: LinearGradient(
              colors: <Color>[for (final GradientStop s in sorted) Color(s.argb)],
              stops: <double>[for (final GradientStop s in sorted) s.pos.clamp(0.0, 1.0)],
            ),
          ),
        ),
        for (int i = 0; i < gradient.stops.length; i++)
          _stopRow(context, i),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              final PaintGradient g = gradient.copy();
              g.stops.add(GradientStop(0.5, 0xFFFFFFFF));
              onChanged(g);
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add stop'),
          ),
        ),
        Row(
          children: <Widget>[
            SizedBox(width: 70, child: Text('Type', style: Theme.of(context).textTheme.bodyMedium)),
            Expanded(
              child: DropdownButton<GradientType>(
                isExpanded: true,
                value: gradient.type,
                items: <DropdownMenuItem<GradientType>>[
                  for (final GradientType t in GradientType.values)
                    DropdownMenuItem<GradientType>(value: t, child: Text(t.label)),
                ],
                onChanged: (GradientType? t) {
                  if (t == null) return;
                  onChanged(gradient.copy()..type = t);
                },
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            const SizedBox(width: 70, child: Text('Angle')),
            Expanded(
              child: Slider(
                value: gradient.angle.clamp(0, 360),
                max: 360,
                divisions: 24,
                label: '${gradient.angle.round()}°',
                onChanged: (double v) => onChanged(gradient.copy()..angle = v),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reverse'),
          value: gradient.reverse,
          onChanged: (bool v) => onChanged(gradient.copy()..reverse = v),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showPresets(context),
                icon: const Icon(Icons.collections_rounded, size: 18),
                label: const Text('Presets'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _save(context),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stopRow(BuildContext context, int i) {
    final GradientStop s = gradient.stops[i];
    return Row(
      children: <Widget>[
        InkWell(
          onTap: () => pick(s.argb).then((int? c) {
            if (c != null) onChanged(gradient.copy()..stops[i].argb = c);
          }),
          child: Container(
            width: 28,
            height: 20,
            decoration: BoxDecoration(
              color: Color(s.argb),
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: s.pos.clamp(0.0, 1.0),
            label: s.pos.toStringAsFixed(2),
            onChanged: (double v) => onChanged(gradient.copy()..stops[i].pos = v),
          ),
        ),
        IconButton(
          tooltip: 'Remove stop',
          iconSize: 18,
          onPressed: gradient.stops.length <= 2
              ? null
              : () => onChanged(gradient.copy()..stops.removeAt(i)),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  void _showPresets(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) {
        final List<PaintGradient> all = <PaintGradient>[
          ...app.userGradients,
          ...GradientLibrary.presets,
        ];
        return ListView(
          children: <Widget>[
            for (final PaintGradient g in all)
              ListTile(
                leading: Container(
                  width: 48,
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      colors: <Color>[
                        for (final GradientStop s
                            in (<GradientStop>[...g.stops]
                              ..sort((GradientStop a, GradientStop b) =>
                                  a.pos.compareTo(b.pos))))
                          Color(s.argb)
                      ],
                    ),
                  ),
                ),
                title: Text(g.name.isEmpty ? '(unnamed)' : g.name),
                subtitle: Text(g.category),
                onTap: () {
                  onChanged(g.copy());
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        );
      },
    );
  }

  void _save(BuildContext context) {
    final TextEditingController c =
        TextEditingController(text: gradient.name.isEmpty ? 'My gradient' : gradient.name);
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Save gradient'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final PaintGradient g = PaintGradient(
                <GradientStop>[for (final GradientStop s in gradient.stops) s.copy()],
                type: gradient.type,
                angle: gradient.angle,
                reverse: gradient.reverse,
                name: c.text.trim(),
                category: 'Saved',
              );
              app.saveGradient(g);
              onChanged(g);
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Draws the in-progress freehand stroke over the sprite as soft dots so the
/// brush feels live, without re-baking the image on every pointer move.
class _StrokePainter extends CustomPainter {
  _StrokePainter(this.points, this.color, this.sizeFrac, this.erase);
  final List<Offset> points;
  final Color color;
  final double sizeFrac;
  final bool erase;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final double shorter = size.width < size.height ? size.width : size.height;
    final double r = (sizeFrac * shorter / 2).clamp(1.0, shorter);
    final Paint paint = Paint()
      ..color = erase ? Colors.white.withOpacity(0.5) : color.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    for (final Offset p in points) {
      canvas.drawCircle(Offset(p.dx * size.width, p.dy * size.height), r, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.points.length != points.length || old.color != color;
}

/// A lightweight transparency checkerboard behind the sprite.
class _Checker extends StatelessWidget {
  const _Checker();
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFF2A2A2A));
}
