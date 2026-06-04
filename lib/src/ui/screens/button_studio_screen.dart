import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ao_constants.dart';
import '../../core/emote.dart';
import '../../imaging/button_maker.dart';
import '../../imaging/codecs.dart';
import '../../imaging/overlay_presets.dart';
import '../app_state.dart';
import '../widgets/checker_image.dart';
import '../widgets/overlay_builder.dart';

/// Button & char-icon studio.
///
/// Buttons (and the char_icon) are auto-generated on export. This screen lets you
/// choose **how** they're framed — **Head / face** by default (AO buttons show
/// expressions, not whole bodies) or **Full body** — plus the size, head-crop
/// zoom, and (for the icon) which emote it comes from.
///
/// Performance: the screen mutates the [AppState] settings directly (no global
/// rebuilds) and renders each preview through a **debounced** [ValueNotifier], so
/// dragging a slider never re-bakes on every frame or lags other screens.
class ButtonStudioScreen extends StatefulWidget {
  const ButtonStudioScreen({super.key});

  @override
  State<ButtonStudioScreen> createState() => _ButtonStudioScreenState();
}

class _ButtonStudioScreenState extends State<ButtonStudioScreen> {
  final ValueNotifier<Uint8List?> _btnPreview = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<Uint8List?> _iconPreview = ValueNotifier<Uint8List?>(null);
  Timer? _btnDebounce;
  Timer? _iconDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _computeBtn();
      _computeIcon();
    });
  }

  @override
  void dispose() {
    _btnDebounce?.cancel();
    _iconDebounce?.cancel();
    _btnPreview.dispose();
    _iconPreview.dispose();
    super.dispose();
  }

  void _scheduleBtn() {
    _btnDebounce?.cancel();
    _btnDebounce = Timer(const Duration(milliseconds: 90), _computeBtn);
  }

  void _scheduleIcon() {
    _iconDebounce?.cancel();
    _iconDebounce = Timer(const Duration(milliseconds: 90), _computeIcon);
  }

  Future<void> _computeBtn() async {
    final AppState app = context.read<AppState>();
    final Uint8List? b = await app.previewAutoButton(app.buttonSize);
    if (mounted) _btnPreview.value = b;
  }

  Future<void> _computeIcon() async {
    final AppState app = context.read<AppState>();
    final Uint8List? b = await app.previewCharIcon();
    if (mounted) _iconPreview.value = b;
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.read<AppState>();
    final List<Emote> emotes = app.character?.emotes ?? const <Emote>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Button & Icon Studio',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text(
          'Buttons and the char_icon are generated on export. Choose how they '
          'frame each sprite — Head / face (default) shows the expression, Full '
          'body squares the whole sprite. Drag a slider for a quick adjust, or '
          'type an exact value in the box beside it (size, zoom, and ±100% '
          'move X/Y). Output is lossless PNG, crisply downscaled from the '
          'full-res sprite (never upscaled), so bigger sizes just mean "as sharp '
          'as the source allows".',
        ),
        const SizedBox(height: 16),

        _BtnCard(
          app: app,
          preview: _btnPreview,
          onChanged: _scheduleBtn,
        ),
        const SizedBox(height: 16),
        _IconCard(
          app: app,
          emotes: emotes,
          preview: _iconPreview,
          onChanged: _scheduleIcon,
        ),
        const SizedBox(height: 16),

        FilledButton.icon(
          onPressed: () => app.exportZip(),
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Export character (.zip) with buttons + char_icon'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tip: a buttonN_off.png or char_icon.png you import (or save here) is '
          'kept as-is on export — only the missing ones are generated.',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
      ],
    );
  }
}

/// Shared building blocks ------------------------------------------------------

