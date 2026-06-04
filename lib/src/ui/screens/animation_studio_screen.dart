import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Easing; // our Easing (Flutter 3.29+ also has one)
import 'package:provider/provider.dart';

import '../../animation/anim_engine.dart';
import '../../animation/easing.dart';
import '../../animation/lipsync.dart';
import '../../plugins/extension_registry.dart';
import '../../presets/presets.dart';
import '../app_state.dart';
import '../widgets/checker_image.dart';

/// The three studio workflows.
enum _StudioMode { effects, mouth, frames }

/// Animation studio with two modes:
///  * **Effects** — one-click procedural recipes (sway, glow, …), stackable.
///  * **Frames** — classic frame-by-frame: pick sprite frames in order and
///    assemble them into one animation (fps, reverse, ping-pong, alignment).
///
/// Performance: rendering is debounced and the looping playback only updates a
/// [ValueNotifier] (so it doesn't rebuild the whole screen each frame); the long
/// preset/effect chip lists are built once.
class AnimationStudioScreen extends StatefulWidget {
  const AnimationStudioScreen({super.key});

  @override
  State<AnimationStudioScreen> createState() => _AnimationStudioScreenState();
}

class _AnimationStudioScreenState extends State<AnimationStudioScreen> {
  // shared
  _StudioMode _mode = _StudioMode.effects;
  int _fps = 12;

  // effects mode
  final List<AnimRecipe> _recipes = <AnimRecipe>[];
  int _frames = 16;
  String _ease = 'linear';
  Widget? _presetChips;
  Widget? _effectChips;

  // mouth (lip-sync) mode
  MouthRegion _mouth = const MouthRegion(0.32, 0.40, 0.36, 0.07);
  double _openAmount = LipSync.defaultOpenAmount;
  int _mouthFrames = 8;
  double? _mouthAspect; // selected sprite w/h, for the region overlay box
  String? _mouthSeededRel; // sprite the auto mouth box was last seeded for

  // frames mode
  final List<String> _seq = <String>[];
  bool _reverse = false;
  bool _pingPong = false;
  int _align = 2; // 0 top · 1 center · 2 bottom
  final TextEditingController _frameName = TextEditingController(text: 'frames');

