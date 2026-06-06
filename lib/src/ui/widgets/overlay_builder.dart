import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../imaging/codecs.dart';
import '../../imaging/overlay_presets.dart';
import 'checker_image.dart';

/// Opens the in-app **overlay builder** — design a custom border/background by
/// choosing a style, colours (via a colour wheel), thickness, corner radius,
/// etc., with a live preview. [initial] pre-fills it (the slot's current spec,
/// so you can *edit* an applied overlay); [onApply] receives the finished spec.
///
/// A **Big editor** button opens a full-screen **zoom + pan** view of the
/// overlay (the same controls on the side) — like the button maker's big editor.
Future<void> showOverlayBuilder(
  BuildContext context, {
  required OverlayKind kind,
  OverlaySpec? initial,
  required ValueChanged<OverlaySpec> onApply,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _OverlayBuilderDialog(kind: kind, initial: initial, onApply: onApply),
  );
}

class _OverlayBuilderDialog extends StatefulWidget {
  const _OverlayBuilderDialog(
      {required this.kind, required this.initial, required this.onApply});
  final OverlayKind kind;
  final OverlaySpec? initial;
  final ValueChanged<OverlaySpec> onApply;

  @override
  State<_OverlayBuilderDialog> createState() => _OverlayBuilderDialogState();
}

class _OverlayBuilderDialogState extends State<_OverlayBuilderDialog> {
  late OverlaySpec _spec;

  @override
  void initState() {
    super.initState();
    final OverlaySpec? init = widget.initial;
    _spec = (init != null && init.kind == widget.kind)
        ? init.copy()
        : OverlayPresets.defaultSpec(widget.kind);
  }

