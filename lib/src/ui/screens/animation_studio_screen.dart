import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Easing; // our Easing (Flutter 3.29+ also has one)
import 'package:provider/provider.dart';

import '../../animation/anim_engine.dart';
import '../../animation/easing.dart';
import '../../animation/jiggle.dart';
import '../../animation/lipsync.dart';
import '../../plugins/extension_registry.dart';
import '../../presets/presets.dart';
import '../app_state.dart';
import '../widgets/checker_image.dart';

/// The studio workflows.
enum _StudioMode { effects, mouth, jiggle, frames }

/// How the talking mouth is drawn: a procedural jaw-drop cavity, a drawn
/// "anime mouth" shape, or a real open mouth meshed from another sprite.
enum _MouthSource { cavity, shape, mesh }

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
  double _openAmount = LipSync.defaultStyle.openAmount;
  int _mouthFrames = 10;
  double? _mouthAspect; // selected sprite w/h, for the region overlay box
  String? _mouthSeededRel; // sprite the auto mouth box was last seeded for
  TalkStyle _talkStyle = LipSync.defaultStyle; // the chosen "way of talking"
  _MouthSource _mouthSource = _MouthSource.cavity;
  MouthShape _mouthShape = LipSync.mouthShapes.first; // chosen anime mouth

  // jiggle mode — default to the twin-lobe "Bust" preset (the headline use).
  JiggleSpec _jiggle = jiggleByName('Bust');
  int _jiggleFrames = 18;

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
          frames: _mouthFrames,
          fps: _fps,
          openAmount: _openAmount,
          style: _talkStyle,
          shape: _mouthSource == _MouthSource.shape ? _mouthShape : null,
          mesh: _mouthSource == _MouthSource.mesh);
    } else if (_mode == _StudioMode.jiggle) {
      await _ensureMouthSeed(app); // also seeds the sprite aspect for the box
      imgs = await app.previewJiggle(<JiggleSpec>[_jiggle],
          frames: _jiggleFrames, fps: _fps);
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
        return 'Drag the pink box onto the lips — corner/edge handles resize it';
      case _StudioMode.jiggle:
        return 'Drag the box over what should jiggle (chest/body) — resize to fit';
      case _StudioMode.effects:
        return _recipes.isEmpty
            ? 'No effects yet — pick a preset or add effects →'
            : 'Stack: ${_recipes.map((AnimRecipe r) => r.type).join(" + ")}';
    }
  }

  /// The looping preview. In Mouth/Jiggle mode it overlays a **draggable,
  /// resizable** box (aligned to the sprite via [_mouthAspect]) so you place the
  /// mouth / jiggle region with the mouse instead of fiddling with sliders.
  Widget _previewContent() {
    final bool boxMode =
        _mode == _StudioMode.mouth || _mode == _StudioMode.jiggle;
    // Effects / Frames mode (or no sprite yet): just the looping image.
    if (!boxMode || _mouthAspect == null) {
      return ValueListenableBuilder<int>(
        valueListenable: _frameIdx,
        builder: (_, int idx, __) {
          final Uint8List? b =
              _frameImgs.isEmpty ? null : _frameImgs[idx % _frameImgs.length];
          return CheckerImage(bytes: b);
        },
      );
    }
    final MouthRegion box = _mode == _StudioMode.mouth
        ? _mouth
        : MouthRegion(_jiggle.x, _jiggle.y, _jiggle.w, _jiggle.h);
    // Box mode: looping preview + an interactive box on top. The image animates
    // (its own ValueListenableBuilder) while the box overlay only rebuilds when
    // you drag it or it's re-seeded — so dragging stays smooth.
    return Center(
      child: AspectRatio(
        aspectRatio: _mouthAspect!,
        child: LayoutBuilder(
          builder: (_, BoxConstraints c) {
            final double w = c.maxWidth, h = c.maxHeight;
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _frameIdx,
                    builder: (_, int idx, __) {
                      final Uint8List? b = _frameImgs.isEmpty
                          ? null
                          : _frameImgs[idx % _frameImgs.length];
                      return CheckerImage(bytes: b, fit: BoxFit.fill);
                    },
                  ),
                ),
                Positioned.fill(
                  child: _MouthBoxOverlay(
                    width: w,
                    height: h,
                    mouth: box,
                    // Live drag: write the value but don't rebuild the controls
                    // (the overlay redraws itself).
                    onChanged: (MouthRegion m) {
                      if (_mode == _StudioMode.mouth) {
                        _mouth = m;
                      } else {
                        _jiggle = _jiggle
                            .copyWith(x: m.x, y: m.y, w: m.w, h: m.h);
                      }
                    },
                    // One rebuild (sync sliders) + re-render the loop on release.
                    onCommit: () {
                      setState(() {});
                      _schedule();
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
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
                value: _StudioMode.jiggle,
                label: Text('Jiggle'),
                icon: Icon(Icons.vibration)),
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
          _StudioMode.jiggle => _jiggleControls(app),
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
      Text('Talking mouth (VN style)',
          style: Theme.of(context).textTheme.titleMedium),
      const Text(
        'Make this one static drawing talk like a visual-novel character — no '
        'extra art needed. Pick a "way of talking", then drag the pink box in '
        'the preview onto the lips — grab its corner to resize, or the right/'
        'bottom edge to stretch width/height. The jaw drops inside the box with '
        'that cadence in a seamless loop.',
        style: TextStyle(fontSize: 12, color: Colors.white60),
      ),
      const SizedBox(height: 10),
      // The headline feature: hundreds of named talking cadences.
      Text('Way of talking', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      OutlinedButton.icon(
        onPressed: _pickTalkStyle,
        icon: const Icon(Icons.record_voice_over_outlined),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text('${_talkStyle.name}  ·  ${_talkStyle.category}',
              overflow: TextOverflow.ellipsis),
        ),
        style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
            alignment: Alignment.centerLeft),
      ),
      Text(
        '${LipSync.styleCatalogue.length} styles — calm, excited, whisper, '
        'angry, sobbing, robotic, singing…',
        style: const TextStyle(fontSize: 11, color: Colors.white38),
      ),
      const Divider(height: 18),
      // How the open mouth looks: procedural cavity, a drawn anime mouth, or a
      // real open mouth meshed from another sprite.
      Text('Mouth opening', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      SegmentedButton<_MouthSource>(
        showSelectedIcon: false,
        segments: const <ButtonSegment<_MouthSource>>[
          ButtonSegment<_MouthSource>(
              value: _MouthSource.cavity, label: Text('Auto')),
          ButtonSegment<_MouthSource>(
              value: _MouthSource.shape, label: Text('Anime')),
          ButtonSegment<_MouthSource>(
              value: _MouthSource.mesh, label: Text('Mesh')),
        ],
        selected: <_MouthSource>{_mouthSource},
        onSelectionChanged: (Set<_MouthSource> s) {
          setState(() => _mouthSource = s.first);
          _schedule();
        },
      ),
      if (_mouthSource == _MouthSource.cavity)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Auto: the jaw drops and a soft dark mouth opens — works on any '
            'sprite, no art needed.',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ),
      if (_mouthSource == _MouthSource.shape) ...<Widget>[
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _pickMouthShape,
          icon: const Icon(Icons.emoji_emotions_outlined),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text('${_mouthShape.name}  ·  ${_mouthShape.category}',
                overflow: TextOverflow.ellipsis),
          ),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
              alignment: Alignment.centerLeft),
        ),
        Text(
          '${LipSync.mouthShapes.length} drawn anime mouths — o, gasp, grin, '
          'tongue, smile…',
          style: const TextStyle(fontSize: 11, color: Colors.white38),
        ),
      ],
      if (_mouthSource == _MouthSource.mesh) ...<Widget>[
        const SizedBox(height: 6),
        const Text(
          'Mesh a REAL open mouth cut from another sprite (the same character '
          'with their mouth open). It is feathered onto this sprite and '
          'cross-fades in as the mouth "opens". Position the box on the mouth '
          'first — the same box is cut from the open-mouth sprite.',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(height: 4),
        Row(children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickMeshSprite,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                app.hasMeshSprite
                    ? 'Open-mouth sprite loaded ✓'
                    : 'Pick open-mouth sprite…',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (app.hasMeshSprite)
            IconButton(
              tooltip: 'Clear',
              onPressed: () {
                app.setMeshSprite(null);
                _schedule();
              },
              icon: const Icon(Icons.close),
            ),
        ]),
      ],
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => _autoPlaceMouth(app),
        icon: const Icon(Icons.center_focus_strong_outlined),
        label: const Text('Auto-place on face'),
      ),
      const SizedBox(height: 8),
      const Text('Or fine-tune with sliders',
          style: TextStyle(fontSize: 11, color: Colors.white38)),
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
      Text('Openness / jaw drop: ${_openAmount.toStringAsFixed(2)}'),
      Slider(
        value: _openAmount.clamp(0.05, 0.8),
        min: 0.05,
        max: 0.8,
        onChanged: (double v) {
          setState(() => _openAmount = v);
          _schedule();
        },
      ),
      Text('Frames: $_mouthFrames  (more = smoother fast styles)'),
      Slider(
        value: _mouthFrames.toDouble().clamp(2, 24),
        min: 2,
        max: 24,
        divisions: 22,
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
                    style: _talkStyle,
                    shape: _mouthSource == _MouthSource.shape ? _mouthShape : null,
                    mesh: _mouthSource == _MouthSource.mesh,
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
                  style: _talkStyle,
                  shape: _mouthSource == _MouthSource.shape ? _mouthShape : null,
                  mesh: _mouthSource == _MouthSource.mesh,
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
        frames: _mouthFrames,
        fps: _fps,
        openAmount: _openAmount,
        style: _talkStyle,
        // Mesh is per-sprite (one specific open mouth), so bulk uses the drawn
        // shape (if chosen) or the procedural cavity.
        shape: _mouthSource == _MouthSource.shape ? _mouthShape : null,
        prefix: '(b)');
  }

  /// Open the searchable, category-grouped talk-style picker. Choosing a style
  /// also resets the openness slider to that style's natural jaw drop (you can
  /// still tweak it afterwards) and refreshes the live preview.
  Future<void> _pickTalkStyle() async {
    final TalkStyle? picked = await showTalkStylePicker(context, _talkStyle);
    if (picked == null || !mounted) return;
    setState(() {
      _talkStyle = picked;
      _openAmount = picked.openAmount;
    });
    _schedule();
  }

  Future<void> _pickMouthShape() async {
    final MouthShape? picked = await showCataloguePicker<MouthShape>(
      context,
      title: 'Pick an anime mouth',
      hint: 'Search mouths (o, gasp, grin, tongue, smile)…',
      items: LipSync.mouthShapes,
      categories: LipSync.mouthShapeCategories,
      nameOf: (MouthShape m) => m.name,
      categoryOf: (MouthShape m) => m.category,
      subtitleOf: (MouthShape m) =>
          'w ${(m.widthFrac * 100).round()}% · h ${(m.heightFrac * 100).round()}%'
          '${m.teeth ? ' · teeth' : ''}${m.tongue ? ' · tongue' : ''}',
      selectedName: _mouthShape.name,
    );
    if (picked == null || !mounted) return;
    setState(() => _mouthShape = picked);
    _schedule();
  }

  Future<void> _pickMeshSprite() async {
    final FilePickerResult? res = await FilePicker.platform
        .pickFiles(withData: true, type: FileType.image);
    if (res == null || res.files.isEmpty) return;
    final PlatformFile f = res.files.first;
    if (f.bytes == null || !mounted) return;
    context
        .read<AppState>()
        .setMeshSprite(f.bytes!, ext: (f.extension ?? 'png').toLowerCase());
    setState(() {});
    _schedule();
  }

  // ===========================================================================
  // Jiggle mode — bounce a region (chest / body / hair / anything)
  // ===========================================================================
  List<Widget> _jiggleControls(AppState app) {
    return <Widget>[
      Text('Jiggle physics', style: Theme.of(context).textTheme.titleMedium),
      const Text(
        'Bounce a part of the sprite — boobs, hair, belly, anything. Drag the '
        'box over it, then dial in the direction, how much it bounces and how '
        'fast. Saved as an animated (a) idle so it plays while the character is '
        'just standing there. (A looping motion tuned to feel springy, not a '
        'true physics sim.)',
        style: TextStyle(fontSize: 12, color: Colors.white60),
      ),
      const SizedBox(height: 10),
      Text('Preset', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      OutlinedButton.icon(
        onPressed: _pickJiggle,
        icon: const Icon(Icons.tune),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text('${_jiggle.name}  ·  ${_jiggle.category}',
              overflow: TextOverflow.ellipsis),
        ),
        style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
            alignment: Alignment.centerLeft),
      ),
      Text(
        '${jigglePresets.length} presets — subtle, bouncy, jelly, sway, wild…',
        style: const TextStyle(fontSize: 11, color: Colors.white38),
      ),
      const SizedBox(height: 8),
      const Text('Drag the box in the preview over what should jiggle.',
          style: TextStyle(fontSize: 11, color: Colors.white54)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _jiggle.twin,
        onChanged: (bool v) {
          setState(() => _jiggle = _jiggle.copyWith(twin: v));
          _schedule();
        },
        title: const Text('Twin lobes (boobs)'),
        subtitle: const Text(
          'Split the box into a left + right lobe that bounce out of phase — '
          'the two-breast look. Off = one region.',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ),
      const SizedBox(height: 6),
      _jiggleSlider('Direction', _jiggle.direction, 0, 180,
          (double v) => _jiggle = _jiggle.copyWith(direction: v),
          suffix: '°', divisions: 36, hint: '0° = up/down · 90° = left/right'),
      _jiggleSlider('Bounce amount', _jiggle.amplitude * 100, 2, 60,
          (double v) => _jiggle = _jiggle.copyWith(amplitude: v / 100),
          suffix: '%', divisions: 58),
      _jiggleSliderInt('Speed (bounces per loop)', _jiggle.frequency, 1, 8,
          (int v) => _jiggle = _jiggle.copyWith(frequency: v)),
      _jiggleSlider('Bounciness', _jiggle.bounciness, 0, 1,
          (double v) => _jiggle = _jiggle.copyWith(bounciness: v)),
      _jiggleSlider('Softness (squash & stretch)', _jiggle.squash, 0, 1,
          (double v) => _jiggle = _jiggle.copyWith(squash: v)),
      _jiggleSlider('Sway (rotation)', _jiggle.sway, 0, 20,
          (double v) => _jiggle = _jiggle.copyWith(sway: v),
          suffix: '°', divisions: 40),
      Text('Frames: $_jiggleFrames'),
      Slider(
        value: _jiggleFrames.toDouble().clamp(4, 32),
        min: 4,
        max: 32,
        divisions: 28,
        onChanged: (double v) {
          setState(() => _jiggleFrames = v.round());
          _schedule();
        },
      ),
      _fpsSlider(),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: app.current == null
              ? null
              : () => app.saveJiggle(<JiggleSpec>[_jiggle],
                  frames: _jiggleFrames, fps: _fps),
          icon: const Icon(Icons.save_rounded),
          label: const Text('Save as (a) idle'),
        ),
      ),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: !app.hasProject ? null : () => _jiggleAll(app),
          icon: const Icon(Icons.auto_awesome_motion),
          label: const Text('Jiggle ALL sprites'),
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Text(
          'Applies this box + settings to every sprite, baked across all CPU '
          'cores.',
          style: TextStyle(fontSize: 11, color: Colors.white60),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  Widget _jiggleSlider(String label, double value, double min, double max,
      void Function(double) assign,
      {String suffix = '', int? divisions, String? hint}) {
    final bool whole = suffix == '%' || suffix == '°';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$label: ${whole ? value.round() : value.toStringAsFixed(2)}$suffix'),
        if (hint != null)
          Text(hint, style: const TextStyle(fontSize: 10, color: Colors.white38)),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: (double v) {
            setState(() => assign(v));
            _schedule();
          },
        ),
      ],
    );
  }

  Widget _jiggleSliderInt(
      String label, int value, int min, int max, void Function(int) assign) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$label: $value'),
        Slider(
          value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: (double v) {
            setState(() => assign(v.round()));
            _schedule();
          },
        ),
      ],
    );
  }

  Future<void> _pickJiggle() async {
    final JiggleSpec? picked = await showCataloguePicker<JiggleSpec>(
      context,
      title: 'Pick a jiggle preset',
      hint: 'Search (bouncy, jelly, sway, heavy, wild)…',
      items: jigglePresets,
      categories: jiggleCategories,
      nameOf: (JiggleSpec j) => j.name,
      categoryOf: (JiggleSpec j) => j.category,
      subtitleOf: (JiggleSpec j) =>
          'amount ${(j.amplitude * 100).round()}% · speed ${j.frequency} · '
          'bounce ${(j.bounciness * 100).round()}%',
      selectedName: _jiggle.name,
    );
    if (picked == null || !mounted) return;
    // Keep the box the user placed; adopt the preset's physics.
    setState(() => _jiggle = picked.copyWith(
        x: _jiggle.x, y: _jiggle.y, w: _jiggle.w, h: _jiggle.h));
    _schedule();
  }

  Future<void> _jiggleAll(AppState app) async {
    final int count = app.spriteBases().length;
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Jiggle all sprites?'),
        content: Text(
          'Apply this jiggle box + settings to all $count sprite(s) and save '
          'each as an animated (a) idle, replacing existing idles. Baked across '
          'all CPU cores.',
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
    await app.bulkJiggleAll(<JiggleSpec>[_jiggle],
        frames: _jiggleFrames, fps: _fps);
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

/// Which part of the mouth box a drag is manipulating.
enum _MouthHandle { move, sizeBoth, sizeW, sizeH }

/// A **draggable + resizable** mouth box drawn over the talk preview, so the box
/// can be placed with the mouse instead of sliders:
///  * drag **inside / anywhere** → move it,
///  * drag the **bottom-right corner** handle → resize (width + height),
///  * drag the **right-edge** handle → width only,
///  * drag the **bottom-edge** handle → height only.
///
/// All geometry is in **fractions** ([MouthRegion]) so it survives the
/// downscaled preview and maps onto the full-res sprite on save. During a drag
/// it keeps a local `_live` box and calls [onChanged] without forcing the
/// parent to rebuild; [onCommit] (on release) triggers the one heavy refresh.
class _MouthBoxOverlay extends StatefulWidget {
  const _MouthBoxOverlay({
    required this.width,
    required this.height,
    required this.mouth,
    required this.onChanged,
    required this.onCommit,
  });

  final double width;
  final double height;
  final MouthRegion mouth;
  final ValueChanged<MouthRegion> onChanged;
  final VoidCallback onCommit;

  @override
  State<_MouthBoxOverlay> createState() => _MouthBoxOverlayState();
}

class _MouthBoxOverlayState extends State<_MouthBoxOverlay> {
  static const double _hit = 22; // px touch radius for the resize handles
  static const Color _pink = Color(0xFFFF4081);

  late MouthRegion _live = widget.mouth;
  _MouthHandle? _drag;

  double get _w => widget.width;
  double get _h => widget.height;

  @override
  void didUpdateWidget(covariant _MouthBoxOverlay old) {
    super.didUpdateWidget(old);
    // Adopt external changes (auto-place, sliders, new sprite) only when idle —
    // never stomp a box the user is actively dragging.
    if (_drag == null) _live = widget.mouth;
  }

  _MouthHandle _hitTest(Offset p) {
    final double bx = _live.x * _w, by = _live.y * _h;
    final double bw = _live.w * _w, bh = _live.h * _h;
    bool nearX(double x) => (p.dx - x).abs() <= _hit;
    bool nearY(double y) => (p.dy - y).abs() <= _hit;
    final bool inRowY = p.dy >= by - _hit && p.dy <= by + bh + _hit;
    final bool inColX = p.dx >= bx - _hit && p.dx <= bx + bw + _hit;
    if (nearX(bx + bw) && nearY(by + bh)) return _MouthHandle.sizeBoth; // corner
    if (nearX(bx + bw) && inRowY) return _MouthHandle.sizeW; // right edge
    if (nearY(by + bh) && inColX) return _MouthHandle.sizeH; // bottom edge
    return _MouthHandle.move; // grab anywhere else to move
  }

  MouthRegion _clamp(MouthRegion m) {
    final double w = m.w.clamp(0.02, 1.0);
    final double h = m.h.clamp(0.01, 1.0);
    final double x = m.x.clamp(0.0, 1.0 - w);
    final double y = m.y.clamp(0.0, 1.0 - h);
    return MouthRegion(x, y, w, h);
  }

  void _onStart(DragStartDetails d) => _drag = _hitTest(d.localPosition);

  void _onUpdate(DragUpdateDetails d) {
    final _MouthHandle? k = _drag;
    if (k == null) return;
    final double dx = d.delta.dx / _w; // fractional move
    final double dy = d.delta.dy / _h;
    final MouthRegion m = _clamp(switch (k) {
      _MouthHandle.move => _live.copyWith(x: _live.x + dx, y: _live.y + dy),
      _MouthHandle.sizeBoth =>
        _live.copyWith(w: _live.w + dx, h: _live.h + dy),
      _MouthHandle.sizeW => _live.copyWith(w: _live.w + dx),
      _MouthHandle.sizeH => _live.copyWith(h: _live.h + dy),
    });
    setState(() => _live = m);
    widget.onChanged(m);
  }

  void _onEnd(DragEndDetails d) {
    _drag = null;
    widget.onCommit();
  }

  Widget _handle() => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _pink, width: 2),
          borderRadius: BorderRadius.circular(3),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final double bx = _live.x * _w, by = _live.y * _h;
    final double bw = (_live.w * _w).clamp(1.0, _w);
    final double bh = (_live.h * _h).clamp(1.0, _h);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onStart,
      onPanUpdate: _onUpdate,
      onPanEnd: _onEnd,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: bx,
            top: by,
            width: bw,
            height: bh,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x22FF4081),
                border: Border.fromBorderSide(
                    BorderSide(color: Color(0xFFFF4081), width: 2)),
              ),
            ),
          ),
          // Visual handles (hit-testing is coordinate-based, so one
          // GestureDetector handles all of them — no gesture-arena conflicts).
          Positioned(left: bx + bw - 7, top: by + bh - 7, child: _handle()),
          Positioned(left: bx + bw - 7, top: by + bh / 2 - 7, child: _handle()),
          Positioned(left: bx + bw / 2 - 7, top: by + bh - 7, child: _handle()),
        ],
      ),
    );
  }
}