  // playback
  List<Uint8List> _frameImgs = <Uint8List>[];
  final ValueNotifier<int> _frameIdx = ValueNotifier<int>(0);
  Timer? _player;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _render();
    });
  }

  @override
  void dispose() {
    _player?.cancel();
    _debounce?.cancel();
    _frameIdx.dispose();
    _frameName.dispose();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), _render);
  }

  Future<void> _render() async {
    final AppState app = context.read<AppState>();
    final List<Uint8List> imgs;
    if (_mode == _StudioMode.frames) {
      imgs = await app.renderFrameSequence(_seq,
          fps: _fps, reverse: _reverse, pingPong: _pingPong, align: _align);
    } else if (_mode == _StudioMode.mouth) {
      await _ensureMouthSeed(app);
      imgs = await app.previewMouthTalk(_mouth,
          frames: _mouthFrames, fps: _fps, openAmount: _openAmount);
    } else {
      final int n = _recipes.isEmpty ? 1 : _frames;
      imgs = await app.renderAnimationPreview(_recipes, frames: n, fps: _fps);
    }
    if (!mounted) return;
    _player?.cancel();
    setState(() => _frameImgs = imgs);
    _frameIdx.value = 0;
    if (imgs.length > 1) {
      _player = Timer.periodic(
        Duration(milliseconds: (1000 / _fps).round()),
        (_) {
          if (_frameImgs.isEmpty) return;
          _frameIdx.value = (_frameIdx.value + 1) % _frameImgs.length;
        },
      );
    }
  }

  // ---- effects-mode actions ----
  void _applyPreset(AnimPreset preset) {
    setState(() {
      _recipes
        ..clear()
        ..addAll(preset.recipes);
      _frames = preset.frames;
      _fps = preset.fps;
    });
    _schedule();
  }

  void _addRecipe(String type) {
    setState(() => _recipes.add(AnimRecipe(type,
        p: <String, double>{'intensity': 6, 'cycles': 1}, ease: _ease)));
    _schedule();
  }

  /// Confirm, then render the current effect stack onto **every** sprite and
  /// save each as an animated WebP (b) talk sprite.
  Future<void> _animateAll(AppState app) async {
    final int count = app.spriteBases().length;
    final String stack = _recipes.map((AnimRecipe r) => r.type).join(' + ');
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Animate all sprites?'),
        content: Text(
          'Render this effect stack ($stack) onto all $count sprite(s) and save '
          'each as an animated WebP (b) talk sprite, replacing any existing talk '
          'sprite. This bakes at full resolution and may take a moment.',
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Animate all')),
        ],
      ),
    );
    if (go != true) return;
    await app.bulkAnimateAll(_recipes, frames: _frames, fps: _fps, prefix: '(b)');
  }

  // ---- frames-mode actions ----
  void _addFrame(String rel) {
    setState(() => _seq.add(rel));
    _schedule();
  }

  void _moveFrame(int i, int delta) {
    final int j = i + delta;
    if (j < 0 || j >= _seq.length) return;
    setState(() {
      final String t = _seq[i];
      _seq[i] = _seq[j];
      _seq[j] = t;
    });
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.read<AppState>();
    _presetChips ??= _buildPresetChips();
    _effectChips ??= _buildEffectChips();

    final bool empty =
        _mode == _StudioMode.frames ? _seq.isEmpty : app.current == null;
    final String emptyMsg = _mode == _StudioMode.frames
        ? 'Add frames on the right →'
        : 'Select an emote to animate it.';

    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: empty
                      ? Center(child: Text(emptyMsg))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _previewContent(),
                        ),
                ),
                const SizedBox(height: 8),
                Text(_statusLine()),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(width: 380, child: _controls(app)),
      ],
    );
  }

  String _statusLine() {
    switch (_mode) {
      case _StudioMode.frames:
        return '${_seq.length} frame(s)  ·  ${_frameImgs.length} shown';
      case _StudioMode.mouth:
        return 'Talking mouth preview — drag the box onto the lips →';
      case _StudioMode.effects:
        return _recipes.isEmpty
            ? 'No effects yet — pick a preset or add effects →'
            : 'Stack: ${_recipes.map((AnimRecipe r) => r.type).join(" + ")}';
    }
  }

  /// The looping preview. In Mouth mode it overlays the adjustable mouth box
  /// (aligned to the sprite via [_mouthAspect]) so you can see exactly what's
  /// being animated and nudge it onto the lips.
  Widget _previewContent() {
    return ValueListenableBuilder<int>(
      valueListenable: _frameIdx,
      builder: (_, int idx, __) {
        final Uint8List? b =
            _frameImgs.isEmpty ? null : _frameImgs[idx % _frameImgs.length];
        if (_mode != _StudioMode.mouth || _mouthAspect == null) {
          return CheckerImage(bytes: b);
        }
        return Center(
          child: AspectRatio(
            aspectRatio: _mouthAspect!,
            child: LayoutBuilder(
              builder: (_, BoxConstraints c) {
                final double w = c.maxWidth, h = c.maxHeight;
                return Stack(
                  children: <Widget>[
                    Positioned.fill(
                        child: CheckerImage(bytes: b, fit: BoxFit.fill)),
                    Positioned(
                      left: (_mouth.x * w).clamp(0.0, w),
                      top: (_mouth.y * h).clamp(0.0, h),
                      width: (_mouth.w * w).clamp(1.0, w),
                      height: (_mouth.h * h).clamp(1.0, h),
                      child: const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0x22FF4081),
                            border: Border.fromBorderSide(
                                BorderSide(color: Color(0xFFFF4081), width: 2)),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _controls(AppState app) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        SegmentedButton<_StudioMode>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<_StudioMode>>[
            ButtonSegment<_StudioMode>(
                value: _StudioMode.effects,
                label: Text('Effects'),
                icon: Icon(Icons.auto_awesome)),
            ButtonSegment<_StudioMode>(
                value: _StudioMode.mouth,
                label: Text('Mouth'),
                icon: Icon(Icons.record_voice_over_outlined)),
            ButtonSegment<_StudioMode>(
                value: _StudioMode.frames,
                label: Text('Frames'),
                icon: Icon(Icons.burst_mode_outlined)),
          ],
          selected: <_StudioMode>{_mode},
          onSelectionChanged: (Set<_StudioMode> s) {
            setState(() => _mode = s.first);
            _schedule();
          },
        ),
        const SizedBox(height: 12),
        ...switch (_mode) {
          _StudioMode.frames => _frameControls(app),
          _StudioMode.mouth => _mouthControls(app),
          _StudioMode.effects => _effectControls(app),
        },
      ],
    );
  }

  // ===========================================================================
  // Frames mode
  // ===========================================================================
  List<Widget> _frameControls(AppState app) {
    final List<({String rel, String label})> files = app.spriteFiles();
    return <Widget>[
      Text('Frame-by-frame', style: Theme.of(context).textTheme.titleMedium),
      const Text(
        'Pick sprite frames in order, then save them as one animation. '
        'Different-sized frames are auto-aligned onto a shared canvas.',
        style: TextStyle(fontSize: 12, color: Colors.white60),
      ),
      const SizedBox(height: 8),
      _fpsSlider(),
      Row(children: <Widget>[
        Expanded(
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Reverse', style: TextStyle(fontSize: 13)),
            value: _reverse,
            onChanged: (bool v) {
              setState(() => _reverse = v);
              _schedule();
            },
          ),
        ),
        Expanded(
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Ping-pong', style: TextStyle(fontSize: 13)),
            value: _pingPong,
            onChanged: (bool v) {
              setState(() => _pingPong = v);
              _schedule();
            },
          ),
        ),
      ]),
      Row(children: <Widget>[
        const Text('Align:'),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: _align,
          items: const <DropdownMenuItem<int>>[
            DropdownMenuItem<int>(value: 2, child: Text('Bottom (floor)')),
            DropdownMenuItem<int>(value: 1, child: Text('Center')),
            DropdownMenuItem<int>(value: 0, child: Text('Top')),
          ],
          onChanged: (int? v) {
            if (v == null) return;
            setState(() => _align = v);
            _schedule();
          },
        ),
      ]),
      const Divider(height: 24),

      // the ordered sequence
      Row(children: <Widget>[
        Expanded(
          child: Text('Sequence (${_seq.length})',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        if (_seq.isNotEmpty)
          TextButton(
            onPressed: () {
              setState(() => _seq.clear());
              _schedule();
            },
            child: const Text('Clear'),
          ),
      ]),
      if (_seq.isEmpty)
        const Text('No frames yet — tap a sprite below to add it.',
            style: TextStyle(fontSize: 12, color: Colors.orange))
      else
        for (int i = 0; i < _seq.length; i++) _seqRow(i),
      const SizedBox(height: 8),
      const Divider(height: 24),

      // name + save
      TextField(
        controller: _frameName,
        decoration: const InputDecoration(labelText: 'Animation name'),
      ),
      const SizedBox(height: 8),
      Row(children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: _seq.length < 2
                ? null
                : () => app.saveFrameSequence(_seq,
                    fps: _fps,
                    reverse: _reverse,
                    pingPong: _pingPong,
                    align: _align,
                    prefix: '(b)',
                    name: _frameName.text),
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save as (b) talk'),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Save as (a) idle',
          onPressed: _seq.length < 2
              ? null
              : () => app.saveFrameSequence(_seq,
                  fps: _fps,
                  reverse: _reverse,
                  pingPong: _pingPong,
                  align: _align,
                  prefix: '(a)',
                  name: _frameName.text),
          icon: const Icon(Icons.bedtime_outlined),
        ),
      ]),
      if (_seq.length < 2)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Add at least 2 frames to save.',
              style: TextStyle(fontSize: 12, color: Colors.white60)),
        ),
      const Divider(height: 24),

      // source files
      Text('Add frames', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      if (files.isEmpty)
        const Text('Import sprites first (Home).', style: TextStyle(fontSize: 12))
      else
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final ({String rel, String label}) f in files)
              ActionChip(
                label: Text(_leaf(f.label), overflow: TextOverflow.ellipsis),
                onPressed: () => _addFrame(f.rel),
              ),
          ],
        ),
      const SizedBox(height: 24),
    ];
  }

  Widget _seqRow(int i) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: <Widget>[
          SizedBox(width: 22, child: Text('${i + 1}.', style: const TextStyle(fontSize: 12))),
          Expanded(child: Text(_leaf(_seq[i]), overflow: TextOverflow.ellipsis)),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Up',
            icon: const Icon(Icons.keyboard_arrow_up, size: 18),
            onPressed: i == 0 ? null : () => _moveFrame(i, -1),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Down',
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            onPressed: i == _seq.length - 1 ? null : () => _moveFrame(i, 1),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Duplicate (hold longer)',
            icon: const Icon(Icons.copy_all_outlined, size: 16),
            onPressed: () {
              setState(() => _seq.insert(i + 1, _seq[i]));
              _schedule();
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 16),
            onPressed: () {
              setState(() => _seq.removeAt(i));
              _schedule();
            },
          ),
        ],
      ),
    );
  }

  String _leaf(String rel) => rel.split('/').last;

  // ===========================================================================
  // Mouth (lip-sync) mode
  // ===========================================================================
  List<Widget> _mouthControls(AppState app) {
    return <Widget>[
      Text('Talking mouth', style: Theme.of(context).textTheme.titleMedium),
      const Text(
        'Fake a talking (b) animation from this one drawing — no extra art '
        'needed. The pink box is the mouth: the jaw drops there with a natural, '
        'looping cadence. Watch the preview loop and nudge the box onto the lips.',
        style: TextStyle(fontSize: 12, color: Colors.white60),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => _autoPlaceMouth(app),
        icon: const Icon(Icons.center_focus_strong_outlined),
        label: const Text('Auto-place on face'),
      ),
      const SizedBox(height: 4),
      _mouthSlider('Mouth X', _mouth.x,
          (double v) => _mouth = _mouth.copyWith(x: v)),
      _mouthSlider('Mouth Y', _mouth.y,
          (double v) => _mouth = _mouth.copyWith(y: v)),
      _mouthSlider('Width', _mouth.w,
          (double v) => _mouth = _mouth.copyWith(w: v),
          min: 0.02, max: 0.9),
      _mouthSlider('Height', _mouth.h,
          (double v) => _mouth = _mouth.copyWith(h: v),
          min: 0.01, max: 0.5),
      const SizedBox(height: 4),
      Text('Open amount: ${_openAmount.toStringAsFixed(2)}'),
      Slider(
        value: _openAmount.clamp(0.05, 0.8),
        min: 0.05,
        max: 0.8,
        onChanged: (double v) {
          setState(() => _openAmount = v);
          _schedule();
        },
      ),
      Text('Frames: $_mouthFrames'),
      Slider(
        value: _mouthFrames.toDouble(),
        min: 2,
        max: 16,
        divisions: 14,
        onChanged: (double v) {
          setState(() => _mouthFrames = v.round());
          _schedule();
        },
      ),
      _fpsSlider(),
      const SizedBox(height: 8),
      Row(children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: app.current == null
                ? null
                : () => app.saveMouthTalk(_mouth,
                    frames: _mouthFrames,
                    fps: _fps,
                    openAmount: _openAmount,
                    prefix: '(b)'),
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save as (b) talk'),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Save as (a) idle',
          onPressed: app.current == null
              ? null
              : () => app.saveMouthTalk(_mouth,
                  frames: _mouthFrames,
                  fps: _fps,
                  openAmount: _openAmount,
                  prefix: '(a)'),
          icon: const Icon(Icons.bedtime_outlined),
        ),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: !app.hasProject ? null : () => _mouthAll(app),
          icon: const Icon(Icons.auto_awesome_motion),
          label: const Text('Talking mouth on ALL sprites'),
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Text(
          'Gives every sprite its own face-placed talking mouth and saves each '
          'as an animated WebP (b) sprite — baked across all CPU cores.',
          style: TextStyle(fontSize: 11, color: Colors.white60),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  Widget _mouthSlider(String label, double value, void Function(double) assign,
      {double min = 0.0, double max = 1.0}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$label: ${(value * 100).round()}%'),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: (double v) {
            setState(() => assign(v));
            _schedule();
          },
        ),
      ],
    );
  }

  /// Reset the mouth box to the face-derived default for the current sprite.
  Future<void> _autoPlaceMouth(AppState app) async {
    final String? rel =
        app.current == null ? null : app.spriteRelFor(app.current!);
    if (rel == null) return;
    final MouthRegion? region = await app.defaultMouthRegionFor(rel);
    if (!mounted || region == null) return;
    setState(() => _mouth = region);
    _schedule();
  }

  /// Seed the mouth box + sprite aspect the first time we show a given sprite,
  /// so the box starts on the face and the overlay is correctly proportioned.
  Future<void> _ensureMouthSeed(AppState app) async {
    final String? rel =
        app.current == null ? null : app.spriteRelFor(app.current!);
    if (rel == null) return;
    if (_mouthSeededRel == rel && _mouthAspect != null) return;
    final MouthRegion? region = await app.defaultMouthRegionFor(rel);
    final double? aspect = await app.currentSpriteAspect();
    if (!mounted) return;
    setState(() {
      if (region != null) _mouth = region;
      _mouthAspect = aspect;
      _mouthSeededRel = rel;
    });
  }

  Future<void> _mouthAll(AppState app) async {
    final int count = app.spriteBases().length;
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Talking mouth on all sprites?'),
        content: Text(
          'Give all $count sprite(s) a face-placed talking mouth and save each '
          'as an animated WebP (b) talk sprite, replacing any existing talk '
          'sprite. Bakes at full resolution across all CPU cores.',
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Do all')),
        ],
      ),
    );
    if (go != true) return;
    await app.bulkMouthTalkAll(
        frames: _mouthFrames, fps: _fps, openAmount: _openAmount, prefix: '(b)');
  }

  // ===========================================================================
  // Effects mode
  // ===========================================================================
  List<Widget> _effectControls(AppState app) {
    return <Widget>[
      Text('Frames: $_frames'),
      Slider(
        value: _frames.toDouble(),
        min: 2,
        max: 48,
        divisions: 46,
        onChanged: (double v) {
          setState(() => _frames = v.round());
          _schedule();
        },
      ),
      _fpsSlider(),
      Row(children: <Widget>[
        const Text('Easing:'),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value: _ease,
            items: <DropdownMenuItem<String>>[
              for (final String e in Easing.names)
                DropdownMenuItem<String>(value: e, child: Text(e)),
            ],
            onChanged: (String? e) {
              if (e == null) return;
              setState(() {
                _ease = e;
                for (final AnimRecipe r in _recipes) {
                  r.ease = e;
                }
              });
              _schedule();
            },
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: _recipes.isEmpty
                ? null
                : () => app.saveAnimation(_recipes,
                    frames: _frames, fps: _fps, prefix: '(b)'),
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save as (b) talk (WebP)'),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Save as (a) idle (WebP)',
          onPressed: _recipes.isEmpty
              ? null
              : () => app.saveAnimation(_recipes,
                  frames: _frames, fps: _fps, prefix: '(a)'),
          icon: const Icon(Icons.bedtime_outlined),
        ),
        IconButton(
          tooltip: 'Clear',
          onPressed: () {
            setState(() => _recipes.clear());
            _schedule();
          },
          icon: const Icon(Icons.clear_all_rounded),
        ),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: (_recipes.isEmpty || !app.hasProject)
              ? null
              : () => _animateAll(app),
          icon: const Icon(Icons.auto_awesome_motion),
          label: const Text('Animate ALL sprites (WebP)'),
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Text(
          'Renders this effect stack onto every sprite at once and saves each as '
          'an animated WebP talk (b) sprite.',
          style: TextStyle(fontSize: 11, color: Colors.white60),
        ),
      ),
      if (_recipes.isNotEmpty) ...<Widget>[
        const Divider(height: 24),
        Text('Effect strength', style: Theme.of(context).textTheme.titleMedium),
        for (int i = 0; i < _recipes.length; i++) _recipeTuner(i),
      ],
      const Divider(height: 24),
      Text('Presets', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      _presetChips ?? const SizedBox.shrink(),
      const Divider(height: 24),
      Text('Add an effect', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      _effectChips ?? const SizedBox.shrink(),
    ];
  }

  Widget _fpsSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Speed: $_fps fps'),
        Slider(
          value: _fps.toDouble(),
          min: 2,
          max: 30,
          divisions: 28,
          onChanged: (double v) {
            setState(() => _fps = v.round());
            _schedule();
          },
        ),
      ],
    );
  }

  Widget _recipeTuner(int i) {
    final AnimRecipe r = _recipes[i];
    final double intensity = r.n('intensity', 6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text('${r.type}  (${intensity.toStringAsFixed(1)})')),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () {
              setState(() => _recipes.removeAt(i));
              _schedule();
            },
          ),
        ]),
        Slider(
          value: intensity.clamp(0, 40),
          max: 40,
          onChanged: (double v) {
            setState(() => r.p['intensity'] = v);
            _schedule();
          },
        ),
      ],
    );
  }

  Widget _buildPresetChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final AnimPreset preset in ExtensionRegistry.instance.animPresets)
          ActionChip(label: Text(preset.name), onPressed: () => _applyPreset(preset)),
      ],
    );
  }

  Widget _buildEffectChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final String type in AnimEngine.recipeTypes)
          if (type != 'none')
            InputChip(label: Text(type), onPressed: () => _addRecipe(type)),
      ],
    );
  }
}
