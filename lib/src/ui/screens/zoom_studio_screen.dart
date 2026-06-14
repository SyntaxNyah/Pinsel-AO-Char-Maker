import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/ao_constants.dart';
import '../../core/emote.dart';
import '../../imaging/sprite_zoom.dart';
import '../app_state.dart';
import '../widgets/checker_image.dart';

/// **Zoom Studio** — the dead-simple "this sprite is too far away, pull it in"
/// screen. A big WYSIWYG canvas shows exactly what AO will display; the **mouse
/// wheel zooms** (toward the cursor), **drag pans**, and one **Apply** bakes the
/// framing into every frame of the sprite — or the whole cast at once, so they
/// stay aligned in-game.
///
/// Performance: the live canvas is a pure widget-layer transform of the plain
/// sprite (instant, GPU, no decode per wheel tick — see the memory note about
/// avoiding per-event re-bakes). Pixels are only touched on [AppState.applyZoom].
class ZoomStudioScreen extends StatefulWidget {
  const ZoomStudioScreen({super.key});

  @override
  State<ZoomStudioScreen> createState() => _ZoomStudioScreenState();
}

class _ZoomStudioScreenState extends State<ZoomStudioScreen> {
  // The live camera, broken into fields so a wheel tick is a cheap setState.
  double _zoom = ZoomLimits.defaultZoom;
  double _focusX = ZoomLimits.defaultFocus;
  double _focusY = ZoomLimits.defaultFocus;
  double _outputScale = 1.0;

  bool _applyAll = true; // the alignment-safe default: frame the whole cast
  bool _showGrid = true;

  Uint8List? _bytes;
  double _aspect = 1.0;
  bool _loading = true;

  /// Tracks (selectedEmote, spriteRevision) so we reload the canvas image when
  /// the user picks a different sprite or a bake changes the pixels.
  (int, int)? _lastSel;

  final FocusNode _kb = FocusNode(debugLabel: 'zoom-canvas');

  SpriteZoomSpec get _spec => SpriteZoomSpec(
        zoom: _zoom,
        focusX: _focusX,
        focusY: _focusY,
        outputScale: _outputScale,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _kb.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AppState app = context.read<AppState>();
    final ({Uint8List? bytes, double? aspect}) src =
        await app.spriteEditorSource(app.current);
    if (!mounted) return;
    setState(() {
      _bytes = src.bytes;
      _aspect = (src.aspect == null || src.aspect! <= 0) ? 1.0 : src.aspect!;
      _loading = false;
    });
  }

  void _resetCamera() {
    setState(() {
      _zoom = ZoomLimits.defaultZoom;
      _focusX = ZoomLimits.defaultFocus;
      _focusY = ZoomLimits.defaultFocus;
    });
  }

  // --- camera maths (kept here; the canvas just reports normalized coords) -----

  void _setZoom(double z) {
    setState(() =>
        _zoom = z.clamp(ZoomLimits.minZoom, ZoomLimits.maxZoom).toDouble());
  }

  /// Wheel / pinch zoom keeping the point under the cursor ([u],[v] in 0..1 of
  /// the canvas) stationary — the natural "zoom where I'm pointing" feel.
  void _zoomAt(double factor, double u, double v) {
    final double oldZoom = _zoom;
    final double newZoom =
        (oldZoom * factor).clamp(ZoomLimits.minZoom, ZoomLimits.maxZoom);
    if (newZoom == oldZoom) return;
    final double sx = _focusX + (u - 0.5) / oldZoom;
    final double sy = _focusY + (v - 0.5) / oldZoom;
    setState(() {
      _zoom = newZoom;
      _focusX = (sx - (u - 0.5) / newZoom).clamp(0.0, 1.0);
      _focusY = (sy - (v - 0.5) / newZoom).clamp(0.0, 1.0);
    });
  }

  /// Drag-pan: [du],[dv] are the drag delta as a fraction of the canvas size.
  void _pan(double du, double dv) {
    setState(() {
      _focusX = (_focusX - du / _zoom).clamp(0.0, 1.0);
      _focusY = (_focusY - dv / _zoom).clamp(0.0, 1.0);
    });
  }

  void _nudgeFocus(double dx, double dy) {
    setState(() {
      _focusX = (_focusX + dx).clamp(0.0, 1.0);
      _focusY = (_focusY + dy).clamp(0.0, 1.0);
    });
  }

  Future<void> _autoFrame() async {
    final AppState app = context.read<AppState>();
    final SpriteZoomSpec? s =
        await app.computeAutoFrame(allSprites: _applyAll);
    if (!mounted || s == null) return;
    setState(() {
      _zoom = s.zoom;
      _focusX = s.focusX;
      _focusY = s.focusY;
    });
  }

