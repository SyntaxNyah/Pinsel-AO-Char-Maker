import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../animation/anim_engine.dart';
import '../../core/ao_constants.dart';
import '../../imaging/codecs.dart';
import '../../imaging/sprite_sheet.dart';
import '../../puppet/puppet.dart';
import '../app_state.dart';

/// **Puppet Studio** — assemble a character out of part layers (sliced from a
/// sprite-sheet/atlas, or dropped in as separate PNGs) and bake a gently
/// *animated* AO sprite from it: an idle `(a)` (breathe / sway / blink) and a
/// talking `(b)`. The "Live2D for AO" path — see docs/PUPPET.md.
class PuppetStudioScreen extends StatefulWidget {
  const PuppetStudioScreen({super.key});

  @override
  State<PuppetStudioScreen> createState() => _PuppetStudioScreenState();
}

/// A curated set of idle motions exposed in the layer controls (type + label).
const List<({String type, String label})> _motions = <({String type, String label})>[
  (type: 'none', label: 'Still'),
  (type: 'breathe', label: 'Breathe'),
  (type: 'sway', label: 'Sway'),
  (type: 'bob', label: 'Bob'),
  (type: 'float', label: 'Float'),
  (type: 'nod', label: 'Nod'),
  (type: 'swing', label: 'Swing'),
  (type: 'pendulum', label: 'Pendulum'),
  (type: 'wiggle', label: 'Wiggle'),
  (type: 'blink', label: 'Blink'),
];