Widget _framingPicker(CropFraming value, ValueChanged<CropFraming> onChanged) {
  return SegmentedButton<CropFraming>(
    segments: const <ButtonSegment<CropFraming>>[
      ButtonSegment<CropFraming>(
        value: CropFraming.head,
        icon: Icon(Icons.face_rounded),
        label: Text('Face'),
      ),
      ButtonSegment<CropFraming>(
        value: CropFraming.full,
        icon: Icon(Icons.accessibility_new_rounded),
        label: Text('Full'),
      ),
      ButtonSegment<CropFraming>(
        value: CropFraming.manual,
        icon: Icon(Icons.crop_rounded),
        label: Text('Manual'),
      ),
    ],
    selected: <CropFraming>{value},
    onSelectionChanged: (Set<CropFraming> s) => onChanged(s.first),
    showSelectedIcon: false,
  );
}

/// The draggable / resizable manual crop box (KFO/DRO style) over the base
/// sprite. It loads the [emote]'s base sprite (reloading on emote / [revision]
/// change), draws the box from [box] (fractions), and reports drags via
/// [onChanged]. [CropBox.toPixels] clamps on render, so even an imperfect drag
/// can only ever produce a valid square button.
class _CropBoxEditor extends StatefulWidget {
  const _CropBoxEditor({
    required this.app,
    required this.emote,
    required this.revision,
    required this.box,
    required this.onChanged,
  });
  final AppState app;
  final Emote? emote;
  final int revision;
  final CropBox box;
  final ValueChanged<CropBox> onChanged;

  @override
  State<_CropBoxEditor> createState() => _CropBoxEditorState();
}

class _CropBoxEditorState extends State<_CropBoxEditor> {
  Uint8List? _bytes;
  double? _aspect;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _CropBoxEditor old) {
    super.didUpdateWidget(old);
    if (old.emote != widget.emote || old.revision != widget.revision) _load();
  }

  Future<void> _load() async {
    _loading = true;
    final ({Uint8List? bytes, double? aspect}) r =
        await widget.app.spriteEditorSource(widget.emote);
    if (!mounted) return;
    setState(() {
      _bytes = r.bytes;
      _aspect = r.aspect;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : const Text('Select an emote to crop.'),
        ),
      );
    }
    final double aspect =
        (_aspect == null || _aspect! <= 0) ? 1.0 : _aspect!;
    final CropBox box = widget.box;
    return SizedBox(
      height: 240,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          double dw = c.maxWidth;
          double dh = dw / aspect;
          if (dh > c.maxHeight) {
            dh = c.maxHeight;
            dw = dh * aspect;
          }
          final double left = box.x * dw, top = box.y * dh, side = box.side * dw;
          return Center(
            child: SizedBox(
              width: dw,
              height: dh,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                      child: CheckerImage(bytes: _bytes, fit: BoxFit.fill)),
                  Positioned(
                    left: left,
                    top: top,
                    width: side,
                    height: side,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (DragUpdateDetails d) {
                        final double nx = (box.x + d.delta.dx / dw)
                            .clamp(0.0, (1 - box.side).clamp(0.0, 1.0));
                        final double maxY =
                            (1 - box.side * aspect).clamp(0.0, 1.0);
                        final double ny =
                            (box.y + d.delta.dy / dh).clamp(0.0, maxY);
                        widget.onChanged(box.copyWith(x: nx, y: ny));
                      },
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0x22FF4081),
                          border: Border.fromBorderSide(
                              BorderSide(color: Color(0xFFFF4081), width: 2)),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (left + side - 16).clamp(0.0, dw - 1),
                    top: (top + side - 16).clamp(0.0, dh - 1),
                    width: 28,
                    height: 28,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (DragUpdateDetails d) {
                        final double ns =
                            (box.side + d.delta.dx / dw).clamp(0.08, 1.0);
                        final double nx =
                            box.x.clamp(0.0, (1 - ns).clamp(0.0, 1.0));
                        final double maxY = (1 - ns * aspect).clamp(0.0, 1.0);
                        final double ny = box.y.clamp(0.0, maxY);
                        widget.onChanged(box.copyWith(side: ns, x: nx, y: ny));
                      },
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFFFF4081),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.open_in_full_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// X / Y / Size sliders for a [CropBox] — the precise (and always-reliable)
/// companion to dragging the box.
Widget _cropSliders(CropBox box, ValueChanged<CropBox> onChanged) {
  return Column(
    children: <Widget>[
      _ValueSlider(
        label: 'Box X',
        value: box.x * 100,
        min: 0,
        max: 100,
        suffix: '%',
        onChanged: (double v) => onChanged(box.copyWith(x: v / 100)),
      ),
      _ValueSlider(
        label: 'Box Y',
        value: box.y * 100,
        min: 0,
        max: 100,
        suffix: '%',
        onChanged: (double v) => onChanged(box.copyWith(y: v / 100)),
      ),
      _ValueSlider(
        label: 'Box size',
        value: box.side * 100,
        min: 5,
        max: 100,
        suffix: '%',
        onChanged: (double v) => onChanged(box.copyWith(side: v / 100)),
      ),
    ],
  );
}

Widget _previewBox(ValueNotifier<Uint8List?> preview, String caption) {
  return Column(
    children: <Widget>[
      Container(
        width: 168,
        height: 168,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ValueListenableBuilder<Uint8List?>(
          valueListenable: preview,
          builder: (_, Uint8List? b, __) => b == null
              ? const Center(child: Text('No sprite'))
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: CheckerImage(bytes: b),
                ),
        ),
      ),
      const SizedBox(height: 6),
      Text(caption),
    ],
  );
}

