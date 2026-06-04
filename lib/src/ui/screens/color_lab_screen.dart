import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';

import '../../imaging/color_ops.dart';
import '../../plugins/extension_registry.dart';
import '../../presets/presets.dart';
import '../app_state.dart';
import '../widgets/zoom_canvas.dart';

/// Real-time recolour. Performance notes:
///  * sliders only do a local [setState] + a debounced preview compute — they
///    never trigger a global rebuild;
///  * the (large) preset/gradient chip lists are built once and reused, so a
///    slider drag doesn't rebuild ~100 chips;
///  * the preview image lives in a [ValueNotifier] driven off a debounce timer,
///    decoupled from widget rebuilds.
///
/// Presets and gradients **blend** (stack) on top of each other and the sliders.
class ColorLabScreen extends StatefulWidget {
  const ColorLabScreen({super.key});

  @override
  State<ColorLabScreen> createState() => _ColorLabScreenState();
}

class _ColorLabScreenState extends State<ColorLabScreen> {
  double hue = 0;
  double sat = 1;
  double bri = 1;
  double con = 1;

  /// Stacked presets/gradients (blended in order, after the sliders).
  final List<OpPipeline> _blend = <OpPipeline>[];

  final ValueNotifier<Uint8List?> _preview = ValueNotifier<Uint8List?>(null);
  Timer? _debounce;
  Widget? _chipsCache;