  /// Open the full-screen big-zoom editor on the SAME spec. Returns true if the
  /// user pressed Apply there (we then close + apply); false/null just returns
  /// here with the edits reflected.
  Future<void> _openBig() async {
    final bool? applied = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _OverlayBigBuilder(spec: _spec, kind: widget.kind),
      ),
    );
    if (!mounted) return;
    if (applied == true) {
      Navigator.of(context).pop(); // close this dialog
      widget.onApply(_spec);
    } else {
      setState(() {}); // reflect any edits made in the big editor
    }
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List preview = Codecs.encodePng(_spec.build(150));
    return AlertDialog(
      title: Text(widget.kind == OverlayKind.border
          ? 'Build a border'
          : 'Build a background'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CheckerImage(bytes: preview),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: OutlinedButton.icon(
                  onPressed: _openBig,
                  icon: const Icon(Icons.zoom_out_map_rounded, size: 18),
                  label: const Text('Big editor (zoom & pan)'),
                ),
              ),
              const SizedBox(height: 12),
              _OverlayControlsPanel(
                spec: _spec,
                kind: widget.kind,
                onChanged: () => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onApply(_spec);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// The full-screen **big zoom** overlay editor — a large zoom + pan preview of
/// the overlay (scroll / pinch to zoom, drag to pan, +/−/reset buttons) with the
/// same style/colour/slider controls down the side. Edits the SAME [spec] the
/// dialog holds; **Apply** signals the dialog to apply, **Done** just returns.
class _OverlayBigBuilder extends StatefulWidget {
  const _OverlayBigBuilder({required this.spec, required this.kind});
  final OverlaySpec spec;
  final OverlayKind kind;

  @override
  State<_OverlayBigBuilder> createState() => _OverlayBigBuilderState();
}

class _OverlayBigBuilderState extends State<_OverlayBigBuilder> {
  final TransformationController _tc = TransformationController();
  final ValueNotifier<Uint8List?> _preview = ValueNotifier<Uint8List?>(null);
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _preview.dispose();
    _tc.dispose();
    super.dispose();
  }

  /// Re-render the big (512px) overlay **debounced**, so dragging a slider
  /// doesn't re-draw + re-encode + re-decode a 512px PNG every tick.
  void _scheduleRender() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 60), _render);
  }

  void _render() {
    if (!mounted) return;
    _preview.value = Codecs.encodePng(widget.spec.build(512));
  }

  /// Scale by [factor] about the viewport centre (so +/− zoom toward the middle,
  /// like the button maker). Scroll-wheel / pinch already zoom toward the
  /// pointer via the InteractiveViewer.
  void _zoomBy(double factor, Size viewport) {
    final double current = _tc.value.getMaxScaleOnAxis();
    final double target = (current * factor).clamp(0.25, 16.0);
    final double f = target / current;
    final double cx = viewport.width / 2, cy = viewport.height / 2;
    final Matrix4 m = Matrix4.identity()
      ..translate(cx, cy)
      ..scale(f)
      ..translate(-cx, -cy);
    _tc.value = m.multiplied(_tc.value);
  }

  void _reset() => _tc.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind == OverlayKind.border
            ? 'Build a border — big editor'
            : 'Build a background — big editor'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Done'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, left: 4),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Apply'),
            ),
          ),
        ],
      ),
      body: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              color: const Color(0xFF1A1A1A),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  final Size viewport = Size(c.maxWidth, c.maxHeight);
                  return Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: InteractiveViewer(
                          transformationController: _tc,
                          minScale: 0.25,
                          maxScale: 16,
                          boundaryMargin: const EdgeInsets.all(600),
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: ValueListenableBuilder<Uint8List?>(
                                valueListenable: _preview,
                                builder: (_, Uint8List? b, __) =>
                                    CheckerImage(bytes: b),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _zoomBtn(Icons.remove_rounded, 'Zoom out',
                                () => _zoomBy(1 / 1.2, viewport)),
                            const SizedBox(width: 4),
                            _zoomBtn(Icons.add_rounded, 'Zoom in',
                                () => _zoomBy(1.2, viewport)),
                            const SizedBox(width: 4),
                            _zoomBtn(Icons.fit_screen_rounded, 'Reset view',
                                _reset),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 340,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Scroll to zoom · drag to pan. Tweak the style, colours and '
                    'sliders — the preview updates live.',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  const SizedBox(height: 12),
                  _OverlayControlsPanel(
                    spec: widget.spec,
                    kind: widget.kind,
                    onChanged: () {
                      setState(() {}); // live slider values
                      _scheduleRender(); // debounced 512px preview
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoomBtn(IconData ic, String tip, VoidCallback onTap) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tip,
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          icon: Icon(ic),
          onPressed: onTap,
        ),
      );
}

/// The shared overlay-editing controls (style, start-from-preset, colour wheels,
/// thickness/radius/inset/pattern sliders). Mutates [spec] in place and calls
/// [onChanged] so the host (dialog or big editor) rebuilds its preview. Used by
/// both so there's one set of controls, not two diverging copies.
class _OverlayControlsPanel extends StatelessWidget {
  const _OverlayControlsPanel({
    required this.spec,
    required this.kind,
    required this.onChanged,
  });
  final OverlaySpec spec;
  final OverlayKind kind;
  final VoidCallback onChanged;

  Future<void> _pickColor(
      BuildContext context, int current, ValueChanged<int> assign) async {
    Color picked = Color(0xFF000000 | (current & 0xFFFFFF));
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Pick a colour'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            enableAlpha: false,
            paletteType: PaletteType.hueWheel,
            hexInputBar: true,
            labelTypes: const <ColorLabelType>[
              ColorLabelType.hex,
              ColorLabelType.rgb,
            ],
            onColorChanged: (Color c) => picked = c,
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done')),
        ],
      ),
    );
    assign(picked.value & 0xFFFFFF);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final OverlayStyle st = spec.style;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _styleDropdown(),
        const SizedBox(height: 8),
        _startFromDropdown(),
        const Divider(),
        if (st.usesColor1)
          _colorRow(context, 'Main colour', spec.color1,
              (int v) => spec.color1 = v),
        if (st.usesColor2)
          _colorRow(context, 'Second colour', spec.color2,
              (int v) => spec.color2 = v),
        if (st.usesPattern)
          _colorRow(context, 'Pattern colour', spec.patternColor,
              (int v) => spec.patternColor = v),
        if (st == OverlayStyle.rainbow || st == OverlayStyle.rainbowFrame)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Colours are automatic for rainbow styles.',
                style: TextStyle(fontSize: 12, color: Colors.white60)),
          ),
        if (st.usesThickness)
          _slider('Thickness', spec.thickness, .01, .25,
              (double v) => spec.thickness = v),
        if (st.usesRadius)
          _slider('Corner radius', spec.radius, 0, .5,
              (double v) => spec.radius = v),
        if (st.usesInset)
          _slider('Inset', spec.inset, 0, .2, (double v) => spec.inset = v),
        if (st.usesCell)
          _slider('Pattern size', spec.cell, .12, .5,
              (double v) => spec.cell = v),
      ],
    );
  }

  Widget _styleDropdown() => InputDecorator(
        decoration: const InputDecoration(labelText: 'Style', isDense: true),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<OverlayStyle>(
            isExpanded: true,
            value: spec.style,
            items: <DropdownMenuItem<OverlayStyle>>[
              for (final OverlayStyle s in stylesForKind(kind))
                DropdownMenuItem<OverlayStyle>(value: s, child: Text(s.label)),
            ],
            onChanged: (OverlayStyle? s) {
              if (s != null) {
                spec.style = s;
                onChanged();
              }
            },
          ),
        ),
      );

  Widget _startFromDropdown() => InputDecorator(
        decoration:
            const InputDecoration(labelText: 'Start from a preset', isDense: true),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<OverlayPreset?>(
            isExpanded: true,
            value: null,
            hint: const Text('—'),
            items: <DropdownMenuItem<OverlayPreset?>>[
              const DropdownMenuItem<OverlayPreset?>(value: null, child: Text('—')),
              for (final OverlayPreset p in OverlayPresets.forKind(kind))
                DropdownMenuItem<OverlayPreset?>(
                    value: p,
                    child: Text('${p.category} · ${p.name}',
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (OverlayPreset? p) {
              if (p != null) {
                final OverlaySpec s = p.spec.copy();
                spec
                  ..style = s.style
                  ..color1 = s.color1
                  ..color2 = s.color2
                  ..patternColor = s.patternColor
                  ..thickness = s.thickness
                  ..radius = s.radius
                  ..inset = s.inset
                  ..cell = s.cell;
                onChanged();
              }
            },
          ),
        ),
      );

  Widget _colorRow(BuildContext context, String label, int color,
          ValueChanged<int> assign) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            SizedBox(
                width: 120,
                child: Text(label, style: const TextStyle(fontSize: 13))),
            GestureDetector(
              onTap: () => _pickColor(context, color, assign),
              child: Container(
                width: 40,
                height: 28,
                decoration: BoxDecoration(
                  color: Color(0xFF000000 | (color & 0xFFFFFF)),
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
                onPressed: () => _pickColor(context, color, assign),
                child: const Text('Wheel')),
          ],
        ),
      );

  Widget _slider(String label, double v, double min, double max,
          ValueChanged<double> assign) =>
      Row(
        children: <Widget>[
          SizedBox(
              width: 110,
              child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: Slider(
              value: v.clamp(min, max),
              min: min,
              max: max,
              onChanged: (double nv) {
                assign(nv);
                onChanged();
              },
            ),
          ),
        ],
      );
}