/// A slider paired with a **typeable value box** — so any setting can be
/// dragged for a quick adjust or typed for an exact value. The field commits on
/// Enter/blur (clamped to [min]..[max]); dragging the slider updates the field
/// live (unless you're editing it). Works for ints (`decimals: 0`) and decimals.
class _ValueSlider extends StatefulWidget {
  const _ValueSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.decimals = 0,
    this.suffix = '',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final int decimals;
  final String suffix;

  @override
  State<_ValueSlider> createState() => _ValueSliderState();
}

class _ValueSliderState extends State<_ValueSlider> {
  late final TextEditingController _ctrl =
      TextEditingController(text: _fmt(widget.value));
  final FocusNode _focus = FocusNode();

  String _fmt(double v) =>
      widget.decimals == 0 ? v.round().toString() : v.toStringAsFixed(widget.decimals);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _ValueSlider old) {
    super.didUpdateWidget(old);
    // Reflect slider / external changes in the field unless it's being edited.
    if (!_focus.hasFocus && _fmt(widget.value) != _ctrl.text) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final double? parsed = double.tryParse(_ctrl.text.trim());
    if (parsed == null) {
      _ctrl.text = _fmt(widget.value); // revert garbage
      return;
    }
    final double clamped = parsed.clamp(widget.min, widget.max);
    _ctrl.text = _fmt(clamped);
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final double v = widget.value.clamp(widget.min, widget.max);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.label),
          Row(
            children: <Widget>[
              Expanded(
                child: Slider(
                  value: v,
                  min: widget.min,
                  max: widget.max,
                  divisions: widget.divisions,
                  label: '${_fmt(v)}${widget.suffix}',
                  onChanged: widget.onChanged,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 68,
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText:
                        widget.suffix.trim().isEmpty ? null : widget.suffix.trim(),
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

/// Import / pick-preset / clear one overlay slot (a border laid on top, or a
/// background behind the sprite). KFO-style frames go in the "Border (on top)"
/// slot. Self-contained so a pick only rebuilds this row. [kind] selects which
/// built-in [OverlayPresets] are offered.
class _OverlayControls extends StatefulWidget {
  const _OverlayControls({
    required this.label,
    required this.slot,
    required this.kind,
    required this.onChanged,
  });
  final String label;
  final OverlaySlot slot;
  final OverlayKind kind;
  final VoidCallback onChanged;

  @override
  State<_OverlayControls> createState() => _OverlayControlsState();
}

class _OverlayControlsState extends State<_OverlayControls> {
  Future<void> _pick() async {
    final FilePickerResult? res =
        await FilePicker.platform.pickFiles(withData: true, type: FileType.image);
    if (res == null || res.files.isEmpty) return;
    final PlatformFile f = res.files.first;
    if (f.bytes == null) return;
    if (!mounted) return;
    context.read<AppState>().setOverlay(
          widget.slot,
          f.bytes!,
          ext: (f.extension ?? 'png').toLowerCase(),
        );
    setState(() {});
    widget.onChanged();
  }

  void _applyPreset(OverlayPreset p) => _applySpec(p.spec.copy());

  /// Apply an editable spec (from a preset or the builder), remembering it so
  /// "Build…" can re-open and tweak it.
  void _applySpec(OverlaySpec spec) {
    // Bake at a high-ish resolution; renderFramed/_fit scales it to the button.
    final Uint8List bytes = Codecs.encodePng(spec.build(256));
    context.read<AppState>().setOverlay(widget.slot, bytes, ext: 'png', spec: spec);
    setState(() {});
    widget.onChanged();
  }

  void _build() => showOverlayBuilder(
        context,
        kind: widget.kind,
        initial: widget.slot.spec,
        onApply: _applySpec,
      );

  void _clear() {
    context.read<AppState>().setOverlay(widget.slot, null);
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final bool set = widget.slot.isSet;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.label, style: const TextStyle(fontSize: 12)),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (set)
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: widget.slot.bytes == null
                      ? null
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CheckerImage(bytes: widget.slot.bytes),
                        ),
                ),
              FilledButton.tonal(
                onPressed: () =>
                    _showOverlayPresetPicker(context, widget.kind, _applyPreset),
                child: const Text('Presets'),
              ),
              OutlinedButton(onPressed: _build, child: const Text('Build…')),
              TextButton(onPressed: _pick, child: Text(set ? 'Import' : 'Import…')),
              if (set)
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: _clear,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cached 56px thumbnails for the preset picker (keyed by kind+name, since a
/// border and a background can share a name like "Monokuma").
final Map<String, Uint8List> _overlayThumbCache = <String, Uint8List>{};

Uint8List _overlayThumb(OverlayPreset p) =>
    _overlayThumbCache.putIfAbsent('${p.kind}:${p.name}',
        () => Codecs.encodePng(p.build(56)));

/// A grid dialog of built-in overlay presets, grouped by category.
Future<void> _showOverlayPresetPicker(
    BuildContext context, OverlayKind kind, ValueChanged<OverlayPreset> onPick) {
  final List<OverlayPreset> presets = OverlayPresets.forKind(kind);
  final List<String> cats = <String>[];
  for (final OverlayPreset p in presets) {
    if (!cats.contains(p.category)) cats.add(p.category);
  }
  return showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(kind == OverlayKind.border
          ? 'Border presets'
          : 'Background presets'),
      content: SizedBox(
        width: 480,
        height: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final String cat in cats) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(cat, style: Theme.of(ctx).textTheme.titleSmall),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final OverlayPreset p
                        in presets.where((OverlayPreset e) => e.category == cat))
                      _PresetSwatch(
                        preset: p,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          onPick(p);
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel')),
      ],
    ),
  );
}

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({required this.preset, required this.onTap});
  final OverlayPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CheckerImage(bytes: _overlayThumb(preset)),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              preset.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// Buttons card ---------------------------------------------------------------

class _BtnCard extends StatefulWidget {
  const _BtnCard({required this.app, required this.preview, required this.onChanged});
  final AppState app;
  final ValueNotifier<Uint8List?> preview;
  final VoidCallback onChanged;

  @override
  State<_BtnCard> createState() => _BtnCardState();
}

class _BtnCardState extends State<_BtnCard> {
  bool _seeded = false;

  /// Seed the manual box from the auto head-square the first time the user
  /// switches to Manual, so they start at the detected face and adjust.
  Future<void> _seedManual() async {
    if (_seeded) return;
    _seeded = true;
    final CropBox seed = await widget.app.headCropFor(widget.app.current);
    if (!mounted) return;
    setState(() => widget.app.buttonCrop = seed);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = widget.app;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('Emote buttons',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Switch(
                  value: app.generateButtons,
                  onChanged: (bool v) => setState(() => app.generateButtons = v),
                ),
                const Text('Generate'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _previewBox(widget.preview, '${app.buttonSize}×${app.buttonSize} px'),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Framing'),
                      const SizedBox(height: 6),
                      _framingPicker(app.buttonFraming, (CropFraming f) {
                        setState(() => app.buttonFraming = f);
                        if (f == CropFraming.manual) _seedManual();
                        widget.onChanged();
                      }),
                      const SizedBox(height: 12),
                      _ValueSlider(
                        label: 'Button size (default 128)',
                        value: app.buttonSize.toDouble(),
                        min: CharFolder.minButtonSize.toDouble(),
                        max: CharFolder.maxButtonSize.toDouble(),
                        divisions: CharFolder.maxButtonSize - CharFolder.minButtonSize,
                        suffix: ' px',
                        onChanged: (double v) {
                          setState(() => app.buttonSize = v.round());
                          widget.onChanged();
                        },
                      ),
                      if (app.buttonFraming == CropFraming.manual) ...<Widget>[
                        const SizedBox(height: 4),
                        const Text(
                          'Drag the box to move it, drag the corner to resize — '
                          'this one box crops every button. (Sliders below for '
                          'exact values.)',
                          style: TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                        const SizedBox(height: 6),
                        _CropBoxEditor(
                          app: app,
                          emote: app.current,
                          revision: app.spriteRevision,
                          box: app.buttonCrop,
                          onChanged: (CropBox b) {
                            setState(() => app.buttonCrop = b);
                            widget.onChanged();
                          },
                        ),
                        _cropSliders(app.buttonCrop, (CropBox b) {
                          setState(() => app.buttonCrop = b);
                          widget.onChanged();
                        }),
                      ] else ...<Widget>[
                        if (app.buttonFraming == CropFraming.head)
                          _ValueSlider(
                            label: 'Face zoom (1.00× default · >1 tighter)',
                            value: app.buttonZoom,
                            min: 0.25,
                            max: 4.0,
                            divisions: 75,
                            decimals: 2,
                            suffix: '×',
                            onChanged: (double v) {
                              setState(() => app.buttonZoom = v);
                              widget.onChanged();
                            },
                          ),
                        _ValueSlider(
                          label: 'Move X',
                          value: app.buttonOffsetX * 100,
                          min: -100,
                          max: 100,
                          divisions: 200,
                          suffix: '%',
                          onChanged: (double v) {
                            setState(() => app.buttonOffsetX = v / 100);
                            widget.onChanged();
                          },
                        ),
                        _ValueSlider(
                          label: 'Move Y',
                          value: app.buttonOffsetY * 100,
                          min: -100,
                          max: 100,
                          divisions: 200,
                          suffix: '%',
                          onChanged: (double v) {
                            setState(() => app.buttonOffsetY = v / 100);
                            widget.onChanged();
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text('Overlays (KFO-style borders)',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      _OverlayControls(
                        label: 'Border (on top)',
                        slot: app.buttonFg,
                        kind: OverlayKind.border,
                        onChanged: widget.onChanged,
                      ),
                      _OverlayControls(
                        label: 'Background',
                        slot: app.buttonBg,
                        kind: OverlayKind.background,
                        onChanged: widget.onChanged,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Char-icon card -------------------------------------------------------------

class _IconCard extends StatefulWidget {
  const _IconCard({
    required this.app,
    required this.emotes,
    required this.preview,
    required this.onChanged,
  });
  final AppState app;
  final List<Emote> emotes;
  final ValueNotifier<Uint8List?> preview;
  final VoidCallback onChanged;

  @override
  State<_IconCard> createState() => _IconCardState();
}

class _IconCardState extends State<_IconCard> {
  bool _seeded = false;

  Future<void> _seedManual() async {
    if (_seeded) return;
    _seeded = true;
    final CropBox seed = await widget.app.headCropFor(widget.app.iconEmote());
    if (!mounted) return;
    setState(() => widget.app.iconCrop = seed);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = widget.app;
    final int maxIndex = widget.emotes.isEmpty ? 0 : widget.emotes.length - 1;
    final int srcIndex = app.iconSourceEmote.clamp(0, maxIndex);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('Character icon (char_icon.png)',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Switch(
                  value: app.generateCharIcon,
                  onChanged: (bool v) => setState(() => app.generateCharIcon = v),
                ),
                const Text('Generate'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _previewBox(widget.preview, '${app.iconSize}×${app.iconSize} px'),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Framing'),
                      const SizedBox(height: 6),
                      _framingPicker(app.iconFraming, (CropFraming f) {
                        setState(() => app.iconFraming = f);
                        if (f == CropFraming.manual) _seedManual();
                        widget.onChanged();
                      }),
                      const SizedBox(height: 12),
                      _ValueSlider(
                        label: 'Icon size (default 40 · AO range 40–128)',
                        value: app.iconSize.toDouble(),
                        min: CharFolder.minIconSize.toDouble(),
                        max: CharFolder.maxIconSize.toDouble(),
                        divisions: CharFolder.maxIconSize - CharFolder.minIconSize,
                        suffix: ' px',
                        onChanged: (double v) {
                          setState(() => app.iconSize = v.round());
                          widget.onChanged();
                        },
                      ),
                      if (app.iconFraming == CropFraming.manual) ...<Widget>[
                        const SizedBox(height: 4),
                        const Text(
                          'Drag the box to move it, drag the corner to resize.',
                          style: TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                        const SizedBox(height: 6),
                        _CropBoxEditor(
                          app: app,
                          emote: app.iconEmote(),
                          revision: app.spriteRevision,
                          box: app.iconCrop,
                          onChanged: (CropBox b) {
                            setState(() => app.iconCrop = b);
                            widget.onChanged();
                          },
                        ),
                        _cropSliders(app.iconCrop, (CropBox b) {
                          setState(() => app.iconCrop = b);
                          widget.onChanged();
                        }),
                      ] else ...<Widget>[
                        if (app.iconFraming == CropFraming.head)
                          _ValueSlider(
                            label: 'Face zoom (1.00× default · >1 tighter)',
                            value: app.iconZoom,
                            min: 0.25,
                            max: 4.0,
                            divisions: 75,
                            decimals: 2,
                            suffix: '×',
                            onChanged: (double v) {
                              setState(() => app.iconZoom = v);
                              widget.onChanged();
                            },
                          ),
                        _ValueSlider(
                          label: 'Move X',
                          value: app.iconOffsetX * 100,
                          min: -100,
                          max: 100,
                          divisions: 200,
                          suffix: '%',
                          onChanged: (double v) {
                            setState(() => app.iconOffsetX = v / 100);
                            widget.onChanged();
                          },
                        ),
                        _ValueSlider(
                          label: 'Move Y',
                          value: app.iconOffsetY * 100,
                          min: -100,
                          max: 100,
                          divisions: 200,
                          suffix: '%',
                          onChanged: (double v) {
                            setState(() => app.iconOffsetY = v / 100);
                            widget.onChanged();
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text('Overlays (KFO-style borders)',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      _OverlayControls(
                        label: 'Border (on top)',
                        slot: app.iconFg,
                        kind: OverlayKind.border,
                        onChanged: widget.onChanged,
                      ),
                      _OverlayControls(
                        label: 'Background',
                        slot: app.iconBg,
                        kind: OverlayKind.background,
                        onChanged: widget.onChanged,
                      ),
                      const SizedBox(height: 12),
                      if (widget.emotes.isNotEmpty) ...<Widget>[
                        const Text('Made from emote'),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          value: srcIndex,
                          decoration: const InputDecoration(isDense: true),
                          items: <DropdownMenuItem<int>>[
                            for (int i = 0; i < widget.emotes.length; i++)
                              DropdownMenuItem<int>(
                                value: i,
                                child: Text(
                                  '${i + 1}. ${widget.emotes[i].comment}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (int? v) {
                            if (v == null) return;
                            setState(() => app.iconSourceEmote = v);
                            widget.onChanged();
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await app.saveCharIcon();
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save char_icon.png now'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