class _PuppetStudioScreenState extends State<PuppetStudioScreen> {
  List<Uint8List> _frames = <Uint8List>[];
  final ValueNotifier<int> _frameVN = ValueNotifier<int>(0);
  bool _talk = false;
  bool _rendering = false;
  Timer? _ticker;
  Timer? _debounce;
  final TextEditingController _name = TextEditingController(text: 'puppet');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleRender());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _debounce?.cancel();
    _frameVN.dispose();
    _name.dispose();
    super.dispose();
  }

  /// Debounced: re-render the animated preview a beat after the last change.
  void _scheduleRender() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _render);
  }

  Future<void> _render() async {
    if (!mounted) return;
    final AppState app = context.read<AppState>();
    if (!app.hasPuppet) {
      _ticker?.cancel();
      if (mounted) setState(() => _frames = <Uint8List>[]);
      return;
    }
    _rendering = true;
    final List<Uint8List> frames = await app.previewPuppet(talk: _talk);
    _rendering = false;
    if (!mounted) return;
    setState(() => _frames = frames);
    if (_frameVN.value >= frames.length) _frameVN.value = 0;
    _startTicker(app.puppetFps);
  }

  void _startTicker(int fps) {
    _ticker?.cancel();
    if (_frames.length < 2) return;
    // Drives only the preview Image (via _frameVN), not a whole-screen setState.
    _ticker = Timer.periodic(
        Duration(milliseconds: (1000 / fps).clamp(40, 400).round()), (_) {
      if (!mounted || _frames.isEmpty) return;
      _frameVN.value = (_frameVN.value + 1) % _frames.length;
    });
  }

  /// Called by the controls after they mutate the rig.
  void _changed() {
    context.read<AppState>().notifyPuppet();
    _scheduleRender();
  }

  Future<void> _addParts() async {
    final AppState app = context.read<AppState>();
    final FilePickerResult? res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: kImportableImageExtensions,
    );
    if (res == null) return;
    app.addPuppetParts(<PickedFile>[
      for (final PlatformFile f in res.files)
        if (f.bytes != null) PickedFile(f.name, f.bytes!),
    ]);
    _scheduleRender();
  }

  Future<void> _sliceSheet() async {
    final AppState app = context.read<AppState>();
    final FilePickerResult? res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: kImportableImageExtensions,
    );
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;
    final sheet = Codecs.decode(res.files.first.bytes!,
        ext: res.files.first.extension);
    if (sheet == null) return;
    final rects = SpriteSheet.autoDetect(sheet, const AutoSpec());
    final List<SheetCell> cells = <SheetCell>[
      for (int i = 0; i < rects.length; i++)
        SheetCell(rects[i], enabled: true, name: 'part${i + 1}'),
    ];
    if (cells.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Couldn\'t auto-detect parts — try the Ripper for '
                'manual control, then "Send to Puppet".')));
      }
      return;
    }
    app.puppetFromSheetCells(sheet, cells);
    _scheduleRender();
  }

  Future<void> _bake() async {
    final AppState app = context.read<AppState>();
    final String? base = await app.bakePuppet(name: _name.text);
    if (mounted && base != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Baked "$base" — an animated emote was added. '
              'Tweak it in Emotes, or export from Home.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.read<AppState>();
    return ListenableBuilder(
      listenable: app,
      builder: (BuildContext context, _) {
        if (!app.hasPuppet) return _empty(context);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(width: 250, child: _layersPanel(app)),
            const VerticalDivider(width: 1),
            Expanded(child: _previewPane(app)),
            const VerticalDivider(width: 1),
            SizedBox(width: 312, child: _controlsPanel(app)),
          ],
        );
      },
    );
  }

  // ---- Empty state ----
  Widget _empty(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.accessibility_new_rounded, size: 64),
            const SizedBox(height: 12),
            Text('Puppet Studio',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Assemble a character from separate parts and bake a gently '
              'animated AO sprite (idle + talking) — the "Live2D for AO" path. '
              'Start from a sheet of parts, or drop in layer PNGs.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _sliceSheet,
                  icon: const Icon(Icons.grid_on_rounded),
                  label: const Text('Slice a sheet of parts'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _addParts,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add part files'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Tip: for a tightly-packed atlas, use the Ripper to box each part, '
              'then "Send to Puppet".',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  // ---- Layers panel ----
  Widget _layersPanel(AppState app) {
    final PuppetRig rig = app.puppetRig!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: <Widget>[
              const Expanded(
                  child: Text('Layers', style: TextStyle(fontWeight: FontWeight.bold))),
              IconButton(
                tooltip: 'Add part files',
                icon: const Icon(Icons.add_photo_alternate_outlined),
                onPressed: _addParts,
              ),
              IconButton(
                tooltip: 'Slice a sheet of parts',
                icon: const Icon(Icons.grid_on_rounded),
                onPressed: _sliceSheet,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: true,
            itemCount: rig.layers.length,
            // Top of the list = drawn on top, so show back-to-front reversed.
            onReorder: (int oldI, int newI) {
              // ReorderableListView indices → list indices (top = last drawn).
              final int n = rig.layers.length;
              final int from = n - 1 - oldI;
              int to = n - 1 - (newI > oldI ? newI - 1 : newI);
              app.movePuppetLayer(from, to);
              _scheduleRender();
            },
            itemBuilder: (BuildContext context, int i) {
              final int li = rig.layers.length - 1 - i; // display top→bottom
              final PuppetLayer l = rig.layers[li];
              final bool sel = app.selectedPuppetLayer == li;
              return ListTile(
                key: ValueKey<int>(identityHashCode(l)),
                dense: true,
                selected: sel,
                onTap: () => app.selectPuppetLayer(li),
                leading: IconButton(
                  tooltip: l.visible ? 'Hide' : 'Show',
                  icon: Icon(l.visible
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_outlined),
                  onPressed: () {
                    l.visible = !l.visible;
                    _changed();
                  },
                ),
                title: Text(l.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(l.role.label),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    app.removePuppetLayer(li);
                    _scheduleRender();
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---- Preview ----
  Widget _previewPane(AppState app) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: <Widget>[
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: false, label: Text('Idle (a)')),
                  ButtonSegment<bool>(value: true, label: Text('Talk (b)')),
                ],
                selected: <bool>{_talk},
                onSelectionChanged: (Set<bool> s) {
                  setState(() => _talk = s.first);
                  _scheduleRender();
                },
              ),
              const Spacer(),
              if (_rendering)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              Text('${_frames.length} frames',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Container(
            color: Colors.black12,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            child: _frames.isEmpty
                ? const Text('No preview yet')
                : ValueListenableBuilder<int>(
                    valueListenable: _frameVN,
                    builder: (BuildContext context, int i, _) => Image.memory(
                      _frames[i.clamp(0, _frames.length - 1)],
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      fit: BoxFit.contain,
                    ),
                  ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Emote / sprite name',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _bake,
                icon: const Icon(Icons.movie_creation_rounded),
                label: const Text('Bake → animated emote'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- Controls ----
  Widget _controlsPanel(AppState app) {
    final PuppetRig rig = app.puppetRig!;
    final int? si = app.selectedPuppetLayer;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Text('Animation', style: Theme.of(context).textTheme.titleSmall),
        _slider('Frames', app.puppetFrames.toDouble(), 2, 32,
            (double v) => app.puppetFrames = v.round(),
            divisions: 30, valueLabel: '${app.puppetFrames}'),
        _slider('Speed (fps)', app.puppetFps.toDouble(), 4, 24,
            (double v) => app.puppetFps = v.round(),
            divisions: 20, valueLabel: '${app.puppetFps}'),
        _slider('Mouth open', app.puppetTalkOpen, 0.1, 1.2,
            (double v) => app.puppetTalkOpen = v),
        _sizeRow(app, rig),
        const Divider(height: 24),
        if (si == null || si >= rig.layers.length)
          const Text('Select a layer to edit it.')
        else
          ..._layerControls(app, rig.layers[si]),
      ],
    );
  }

  Widget _sizeRow(AppState app, PuppetRig rig) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _miniField('Canvas W', rig.width, (int v) {
            rig.width = v.clamp(16, 2048);
            _changed();
          }),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniField('Canvas H', rig.height, (int v) {
            rig.height = v.clamp(16, 2048);
            _changed();
          }),
        ),
      ],
    );
  }

  List<Widget> _layerControls(AppState app, PuppetLayer l) {
    final String motionType = l.motion.isEmpty ? 'none' : l.motion.first.type;
    return <Widget>[
      Row(
        children: <Widget>[
          Text(l.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
        ],
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<PuppetRole>(
        value: l.role,
        decoration: const InputDecoration(
            labelText: 'Role', isDense: true, border: OutlineInputBorder()),
        items: <DropdownMenuItem<PuppetRole>>[
          for (final PuppetRole r in PuppetRole.values)
            DropdownMenuItem<PuppetRole>(value: r, child: Text(r.label)),
        ],
        onChanged: (PuppetRole? r) {
          if (r == null) return;
          // Role drives the auto-animation, so re-seed motion/pivot/phase to its
          // defaults (then the user can tweak).
          l.role = r;
          l.motion = PuppetLayer.defaultMotion(r);
          final (double px, double py) = PuppetLayer.defaultPivot(r);
          l.pivotX = px;
          l.pivotY = py;
          l.phase = PuppetLayer.defaultPhase(r);
          _changed();
        },
      ),
      _slider('Position X', l.x, 0, 1, (double v) => l.x = v),
      _slider('Position Y', l.y, 0, 1, (double v) => l.y = v),
      _slider('Scale', l.scale, 0.2, 3, (double v) => l.scale = v),
      _slider('Rotate', l.angle, -45, 45, (double v) => l.angle = v),
      _slider('Pivot X', l.pivotX, 0, 1, (double v) => l.pivotX = v),
      _slider('Pivot Y', l.pivotY, 0, 1, (double v) => l.pivotY = v),
      _slider('Opacity', l.opacity, 0, 1, (double v) => l.opacity = v),
      _slider('Phase', l.phase, 0, 1, (double v) => l.phase = v),
      const Divider(height: 24),
      Text('Motion', style: Theme.of(context).textTheme.titleSmall),
      DropdownButtonFormField<String>(
        value: motionType,
        decoration: const InputDecoration(
            labelText: 'Idle motion', isDense: true, border: OutlineInputBorder()),
        items: <DropdownMenuItem<String>>[
          for (final ({String type, String label}) m in _motions)
            DropdownMenuItem<String>(value: m.type, child: Text(m.label)),
        ],
        onChanged: (String? t) {
          if (t == null) return;
          _setMotion(l, t);
          _changed();
        },
      ),
      if (motionType == 'blink')
        _slider(
            'Blinks / loop',
            (l.motion.first.p['count'] ?? 1).toDouble(),
            1,
            5,
            (double v) => l.motion.first.p['count'] = v.roundToDouble(),
            divisions: 4)
      else if (motionType != 'none') ...<Widget>[
        _slider(
            'Amount',
            (l.motion.first.p['intensity'] ?? 5).toDouble(),
            0,
            20,
            (double v) => l.motion.first.p['intensity'] = v),
        _slider(
            'Cycles',
            (l.motion.first.p['cycles'] ?? 1).toDouble(),
            1,
            4,
            (double v) => l.motion.first.p['cycles'] = v.roundToDouble(),
            divisions: 3),
      ],
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Text('Tip: the Talk (b) clip opens any layer tagged "Mouth".',
            style: Theme.of(context).textTheme.bodySmall),
      ),
    ];
  }

  void _setMotion(PuppetLayer l, String type) {
    if (type == 'none') {
      l.motion = <AnimRecipe>[];
    } else if (type == 'blink') {
      l.motion = <AnimRecipe>[
        AnimRecipe('blink', p: <String, double>{'count': 1})
      ];
    } else {
      l.motion = <AnimRecipe>[
        AnimRecipe(type, p: <String, double>{'intensity': 5, 'cycles': 1})
      ];
    }
  }

  // ---- Small reusable controls ----
  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    void Function(double) onChanged, {
    int? divisions,
    String? valueLabel,
  }) {
    final double v = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                  child: Text(label,
                      style: Theme.of(context).textTheme.bodySmall)),
              Text(
                  valueLabel ??
                      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          Slider(
            value: v,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (double nv) {
              onChanged(nv);
              _changed();
            },
          ),
        ],
      ),
    );
  }

  Widget _miniField(String label, int value, void Function(int) onChanged) {
    return TextFormField(
      initialValue: '$value',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
          labelText: label, isDense: true, border: const OutlineInputBorder()),
      onFieldSubmitted: (String s) {
        final int? v = int.tryParse(s.trim());
        if (v != null) onChanged(v);
      },
    );
  }
}