  Future<void> _apply() async {
    final AppState app = context.read<AppState>();
    final int n = await app.applyZoom(_spec, allSprites: _applyAll);
    if (n > 0) _resetCamera(); // baked in — show the new result 1:1
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Let modified combos bubble to the global shortcuts (e.g. Ctrl/⌘ + ↑/↓
    // for previous/next emote) — the canvas only claims *bare* keys.
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    const double s = ZoomLimits.focusStep;
    final LogicalKeyboardKey k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _nudgeFocus(-s, 0);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _nudgeFocus(s, 0);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _nudgeFocus(0, -s);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _nudgeFocus(0, s);
    } else if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      _setZoom(_zoom * ZoomLimits.zoomStep);
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      _setZoom(_zoom / ZoomLimits.zoomStep);
    } else if (k == LogicalKeyboardKey.digit0 ||
        k == LogicalKeyboardKey.numpad0 ||
        k == LogicalKeyboardKey.keyR) {
      _resetCamera();
    } else if (k == LogicalKeyboardKey.keyG) {
      setState(() => _showGrid = !_showGrid);
    } else if (k == LogicalKeyboardKey.keyF) {
      _autoFrame();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (int, int)>(
      selector: (_, AppState a) => (a.selectedEmote, a.spriteRevision),
      builder: (BuildContext context, (int, int) sel, _) {
        if (_lastSel != sel) {
          _lastSel = sel;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _load();
          });
        }
        final AppState app = context.read<AppState>();
        final bool hasSprite =
            app.current != null && app.spriteRelFor(app.current!) != null;
        return Row(
          children: <Widget>[
            Expanded(
              flex: 4,
              child: hasSprite
                  ? _canvasArea()
                  : const Center(
                      child: Text(
                          'Select an emote (Emotes tab) to zoom its sprite.')),
            ),
            const VerticalDivider(width: 1),
            SizedBox(width: 340, child: _controls(hasSprite)),
          ],
        );
      },
    );
  }

  Widget _canvasArea() {
    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Focus(
              focusNode: _kb,
              onKeyEvent: _onKey,
              child: Listener(
                onPointerDown: (_) => _kb.requestFocus(),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _ZoomStage(
                              bytes: _bytes,
                              aspect: _aspect,
                              zoom: _zoom,
                              focusX: _focusX,
                              focusY: _focusY,
                              showGrid: _showGrid,
                              onZoomAt: _zoomAt,
                              onPan: _pan,
                            ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _floatingZoomBar(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        _SpriteStrip(onPick: (int i) => context.read<AppState>().selectEmote(i)),
      ],
    );
  }

  Widget _floatingZoomBar() {
    Widget btn(IconData ic, String tip, VoidCallback onTap) => Material(
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('${(_zoom * 100).round()}%',
              style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 4),
        btn(Icons.remove_rounded, 'Zoom out (−)',
            () => _setZoom(_zoom / ZoomLimits.zoomStep)),
        btn(Icons.add_rounded, 'Zoom in (+)',
            () => _setZoom(_zoom * ZoomLimits.zoomStep)),
        btn(Icons.center_focus_strong_rounded, 'Reset camera (R)', _resetCamera),
        btn(
          _showGrid ? Icons.grid_on_rounded : Icons.grid_off_rounded,
          'Toggle grid (G)',
          () => setState(() => _showGrid = !_showGrid),
        ),
      ],
    );
  }

  Widget _controls(bool hasSprite) {
    final TextTheme t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Zoom Studio', style: t.titleMedium),
            const Spacer(),
            TextButton(onPressed: _resetCamera, child: const Text('Reset')),
          ],
        ),
        const Text(
          'Mouse wheel = zoom · drag = pan. Pull a too-far-away character in so '
          'it fills the AO viewport.',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
        const SizedBox(height: 12),

        // --- Zoom slider + exact box ------------------------------------------
        Text('Zoom: ${(_zoom * 100).round()}%', style: t.labelLarge),
        Row(
          children: <Widget>[
            Expanded(
              child: Slider(
                // The slider is a coarse 0.1×–8× control; the wheel / % field /
                // auto-frame can push past 8× (up to [ZoomLimits.maxZoom]), so
                // pin the displayed value to the slider's own range.
                value: _zoom.clamp(ZoomLimits.minZoom, 8.0),
                min: ZoomLimits.minZoom,
                max: 8.0,
                onChanged: _setZoom,
              ),
            ),
            SizedBox(
              width: 54,
              child: _ZoomField(zoom: _zoom, onZoom: _setZoom),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          children: <Widget>[
            for (final double z in <double>[1, 1.5, 2, 3, 4])
              OutlinedButton(
                onPressed: () => _setZoom(z),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text('${z % 1 == 0 ? z.toInt() : z}×'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: hasSprite ? _autoFrame : null,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: Text(_applyAll
              ? 'Auto-frame the whole cast'
              : 'Auto-frame this sprite'),
        ),
        const SizedBox(height: 2),
        const Text(
          'Finds the character and frames it automatically (one shared framing, '
          'so the cast stays aligned).',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
        const Divider(height: 28),

        // --- Focus nudge ------------------------------------------------------
        Text('Recenter', style: t.labelLarge),
        const SizedBox(height: 6),
        _focusPad(),
        const Divider(height: 28),

        // --- Output resolution ------------------------------------------------
        Text('Export resolution', style: t.labelLarge),
        const SizedBox(height: 2),
        const Text(
          'Keep ×1 for AO. Bake at a higher resolution for crisper results on '
          'big HD themes.',
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
        const SizedBox(height: 6),
        SegmentedButton<double>(
          segments: const <ButtonSegment<double>>[
            ButtonSegment<double>(value: 0.5, label: Text('½×')),
            ButtonSegment<double>(value: 1.0, label: Text('1×')),
            ButtonSegment<double>(value: 2.0, label: Text('2×')),
          ],
          selected: <double>{_outputScale},
          onSelectionChanged: (Set<double> s) =>
              setState(() => _outputScale = s.first),
          showSelectedIcon: false,
        ),
        const Divider(height: 28),

        // --- Apply target + button -------------------------------------------
        Text('Apply to', style: t.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: true,
              icon: Icon(Icons.groups_rounded),
              label: Text('Whole cast'),
            ),
            ButtonSegment<bool>(
              value: false,
              icon: Icon(Icons.image_rounded),
              label: Text('This sprite'),
            ),
          ],
          selected: <bool>{_applyAll},
          onSelectionChanged: (Set<bool> s) =>
              setState(() => _applyAll = s.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: hasSprite && !_spec.isNoop ? _apply : null,
          icon: const Icon(Icons.zoom_in_map_rounded),
          label: Text(_applyAll
              ? 'Apply zoom to all sprites'
              : 'Apply zoom to this sprite'),
        ),
        const SizedBox(height: 6),
        const Text(
          'The same framing is baked into every frame and every (a)/(b)/(c), so '
          'animations and the whole cast line up in-game.',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
        const SizedBox(height: 14),
        _shortcutsCard(),
      ],
    );
  }

  /// A little D-pad to recentre the camera without a steady-handed drag.
  Widget _focusPad() {
    Widget arrow(IconData ic, double dx, double dy, String tip) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(ic),
          onPressed: () => _nudgeFocus(dx, dy),
        );
    const double s = ZoomLimits.focusStep;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          arrow(Icons.keyboard_arrow_up_rounded, 0, -s, 'Up'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              arrow(Icons.keyboard_arrow_left_rounded, -s, 0, 'Left'),
              IconButton(
                tooltip: 'Centre',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.center_focus_weak_rounded),
                onPressed: () => setState(() {
                  _focusX = 0.5;
                  _focusY = 0.5;
                }),
              ),
              arrow(Icons.keyboard_arrow_right_rounded, s, 0, 'Right'),
            ],
          ),
          arrow(Icons.keyboard_arrow_down_rounded, 0, s, 'Down'),
        ],
      ),
    );
  }

  Widget _shortcutsCard() {
    const List<List<String>> rows = <List<String>>[
      <String>['Wheel', 'Zoom toward the cursor'],
      <String>['Drag', 'Pan the camera'],
      <String>['+ / −', 'Zoom in / out'],
      <String>['Arrows', 'Recenter'],
      <String>['R / 0', 'Reset camera'],
      <String>['G', 'Toggle grid'],
      <String>['F', 'Auto-frame'],
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('On the canvas',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 4),
          for (final List<String> r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 60,
                    child: Text(r[0],
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Text(r[1],
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white60)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A typeable zoom-percent field kept in sync with the slider.
class _ZoomField extends StatefulWidget {
  const _ZoomField({required this.zoom, required this.onZoom});
  final double zoom;
  final ValueChanged<double> onZoom;

  @override
  State<_ZoomField> createState() => _ZoomFieldState();
}

class _ZoomFieldState extends State<_ZoomField> {
  late final TextEditingController _c =
      TextEditingController(text: _pct().toString());
  final FocusNode _f = FocusNode();

  int _pct() => (widget.zoom * 100).round();

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (!_f.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_ZoomField old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != _pct().toString()) {
      _c.text = _pct().toString();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  void _commit() {
    final int? pct = int.tryParse(_c.text.trim());
    if (pct == null) {
      _c.text = _pct().toString();
      return;
    }
    widget.onZoom(pct / 100);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _f,
      textAlign: TextAlign.right,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(isDense: true, suffixText: '%'),
      onSubmitted: (_) => _commit(),
    );
  }
}

/// The live WYSIWYG canvas: shows the plain sprite under a normalized camera
/// transform (wheel zoom + drag pan), a checker backdrop for transparent margin,
/// and an optional rule-of-thirds grid. Pure widget layer — no re-encode.
class _ZoomStage extends StatefulWidget {
  const _ZoomStage({
    required this.bytes,
    required this.aspect,
    required this.zoom,
    required this.focusX,
    required this.focusY,
    required this.showGrid,
    required this.onZoomAt,
    required this.onPan,
  });

  final Uint8List? bytes;
  final double aspect;
  final double zoom;
  final double focusX;
  final double focusY;
  final bool showGrid;

  /// (wheel factor, cursor-u 0..1, cursor-v 0..1).
  final void Function(double factor, double u, double v) onZoomAt;

  /// (drag-du as fraction of width, drag-dv as fraction of height).
  final void Function(double du, double dv) onPan;

  @override
  State<_ZoomStage> createState() => _ZoomStageState();
}

class _ZoomStageState extends State<_ZoomStage> {
  double _rw = 1, _rh = 1; // the fitted output rect (set each build)

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        double rw = c.maxWidth;
        double rh = rw / widget.aspect;
        if (rh > c.maxHeight) {
          rh = c.maxHeight;
          rw = rh * widget.aspect;
        }
        _rw = rw;
        _rh = rh;
        final double dispW = rw * widget.zoom;
        final double dispH = rh * widget.zoom;
        final double left = rw * 0.5 - widget.focusX * dispW;
        final double top = rh * 0.5 - widget.focusY * dispH;
        return Center(
          child: SizedBox(
            width: rw,
            height: rh,
            child: Listener(
              onPointerSignal: (PointerSignalEvent e) {
                if (e is PointerScrollEvent && _rw > 0 && _rh > 0) {
                  final double factor = e.scrollDelta.dy < 0
                      ? ZoomLimits.wheelStep
                      : 1 / ZoomLimits.wheelStep;
                  widget.onZoomAt(factor, e.localPosition.dx / _rw,
                      e.localPosition.dy / _rh);
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (DragUpdateDetails d) {
                  if (_rw > 0 && _rh > 0) {
                    widget.onPan(d.delta.dx / _rw, d.delta.dy / _rh);
                  }
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                  ),
                  child: ClipRect(
                    child: Stack(
                      children: <Widget>[
                        const Positioned.fill(child: CheckerImage(bytes: null)),
                        Positioned(
                          left: left,
                          top: top,
                          width: dispW,
                          height: dispH,
                          child: CheckerImage(
                              bytes: widget.bytes, fit: BoxFit.fill),
                        ),
                        if (widget.showGrid)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(painter: _GridPainter()),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Rule-of-thirds + centre crosshair over the output rect (a framing guide).
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..strokeWidth = 1;
    for (int i = 1; i < 3; i++) {
      final double x = size.width * i / 3;
      final double y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final Paint cross = Paint()
      ..color = Colors.pinkAccent.withOpacity(0.5)
      ..strokeWidth = 1;
    final Offset c = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(c - const Offset(8, 0), c + const Offset(8, 0), cross);
    canvas.drawLine(c - const Offset(0, 8), c + const Offset(0, 8), cross);
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

/// Horizontal strip of every emote's sprite — the "grid" of poses to pick from.
/// Tap a thumbnail to switch which sprite the canvas is framing.
class _SpriteStrip extends StatelessWidget {
  const _SpriteStrip({required this.onPick});
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (BuildContext context, AppState app, _) {
        final List<Emote> emotes = app.character?.emotes ?? <Emote>[];
        final List<int> withSprite = <int>[
          for (int i = 0; i < emotes.length; i++)
            if (app.spriteRelFor(emotes[i]) != null) i,
        ];
        if (withSprite.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 84,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: withSprite.length,
            itemBuilder: (BuildContext context, int j) {
              final int i = withSprite[j];
              final bool selected = i == app.selectedEmote;
              final String? rel = app.spriteRelFor(emotes[i]);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  onTap: () => onPick(i),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? Colors.pinkAccent
                            : Colors.white24,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: rel == null
                        ? const SizedBox.shrink()
                        : _StripThumb(rel: rel),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _StripThumb extends StatefulWidget {
  const _StripThumb({required this.rel});
  final String rel;

  @override
  State<_StripThumb> createState() => _StripThumbState();
}

class _StripThumbState extends State<_StripThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_StripThumb old) {
    super.didUpdateWidget(old);
    if (old.rel != widget.rel) _load();
  }

  Future<void> _load() async {
    final Uint8List? b =
        await context.read<AppState>().previewSprite(widget.rel, maxEdge: 96);
    if (mounted) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return const Center(
        child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return CheckerImage(bytes: _bytes, fit: BoxFit.contain);
  }
}
