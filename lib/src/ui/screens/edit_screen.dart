import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ao_constants.dart';
import '../../imaging/sprite_edit.dart';
import '../app_state.dart';
import '../widgets/zoom_canvas.dart';

/// Crop / **grow** / auto-trim / background-removal for the selected sprite (or
/// all). Live, debounced preview decoupled from widget rebuilds.
///
/// Each side has ONE bidirectional control: drag right (positive) to **crop**
/// that edge inward, drag left (negative) to **grow** the canvas outward with
/// transparent margin. Small `−` / `+` stepper buttons beside each slider give
/// pixel-precise nudges without a steady-handed drag. A *This sprite / All
/// sprites* toggle decides what one Apply press bakes.
class EditScreen extends StatefulWidget {
  const EditScreen({super.key});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  /// Per-side amount, signed: **> 0 crops** that edge in (0..maxCrop), **< 0
  /// grows** the canvas out on that edge (0..-maxPad). 0 leaves the side alone.
  double _l = 0, _t = 0, _r = 0, _b = 0;
  bool _autoTrim = false;
  bool _removeBg = false;
  bool _despill = false;
  double _tol = 40;

  /// Resize: per-axis scale factors (1.0 = unchanged), whether width/height are
  /// locked together, and the current sprite's pixel size (for the px fields).
  double _scaleX = 1.0, _scaleY = 1.0;
  bool _lockAspect = true;
  int _origW = 0, _origH = 0;

  /// Apply target: false = just the selected emote's sprite, true = every
  /// sprite. Surfaced as a toggle so it's obvious which one Apply will hit.
  bool _applyAll = false;

  final ValueNotifier<Uint8List?> _preview = ValueNotifier<Uint8List?>(null);
  Timer? _debounce;

  static double _crop(double v) => v > 0 ? v : 0;
  static double _pad(double v) => v < 0 ? -v : 0;