/// Show the searchable, category-grouped **talk style** picker over
/// [LipSync.styleCatalogue]. Returns the chosen style, or null if cancelled.
Future<TalkStyle?> showTalkStylePicker(
        BuildContext context, TalkStyle current) =>
    showDialog<TalkStyle>(
      context: context,
      builder: (BuildContext ctx) => _TalkStylePicker(current: current),
    );

/// A dialog listing every [TalkStyle] grouped by category, with a live text
/// filter and a per-category quick filter, so picking from hundreds of styles
/// stays fast.
class _TalkStylePicker extends StatefulWidget {
  const _TalkStylePicker({required this.current});
  final TalkStyle current;

  @override
  State<_TalkStylePicker> createState() => _TalkStylePickerState();
}

class _TalkStylePickerState extends State<_TalkStylePicker> {
  String _query = '';
  String? _category; // null = all categories

  @override
  Widget build(BuildContext context) {
    final String q = _query.trim().toLowerCase();
    final List<TalkStyle> matches = <TalkStyle>[
      for (final TalkStyle s in LipSync.styleCatalogue)
        if ((_category == null || s.category == _category) &&
            (q.isEmpty ||
                s.name.toLowerCase().contains(q) ||
                s.category.toLowerCase().contains(q)))
          s,
    ];

    // Group matches by category, preserving catalogue order.
    final Map<String, List<TalkStyle>> grouped = <String, List<TalkStyle>>{};
    for (final TalkStyle s in matches) {
      (grouped[s.category] ??= <TalkStyle>[]).add(s);
    }

    return AlertDialog(
      title: const Text('Pick a way of talking'),
      content: SizedBox(
        width: 460,
        height: 540,
        child: Column(
          children: <Widget>[
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Search styles (e.g. excited, whisper, robotic)…',
              ),
              onChanged: (String v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text('All'),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null),
                    ),
                  ),
                  for (final String c in LipSync.styleCategories)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('No styles match.'))
                  : ListView(
                      children: <Widget>[
                        for (final MapEntry<String, List<TalkStyle>> g
                            in grouped.entries) ...<Widget>[
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(4, 8, 4, 4),
                            child: Text(g.key.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 1,
                                    color: Colors.white54)),
                          ),
                          for (final TalkStyle s in g.value)
                            ListTile(
                              dense: true,
                              selected: s.name == widget.current.name,
                              leading: const Icon(
                                  Icons.record_voice_over_outlined,
                                  size: 18),
                              title: Text(s.name),
                              subtitle: Text(
                                'rate ${s.syllables} · open '
                                '${(s.openAmount * 100).round()}% · '
                                'jitter ${(s.jitter * 100).round()}%'
                                '${s.pause > 0.25 ? ' · pauses' : ''}'
                                '${s.bob > 0.3 ? ' · bob' : ''}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              onTap: () => Navigator.pop(context, s),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// A generic searchable, category-grouped catalogue picker (used by the mouth
/// shapes and the jiggle presets). Returns the chosen item, or null.
Future<T?> showCataloguePicker<T>(
  BuildContext context, {
  required String title,
  required String hint,
  required List<T> items,
  required List<String> categories,
  required String Function(T) nameOf,
  required String Function(T) categoryOf,
  required String Function(T) subtitleOf,
  String? selectedName,
}) =>
    showDialog<T>(
      context: context,
      builder: (BuildContext ctx) => _CataloguePicker<T>(
        title: title,
        hint: hint,
        items: items,
        categories: categories,
        nameOf: nameOf,
        categoryOf: categoryOf,
        subtitleOf: subtitleOf,
        selectedName: selectedName,
      ),
    );

class _CataloguePicker<T> extends StatefulWidget {
  const _CataloguePicker({
    required this.title,
    required this.hint,
    required this.items,
    required this.categories,
    required this.nameOf,
    required this.categoryOf,
    required this.subtitleOf,
    this.selectedName,
  });
  final String title;
  final String hint;
  final List<T> items;
  final List<String> categories;
  final String Function(T) nameOf;
  final String Function(T) categoryOf;
  final String Function(T) subtitleOf;
  final String? selectedName;

  @override
  State<_CataloguePicker<T>> createState() => _CataloguePickerState<T>();
}

class _CataloguePickerState<T> extends State<_CataloguePicker<T>> {
  String _query = '';
  String? _category;

  @override
  Widget build(BuildContext context) {
    final String q = _query.trim().toLowerCase();
    final List<T> matches = <T>[
      for (final T it in widget.items)
        if ((_category == null || widget.categoryOf(it) == _category) &&
            (q.isEmpty ||
                widget.nameOf(it).toLowerCase().contains(q) ||
                widget.categoryOf(it).toLowerCase().contains(q)))
          it,
    ];
    final Map<String, List<T>> grouped = <String, List<T>>{};
    for (final T it in matches) {
      (grouped[widget.categoryOf(it)] ??= <T>[]).add(it);
    }
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        height: 540,
        child: Column(
          children: <Widget>[
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: widget.hint,
              ),
              onChanged: (String v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text('All'),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null),
                    ),
                  ),
                  for (final String c in widget.categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('Nothing matches.'))
                  : ListView(
                      children: <Widget>[
                        for (final MapEntry<String, List<T>> g
                            in grouped.entries) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                            child: Text(g.key.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 1,
                                    color: Colors.white54)),
                          ),
                          for (final T it in g.value)
                            ListTile(
                              dense: true,
                              selected: widget.nameOf(it) == widget.selectedName,
                              title: Text(widget.nameOf(it)),
                              subtitle: Text(widget.subtitleOf(it),
                                  style: const TextStyle(fontSize: 11)),
                              onTap: () => Navigator.pop(context, it),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