  /// Plain (no-pipeline) bytes of the current sprite, kept so the GPU preview
  /// path can filter them live on the compositor. [_baseRel] tracks which sprite
  /// they belong to so they reload when the sprite (or its pixels) change.
  Uint8List? _baseBytes;
  String? _baseRel;
  Color _picked = const Color(0xFFFF5577);
  late final TextEditingController _hexCtrl =
      TextEditingController(text: _hex6(_picked));

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
    _hexCtrl.dispose();
    super.dispose();
  }

  /// 6-digit `rrggbb` (no `#`, no alpha) for the inline hex field.
  String _hex6(Color c) =>
      (c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  void _setPicked(Color c, {bool syncHex = true}) {
    setState(() => _picked = c);
    if (syncHex) _hexCtrl.text = _hex6(c);
  }

  /// Parse the inline hex field (`#rgb`/`rrggbb`/`aarrggbb`) and apply it.
  void _applyHexField(String raw) {
    final int? argb = parseHexColor(raw.trim());
    if (argb != null) _setPicked(Color(argb), syncHex: false);
  }

  List<ColorOp> get _pipeline => <ColorOp>[
        if (hue.abs() > 0.5) ColorOp('hueShift', nums: <String, double>{'degrees': hue}),
        if ((sat - 1).abs() > 0.01) ColorOp('saturation', nums: <String, double>{'amount': sat}),
        if ((bri - 1).abs() > 0.01) ColorOp('brightness', nums: <String, double>{'amount': bri}),
        if ((con - 1).abs() > 0.01) ColorOp('contrast', nums: <String, double>{'amount': con}),
        for (final OpPipeline p in _blend) ...p.ops,
      ];

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 110), _compute);
  }

  Future<void> _compute() async {
    final AppState app = context.read<AppState>();
    final String? rel = app.current == null ? null : app.spriteRelFor(app.current!);
    if (rel == null) {
      _preview.value = null;
      return;
    }
    // Load (or reload) the plain base bytes for the GPU preview path.
    if (_baseRel != rel || _baseBytes == null) {
      _baseRel = rel;
      final Uint8List? base = await app.previewSprite(rel);
      if (mounted) setState(() => _baseBytes = base);
    }
    final Uint8List? bytes = await app.previewWithPipeline(rel, _pipeline);
    if (mounted) _preview.value = bytes;
  }

  void _addPreset(OpPipeline p) {
    setState(() => _blend.add(p));
    _schedule();
  }

  void _removeBlend(int i) {
    setState(() => _blend.removeAt(i));
    _schedule();
  }

  void _reset() {
    setState(() {
      hue = 0;
      sat = 1;
      bri = 1;
      con = 1;
      _blend.clear();
    });
    _schedule();
  }

  Future<void> _apply({required bool allSprites}) async {
    final AppState app = context.read<AppState>();
    if (_pipeline.isEmpty) return;
    app.setLivePipeline(_pipeline);
    await app.applyPipeline(allSprites: allSprites);
    // The look is now baked into the sprite(s); reload the base bytes (the
    // pixels changed) and clear the live stack so the preview shows the result
    // instead of re-applying on top.
    _baseRel = null;
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.read<AppState>();
    final bool hasSprite =
        app.current != null && app.spriteRelFor(app.current!) != null;
    _chipsCache ??= _buildChips();

    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: hasSprite
                ? _previewArea(app)
                : const Center(
                    child: Text('Select an emote (Emotes tab) to recolour it.')),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(width: 360, child: _controls()),
      ],
    );
  }

  /// The preview. When the whole live pipeline is an exact linear transform we
  /// filter the base sprite **on the GPU** (a `ColorFilter` matrix) for instant,
  /// per-frame-free feedback; otherwise we fall back to the CPU-baked preview
  /// (HSV ops, gradient maps, blurs, …). The result is always faithful — "Apply"
  /// bakes the same pipeline on the CPU either way.
  Widget _previewArea(AppState app) {
    final List<double>? matrix = app.liveColorMatrix(_pipeline);
    if (matrix != null && _baseBytes != null) {
      return Stack(
        children: <Widget>[
          Positioned.fill(
            child: ZoomCanvas(
              bytes: _baseBytes,
              colorFilter: ColorFilter.matrix(matrix),
            ),
          ),
          const Positioned(top: 10, right: 10, child: _GpuBadge()),
        ],
      );
    }
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: _preview,
      builder: (_, Uint8List? b, __) => ZoomCanvas(bytes: b),
    );
  }

  Widget _controls() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Row(children: <Widget>[
          Text('Adjust', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          TextButton(onPressed: _reset, child: const Text('Reset')),
        ]),
        _slider('Hue', hue, -180, 180, (double v) => hue = v),
        _slider('Saturation', sat, 0, 3, (double v) => sat = v),
        _slider('Brightness', bri, 0, 2, (double v) => bri = v),
        _slider('Contrast', con, 0, 2, (double v) => con = v),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _apply(allSprites: false),
              icon: const Icon(Icons.brush_rounded),
              label: const Text('Apply'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => _apply(allSprites: true),
              icon: const Icon(Icons.select_all_rounded),
              label: const Text('All sprites'),
            ),
          ),
        ]),
        if (_blend.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text('Blended (${_blend.length})',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (int i = 0; i < _blend.length; i++)
                InputChip(
                  label: Text(_blend[i].name),
                  onDeleted: () => _removeBlend(i),
                ),
            ],
          ),
        ],
        const Divider(height: 24),
        _customColour(),
        const Divider(height: 24),
        const Text('Tap presets to blend them together'),
        const SizedBox(height: 8),
        _chipsCache ?? const SizedBox.shrink(),
      ],
    );
  }

  /// Pick ANY colour with a wheel/picker and blend it in several ways.
  Widget _customColour() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Custom colour', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Row(children: <Widget>[
          GestureDetector(
            onTap: _openPicker,
            child: Container(
              width: 40,
              height: 36,
              decoration: BoxDecoration(
                color: _picked,
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Type a hex code directly (e.g. FF5577).
          SizedBox(
            width: 110,
            child: TextField(
              controller: _hexCtrl,
              decoration: const InputDecoration(prefixText: '#', labelText: 'Hex'),
              textCapitalization: TextCapitalization.characters,
              onChanged: _applyHexField,
              onSubmitted: _applyHexField,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Colour wheel',
            onPressed: _openPicker,
            icon: const Icon(Icons.colorize_rounded),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            ActionChip(label: const Text('Recolour to'), onPressed: _applyRecolour),
            ActionChip(label: const Text('Tint'), onPressed: _applyTint),
            ActionChip(label: const Text('Solid fill'), onPressed: _applySolid),
            ActionChip(label: const Text('Gradient'), onPressed: _applyGradientFrom),
          ],
        ),
      ],
    );
  }

  void _openPicker() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Pick a colour'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _picked,
            enableAlpha: false,
            paletteType: PaletteType.hueWheel, // an actual colour wheel
            hexInputBar: true, // editable hex field inside the picker
            labelTypes: const <ColorLabelType>[
              ColorLabelType.hex,
              ColorLabelType.rgb,
              ColorLabelType.hsv,
            ],
            onColorChanged: (Color c) => _setPicked(c),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done')),
        ],
      ),
    );
  }

  String get _hex => formatHexColor(_picked.value);

  void _applyRecolour() {
    final HSVColor h = HSVColor.fromColor(_picked);
    _addPreset(OpPipeline('Recolour $_hex', <ColorOp>[
      ColorOp('colorize', nums: <String, double>{
        'hue': h.hue,
        'saturation': h.saturation,
        'strength': 0.95,
      }),
    ]));
  }

  void _applyTint() => _addPreset(OpPipeline('Tint $_hex', <ColorOp>[
        ColorOp('tint', nums: <String, double>{'amount': 0.5}, strs: <String, String>{'color': _hex}),
      ]));

  void _applySolid() => _addPreset(OpPipeline('Solid $_hex', <ColorOp>[
        ColorOp('solidColor', strs: <String, String>{'color': _hex}),
      ]));

  void _applyGradientFrom() => _addPreset(OpPipeline('Gradient $_hex', <ColorOp>[
        ColorOp('gradientMap',
            nums: <String, double>{'pos0': 0, 'pos1': 1, 'strength': 1},
            strs: <String, String>{'stop0': '#FF000000', 'stop1': _hex}),
      ]));

  /// Built once (presets don't change during a screen visit), so slider drags
  /// don't rebuild ~100 chips.
  Widget _buildChips() {
    final List<OpPipeline> presets = ExtensionRegistry.instance.colorPresets;
    final List<NamedGradient> grads = ExtensionRegistry.instance.gradients;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Presets (${presets.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final OpPipeline preset in presets)
              ActionChip(label: Text(preset.name), onPressed: () => _addPreset(preset)),
          ],
        ),
        const SizedBox(height: 16),
        Text('Gradient maps (${grads.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final NamedGradient g in grads)
              ActionChip(
                label: Text(g.name),
                onPressed: () => _addPreset(
                  OpPipeline(g.name, <ColorOp>[PresetLibrary.gradientMapOp(g)]),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max,
      void Function(double) assign) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$label: ${value.toStringAsFixed(2)}'),
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
}

/// A little "GPU" pill shown while the preview is being rendered live on the
/// compositor (a colour-matrix filter) rather than CPU-baked.
class _GpuBadge extends StatelessWidget {
  const _GpuBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xCC1B5E20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF66BB6A)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.bolt_rounded, size: 14, color: Color(0xFFB9F6CA)),
          SizedBox(width: 3),
          Text('GPU live preview',
              style: TextStyle(fontSize: 11, color: Color(0xFFB9F6CA))),
        ],
      ),
    );
  }
}