  SpriteEditSpec get _spec => SpriteEditSpec(
        cropLeft: _crop(_l),
        cropTop: _crop(_t),
        cropRight: _crop(_r),
        cropBottom: _crop(_b),
        padLeft: _pad(_l),
        padTop: _pad(_t),
        padRight: _pad(_r),
        padBottom: _pad(_b),
        autoTrim: _autoTrim,
        removeBgCorners: _removeBg,
        despillEdges: _removeBg && _despill,
        bgTolerance: _tol,
        scaleX: _scaleX,
        scaleY: _scaleY,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _compute();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _preview.dispose();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _compute);
  }

  Future<void> _compute() async {
    final AppState app = context.read<AppState>();
    final String? rel = app.current == null ? null : app.spriteRelFor(app.current!);
    if (rel == null) {
      _preview.value = null;
      return;
    }
    // Keep the sprite's real pixel size handy so the resize px fields are exact.
    final ({int w, int h})? size = await app.currentSpriteSize();
    if (mounted && size != null && (size.w != _origW || size.h != _origH)) {
      setState(() {
        _origW = size.w;
        _origH = size.h;
      });
    }
    final Uint8List? bytes = await app.previewEdit(rel, _spec);
    if (mounted) _preview.value = bytes;
  }

  void _reset() {
    setState(() {
      _l = _t = _r = _b = 0;
      _autoTrim = false;
      _removeBg = false;
      _despill = false;
      _scaleX = 1.0;
      _scaleY = 1.0;
    });
    _schedule();
  }

  void _setScaleX(double sx) {
    final double v = sx.clamp(0.05, 8.0);
    setState(() {
      _scaleX = v;
      if (_lockAspect) _scaleY = v;
    });
    _schedule();
  }

  void _setScaleY(double sy) {
    final double v = sy.clamp(0.05, 8.0);
    setState(() {
      _scaleY = v;
      if (_lockAspect) _scaleX = v;
    });
    _schedule();
  }

  Future<void> _apply() async {
    final AppState app = context.read<AppState>();
    await app.applyEdit(_spec, allSprites: _applyAll);
    _reset(); // baked in; show the result
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.read<AppState>();
    final bool hasSprite =
        app.current != null && app.spriteRelFor(app.current!) != null;

    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: hasSprite
                ? ValueListenableBuilder<Uint8List?>(
                    valueListenable: _preview,
                    builder: (_, Uint8List? b, __) => ZoomCanvas(bytes: b),
                  )
                : const Center(
                    child: Text('Select an emote (Emotes tab) to edit its sprite.')),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(width: 380, child: _controls()),
      ],
    );
  }

  Widget _controls() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Row(children: <Widget>[
          Text('Edit sprite', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          TextButton(onPressed: _reset, child: const Text('Reset')),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-trim transparent margins'),
          value: _autoTrim,
          onChanged: (bool v) {
            setState(() => _autoTrim = v);
            _schedule();
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Remove background'),
          subtitle: const Text('flood-fill from the corners'),
          value: _removeBg,
          onChanged: (bool v) {
            setState(() => _removeBg = v);
            _schedule();
          },
        ),
        if (_removeBg)
          _simpleSlider('BG tolerance', _tol, 0, 120,
              (double v) => _tol = v, label: _tol.round().toString()),
        if (_removeBg)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Despill soft edges'),
            subtitle: const Text(
                'un-tint hair/edge pixels so they keep no background halo'),
            value: _despill,
            onChanged: (bool v) {
              setState(() => _despill = v);
              _schedule();
            },
          ),
        const Divider(height: 24),
        Text('Crop / grow each side', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 2),
        const Text(
          'Drag right to crop the edge in, left to grow the canvas out '
          '(transparent). Use −/+ for 1% nudges.',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
        const SizedBox(height: 4),
        _sideControl('Left', _l, (double v) => _l = v),
        _sideControl('Top', _t, (double v) => _t = v),
        _sideControl('Right', _r, (double v) => _r = v),
        _sideControl('Bottom', _b, (double v) => _b = v),
        const Divider(height: 24),
        _resizeControls(),
        const Divider(height: 24),
        Text('Apply to', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: false,
              icon: Icon(Icons.image_rounded),
              label: Text('This sprite'),
            ),
            ButtonSegment<bool>(
              value: true,
              icon: Icon(Icons.select_all_rounded),
              label: Text('All sprites'),
            ),
          ],
          selected: <bool>{_applyAll},
          onSelectionChanged: (Set<bool> s) => setState(() => _applyAll = s.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _apply,
          icon: Icon(_applyAll
              ? Icons.select_all_rounded
              : Icons.crop_rounded),
          label: Text(_applyAll ? 'Apply to all sprites' : 'Apply to this sprite'),
        ),
        const SizedBox(height: 6),
        const Text(
          'Crop / grow / resize / auto-trim apply the same box and scale to every '
          'frame and to (a)/(b)/(c) of an emote, so animations and idle/talk stay '
          'aligned.',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
      ],
    );
  }

  /// A bidirectional crop/grow control for one side: a centred slider (negative
  /// = grow, positive = crop) flanked by `−` / `+` stepper buttons (the QoL
  /// mouse nudges). The label spells out which way it's going.
  Widget _sideControl(String name, double v, void Function(double) assign) {
    const double min = -CropLimits.maxPadFraction;
    const double max = CropLimits.maxCropFraction;
    final double cur = v.clamp(min, max);

    void apply(double nv) {
      setState(() => assign(nv.clamp(min, max)));
      _schedule();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('$name: ${_sideLabel(cur)}'),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Grow / less crop (−1%)',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () => apply(cur - CropLimits.stepFraction),
              ),
              Expanded(
                child: Slider(
                  value: cur,
                  min: min,
                  max: max,
                  onChanged: apply,
                ),
              ),
              IconButton(
                tooltip: 'Crop / less grow (+1%)',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: () => apply(cur + CropLimits.stepFraction),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _sideLabel(double v) {
    if (v > 0.0005) return '${(v * 100).round()}% crop';
    if (v < -0.0005) return '${(-v * 100).round()}% grow';
    return '0% (unchanged)';
  }

  /// Resize the whole sprite — by **width and height**, with a slider, `−/+`
  /// steppers, AND a typeable exact-pixel box for each axis. Lock the aspect
  /// ratio to scale both together, or unlock to stretch independently.
  Widget _resizeControls() {
    final int targetW = (_origW * _scaleX).round();
    final int targetH = (_origH * _scaleY).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Resize the whole image',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 2),
        Text(
          _origW > 0
              ? 'Original ${_origW}×$_origH px  →  new ${targetW}×$targetH px. '
                  'Drag the slider, use −/+, or type the exact pixels.'
              : 'Select a sprite to resize it.',
          style: const TextStyle(fontSize: 12, color: Colors.white60),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Lock aspect ratio'),
          subtitle: const Text('keep width & height in proportion'),
          value: _lockAspect,
          onChanged: (bool v) => setState(() => _lockAspect = v),
        ),
        _ResizeAxis(
          label: 'Width',
          scale: _scaleX,
          origPx: _origW,
          onScale: _setScaleX,
        ),
        _ResizeAxis(
          label: 'Height',
          scale: _scaleY,
          origPx: _origH,
          onScale: _setScaleY,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            children: <Widget>[
              for (final int pct in <int>[25, 50, 100, 150, 200])
                OutlinedButton(
                  onPressed: () => _setScaleX(pct / 100),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text('$pct%'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _simpleSlider(String name, double v, double min, double max,
      void Function(double) assign, {String? label}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$name: ${label ?? '${(v * 100).round()}%'}'),
        Slider(
          value: v.clamp(min, max),
          min: min,
          max: max,
          onChanged: (double nv) {
            setState(() => assign(nv));
            _schedule();
          },
        ),
      ],
    );
  }
}

/// One resize axis (Width or Height): a **slider** + **−/+ steppers** (mouse)
/// and a **typeable exact-pixel box** (numbers), all driving the same
/// [onScale] (a new scale factor). The px box shows `origPx × scale` and, when
/// you type an exact pixel size, converts it back to a scale factor.
class _ResizeAxis extends StatefulWidget {
  const _ResizeAxis({
    required this.label,
    required this.scale,
    required this.origPx,
    required this.onScale,
  });
  final String label;
  final double scale;
  final int origPx;
  final ValueChanged<double> onScale;

  @override
  State<_ResizeAxis> createState() => _ResizeAxisState();
}

class _ResizeAxisState extends State<_ResizeAxis> {
  late final TextEditingController _ctrl =
      TextEditingController(text: _px().toString());
  final FocusNode _focus = FocusNode();

  int _px() => (widget.origPx * widget.scale).round();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_ResizeAxis old) {
    super.didUpdateWidget(old);
    // Reflect slider / external changes in the field unless it's being edited.
    if (!_focus.hasFocus && _ctrl.text != _px().toString()) {
      _ctrl.text = _px().toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final int? px = int.tryParse(_ctrl.text.trim());
    if (px == null || widget.origPx <= 0) {
      _ctrl.text = _px().toString(); // revert garbage
      return;
    }
    widget.onScale(px / widget.origPx);
  }

  @override
  Widget build(BuildContext context) {
    final double s = widget.scale;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${widget.label}: ${(s * 100).round()}%'),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Smaller (−5%)',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () => widget.onScale(s - 0.05),
              ),
              Expanded(
                child: Slider(
                  value: s.clamp(0.1, 4.0),
                  min: 0.1,
                  max: 4.0,
                  onChanged: widget.onScale,
                ),
              ),
              IconButton(
                tooltip: 'Bigger (+5%)',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: () => widget.onScale(s + 0.05),
              ),
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'px',
                  ),
                  onSubmitted: (_) => _commit(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
