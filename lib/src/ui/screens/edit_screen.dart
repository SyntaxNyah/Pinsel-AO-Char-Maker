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
  double _tol = 40;

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
        bgTolerance: _tol,
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
    final Uint8List? bytes = await app.previewEdit(rel, _spec);
    if (mounted) _preview.value = bytes;
  }

  void _reset() {
    setState(() {
      _l = _t = _r = _b = 0;
      _autoTrim = false;
      _removeBg = false;
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
          'Crop / grow / auto-trim apply the same box to every frame and to '
          '(a)/(b)/(c) of an emote, so animations and idle/talk stay aligned.',
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
