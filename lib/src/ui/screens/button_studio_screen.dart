import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/ao_constants.dart';
import '../../core/emote.dart';
import '../../imaging/button_maker.dart';
import '../../imaging/codecs.dart';
import '../../imaging/overlay_presets.dart';
import '../app_state.dart';
import '../widgets/checker_image.dart';
import '../widgets/key_capture.dart';
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

  /// Preview render resolution: at least [CharFolder.buttonPreviewRenderPx] so a
  /// small (e.g. 40px) export still frames crisply on screen, but never below
  /// the chosen export size when that's larger (so big buttons show full
  /// detail). The exported file still uses the chosen size — this only affects
  /// the on-screen preview.
  Future<void> _computeBtn() async {
    final AppState app = context.read<AppState>();
    final int previewPx =
        math.max(app.buttonSize, CharFolder.buttonPreviewRenderPx);
    final Uint8List? b = await app.previewAutoButton(previewPx);
    if (!mounted) return;
    _btnPreview.value = b;
    // Tell the list's tiny button thumbnails to re-render with the new framing
    // (debounced — this only runs after the user pauses, and only the ~dozen
    // visible thumbnails actually reload).
    app.bumpButtonStyle();
  }

  Future<void> _computeIcon() async {
    final AppState app = context.read<AppState>();
    final int previewPx =
        math.max(app.iconSize, CharFolder.buttonPreviewRenderPx);
    final Uint8List? b = await app.previewCharIcon(previewPx);
    if (mounted) _iconPreview.value = b;
  }

  /// Select a sprite to frame (from the left list, like the Emotes screen).
  /// Drives the live button preview and — in Manual mode — which sprite's crop
  /// box the editor edits. Seeds the box from the sprite's own auto face on
  /// arrival, then **notifies** so the freshly-seeded box shows immediately.
  Future<void> _selectSprite(int i) async {
    final AppState app = context.read<AppState>();
    // Carry the current framing forward when stepping to a later sprite (same
    // rule as the keyboard), so clicking down the list keeps your box too.
    if (app.buttonFraming == CropFraming.manual) {
      await app.navigateButtonFraming(i);
    } else {
      app.selectEmote(i); // notifies → the right-hand cards rebuild
    }
    _scheduleBtn(); // the icon uses its own source emote, so it's unaffected
  }

  @override
  Widget build(BuildContext context) {
    // A left sprite list (like the Emotes screen) so you can jump straight to
    // any pose to frame its button — plus a tiny preview of each. The right
    // pane (the cards) rebuilds when the selected sprite or its pixels change.
    return Row(
      children: <Widget>[
        SizedBox(width: 260, child: _ButtonSpriteList(onSelect: _selectSprite)),
        const VerticalDivider(width: 1),
        Expanded(
          child: Selector<AppState, (int, int)>(
            selector: (_, AppState a) => (a.selectedEmote, a.spriteRevision),
            builder: (BuildContext context, _, __) => _cards(context),
          ),
        ),
      ],
    );
  }

  Widget _cards(BuildContext context) {
    final AppState app = context.read<AppState>();
    final List<Emote> emotes = app.character?.emotes ?? const <Emote>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Button & Icon Studio',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text(
          'Buttons and the char_icon are generated on export. Pick a sprite on '
          'the left to frame its button, then choose how it frames — Head / face '
          '(default) shows the expression, Full body squares the whole sprite. '
          'Drag a slider for a quick adjust, or type an exact value in the box '
          'beside it (size, zoom, and ±100% move X/Y). Output is lossless PNG, '
          'area-averaged down from the full-res sprite (never upscaled). The '
          'default is the classic 40×40 AO button: exporting at the size the '
          'theme shows it means no blurry theme-side rescale in-game. The '
          'on-screen preview is rendered larger so framing stays crisp — the '
          'file is still the size you pick.',
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
          onPressed: () => app.exportFolder(),
          icon: const Icon(Icons.drive_folder_upload_rounded),
          label: const Text(
              'Save as a folder (no zip) — drops straight into AO'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => app.exportZip(),
          icon: const Icon(Icons.archive_outlined),
          label: const Text('…or export a .zip instead'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Save as a folder writes the finished character folder (char.ini + '
          'sprites + buttons + char_icon) straight to a location you pick — no '
          'zip to extract, DRO/KFO-style. A buttonN_off.png or char_icon.png you '
          'import (or save here) is kept as-is on export — only the missing ones '
          'are generated.',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
      ],
    );
  }
}

/// The left-hand sprite list — the Emotes-screen layout, but for **buttons**:
/// click any sprite to frame it, with a **tiny preview** of each and a tick on
/// the ones you've given a custom (Manual) box. Auto-scrolls to the selected
/// sprite when it changes from the keyboard, so walking a 196-pose cast stays
/// oriented.
class _ButtonSpriteList extends StatefulWidget {
  const _ButtonSpriteList({required this.onSelect});
  final ValueChanged<int> onSelect;

  @override
  State<_ButtonSpriteList> createState() => _ButtonSpriteListState();
}

class _ButtonSpriteListState extends State<_ButtonSpriteList> {
  final ScrollController _scroll = ScrollController();
  int _lastSelected = -1;

  /// Approximate row height — only used to scroll a keyboard-selected (possibly
  /// off-screen) sprite into view.
  static const double _rowExtent = 60;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToSelected(int i) {
    if (!_scroll.hasClients || i < 0) return;
    final ScrollPosition pos = _scroll.position;
    final double rowTop = i * _rowExtent;
    if (rowTop >= pos.pixels &&
        rowTop + _rowExtent <= pos.pixels + pos.viewportDimension) {
      return; // already visible
    }
    _scroll.animateTo(
      (rowTop - 96).clamp(0.0, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (BuildContext context, AppState app, _) {
        final List<Emote> emotes = app.character?.emotes ?? const <Emote>[];
        final bool manual = app.buttonFraming == CropFraming.manual;
        // Auto-scroll to the selected sprite when it changes externally
        // (keyboard nav). Scheduled post-frame — can't scroll during build.
        if (app.selectedEmote != _lastSelected) {
          _lastSelected = app.selectedEmote;
          final int target = app.selectedEmote;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToSelected(target);
          });
        }
        final (int, int) cov = app.buttonCropCoverage;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: <Widget>[
                  const Text('Sprites',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (manual)
                    Text('${cov.$1}/${cov.$2} framed',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white54)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(
                'Click a sprite to frame its button.',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: emotes.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Import sprites to frame buttons.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54)),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: emotes.length,
                      itemBuilder: (BuildContext context, int i) {
                        final Emote e = emotes[i];
                        final bool framed = e.sprite.isNotEmpty &&
                            app.buttonCropRaw(e.sprite) != null;
                        return ListTile(
                          dense: true,
                          selected: i == app.selectedEmote,
                          leading: _ButtonThumb(
                            emote: e,
                            revision: app.buttonThumbKey(e),
                          ),
                          title: Text(
                            e.comment.trim().isEmpty ? e.sprite : e.comment,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(e.sprite,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: manual && framed
                              ? const Tooltip(
                                  message: 'Has a custom box',
                                  child: Icon(Icons.check_circle_rounded,
                                      size: 16, color: Color(0xFFFF4081)),
                                )
                              : null,
                          onTap: () {
                            _lastSelected = i; // suppress the tap auto-scroll
                            widget.onSelect(i);
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// A small thumbnail of the **rendered button** for a sprite (the "tiny
/// preview") — it shows what the button will actually look like with the
/// current framing/zoom/crop/overlays, not the raw sprite. Renders once via
/// [AppState.previewButtonForEmote] (96px) and reloads only when the sprite's
/// pixels ([spriteRevision]) or the button style ([buttonStyleRevision]) change
/// — both folded into [revision]. Lazy per visible row, so a big cast stays
/// snappy.
class _ButtonThumb extends StatefulWidget {
  const _ButtonThumb({required this.emote, required this.revision});
  final Emote? emote;
  final int revision;

  @override
  State<_ButtonThumb> createState() => _ButtonThumbState();
}

class _ButtonThumbState extends State<_ButtonThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    // Paint instantly from the cache (the common case while scrolling) — only
    // render if this sprite's framing isn't cached yet.
    _bytes = context.read<AppState>().cachedButtonThumb(widget.emote);
    if (_bytes == null) _load();
  }

  @override
  void didUpdateWidget(_ButtonThumb old) {
    super.didUpdateWidget(old);
    if (old.emote != widget.emote || old.revision != widget.revision) {
      final Uint8List? hit =
          context.read<AppState>().cachedButtonThumb(widget.emote);
      if (hit != null) {
        setState(() => _bytes = hit); // instant, no re-render
      } else {
        _load();
      }
    }
  }

  Future<void> _load() async {
    final Uint8List? b = await context.read<AppState>().buttonThumb(widget.emote);
    if (mounted) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: _bytes == null
          ? const Icon(Icons.crop_square_rounded, size: 16, color: Colors.white24)
          : CheckerImage(bytes: _bytes),
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
    this.onCommit,
    this.height = 240,
  });
  final AppState app;
  final Emote? emote;
  final int revision;
  final CropBox box;

  /// Live during a drag — writes the box but the host should NOT rebuild on it
  /// (the editor renders the drag itself).
  final ValueChanged<CropBox> onChanged;

  /// Called once when a drag ends — the host does its heavy refresh here.
  final VoidCallback? onCommit;

  /// Editor canvas height. The button card passes a big value (KFO-style large
  /// framing area) so you can place boxes precisely; the icon card stays small.
  final double height;

  @override
  State<_CropBoxEditor> createState() => _CropBoxEditorState();
}

class _CropBoxEditorState extends State<_CropBoxEditor> {
  Uint8List? _bytes;
  double? _aspect;
  bool _loading = false;

  /// The box being dragged — rendered while non-null so a drag is smooth without
  /// rebuilding the whole card every frame; cleared when an external box arrives.
  CropBox? _live;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _CropBoxEditor old) {
    super.didUpdateWidget(old);
    if (old.emote != widget.emote || old.revision != widget.revision) _load();
    if (!identical(old.box, widget.box)) _live = null;
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
        height: widget.height,
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : const Text('Select an emote to crop.'),
        ),
      );
    }
    final double aspect =
        (_aspect == null || _aspect! <= 0) ? 1.0 : _aspect!;
    final CropBox box = _live ?? widget.box;
    return SizedBox(
      height: widget.height,
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
                        final CropBox b = _live ?? widget.box;
                        final double nx = (b.x + d.delta.dx / dw)
                            .clamp(0.0, (1 - b.side).clamp(0.0, 1.0));
                        final double maxY = (1 - b.side * aspect).clamp(0.0, 1.0);
                        final double ny =
                            (b.y + d.delta.dy / dh).clamp(0.0, maxY);
                        final CropBox next = b.copyWith(x: nx, y: ny);
                        setState(() => _live = next);
                        widget.onChanged(next);
                      },
                      onPanEnd: (_) => widget.onCommit?.call(),
                      onPanCancel: () => widget.onCommit?.call(),
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
                        final CropBox b = _live ?? widget.box;
                        final double ns =
                            (b.side + d.delta.dx / dw).clamp(0.08, 1.0);
                        final double nx =
                            b.x.clamp(0.0, (1 - ns).clamp(0.0, 1.0));
                        final double maxY = (1 - ns * aspect).clamp(0.0, 1.0);
                        final double ny = b.y.clamp(0.0, maxY);
                        final CropBox next = b.copyWith(side: ns, x: nx, y: ny);
                        setState(() => _live = next);
                        widget.onChanged(next);
                      },
                      onPanEnd: (_) => widget.onCommit?.call(),
                      onPanCancel: () => widget.onCommit?.call(),
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

/// Steps the Button Studio's "current sprite" in Manual mode (◀ ▶) and shows
/// which sprite you're framing plus how many have a custom box, so editing all
/// of a cast's poses by hand is one tidy walk instead of bouncing to the Emotes
/// screen per sprite.
class _SpriteNav extends StatelessWidget {
  const _SpriteNav({required this.app, required this.onGoto});
  final AppState app;
  final ValueChanged<int> onGoto;

  @override
  Widget build(BuildContext context) {
    final List<Emote> emotes = app.character?.emotes ?? const <Emote>[];
    if (emotes.isEmpty) {
      return const Text('No emotes to frame yet — import sprites first.',
          style: TextStyle(fontSize: 12, color: Colors.white60));
    }
    final int i = app.selectedEmote.clamp(0, emotes.length - 1);
    final Emote e = emotes[i];
    final (int, int) cov = app.buttonCropCoverage;
    final String label =
        e.comment.trim().isEmpty ? e.sprite : '${e.comment}  ·  ${e.sprite}';
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Previous sprite',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: i > 0 ? () => onGoto(i - 1) : null,
        ),
        Expanded(
          child: Column(
            children: <Widget>[
              Text('Sprite ${i + 1} of ${emotes.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              Text('${cov.$1} of ${cov.$2} sprites customised',
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Next sprite',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: i < emotes.length - 1 ? () => onGoto(i + 1) : null,
        ),
      ],
    );
  }
}

/// Per-sprite Manual actions: snap the current sprite back to its auto face
/// crop, or stamp the current box onto every sprite at once (when many poses
/// share a framing).
class _ManualCropActions extends StatelessWidget {
  const _ManualCropActions(
      {required this.app, required this.emote, required this.onChanged});
  final AppState app;
  final Emote? emote;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final Emote? e = emote;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: e == null
                ? null
                : () async {
                    await app.resetButtonCropFor(e);
                    onChanged();
                  },
            icon: const Icon(Icons.restore_rounded, size: 16),
            label: const Text('Reset this sprite to auto'),
          ),
          OutlinedButton.icon(
            onPressed: e == null
                ? null
                : () {
                    app.applyButtonCropToAll(app.buttonCropFor(e.sprite));
                    onChanged();
                  },
            icon: const Icon(Icons.select_all_rounded, size: 16),
            label: const Text('Apply this box to all sprites'),
          ),
        ],
      ),
    );
  }
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
    required this.onSet,
    required this.onChanged,
    this.onApplyAll,
    this.scopeNote,
  });
  final String label;

  /// The slot to **display** (its current art/spec). For per-sprite button
  /// overlays this is the *selected sprite's* slot; for the icon it's the single
  /// icon slot. Mutations go through [onSet], not by writing the slot directly,
  /// so the owner controls where the art is stored.
  final OverlaySlot slot;
  final OverlayKind kind;

  /// Apply art to the slot (null [bytes] clears it). [spec] is set for
  /// preset/built overlays so "Build…"/"Save" can re-open them.
  final void Function(Uint8List? bytes, String ext, OverlaySpec? spec) onSet;
  final VoidCallback onChanged;

  /// When non-null, an **"Apply to all sprites"** button is shown (per-sprite
  /// button overlays); null for the single-slot icon.
  final VoidCallback? onApplyAll;

  /// Optional caption under the controls (e.g. "this sprite — k/N have a
  /// border").
  final String? scopeNote;

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
    widget.onSet(f.bytes!, (f.extension ?? 'png').toLowerCase(), null);
    setState(() {});
    widget.onChanged();
  }

  void _applyPreset(OverlayPreset p) => _applySpec(p.spec.copy());

  /// Apply an editable spec (from a preset or the builder), remembering it so
  /// "Build…" can re-open and tweak it.
  void _applySpec(OverlaySpec spec) {
    // Bake at a high-ish resolution; renderFramed/_fit scales it to the button.
    final Uint8List bytes = Codecs.encodePng(spec.build(256));
    widget.onSet(bytes, 'png', spec);
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
    widget.onSet(null, 'png', null);
    setState(() {});
    widget.onChanged();
  }

  void _applyAll() {
    widget.onApplyAll?.call();
    setState(() {});
    widget.onChanged();
  }

  /// Save the slot's current built/preset spec as a reusable **user preset**
  /// (persists across sessions, shows up in the Presets picker). Only offered
  /// when the slot holds an editable spec (not an imported PNG).
  Future<void> _saveAsPreset() async {
    final OverlaySpec? spec = widget.slot.spec;
    if (spec == null) return;
    final String? name = await _promptPresetName(context);
    if (name == null || name.trim().isEmpty || !mounted) return;
    context.read<AppState>().saveOverlayPreset(name.trim(), spec);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved overlay preset "${name.trim()}".')),
      );
    }
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
              if (widget.slot.spec != null)
                TextButton.icon(
                  onPressed: _saveAsPreset,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                  label: const Text('Save'),
                ),
              TextButton(onPressed: _pick, child: Text(set ? 'Import' : 'Import…')),
              if (set)
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: _clear,
                ),
              // Per-sprite by default → offer copying this border to the cast.
              if (widget.onApplyAll != null && set)
                TextButton.icon(
                  onPressed: _applyAll,
                  icon: const Icon(Icons.select_all_rounded, size: 16),
                  label: const Text('Apply to all sprites'),
                ),
            ],
          ),
          if (widget.scopeNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(widget.scopeNote!,
                  style: const TextStyle(fontSize: 10, color: Colors.white38)),
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

/// Caption for the per-sprite button overlay controls: how many sprites in the
/// cast currently wear a border/background.
String _overlayScopeNote(AppState app) {
  final (int done, int total) = app.buttonOverlayCoverage;
  return 'this sprite · $done/$total sprite(s) have an overlay';
}

/// Prompt for a name to save a built overlay as a user preset.
Future<String?> _promptPresetName(BuildContext context) {
  final TextEditingController c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('Save overlay preset'),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Preset name',
          hintText: 'e.g. My pink frame',
        ),
        onSubmitted: (String v) => Navigator.pop(ctx, v),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Save')),
      ],
    ),
  );
}

/// A grid dialog of overlay presets, grouped by category — your **★ Saved**
/// presets first (tap to use, × to delete), then the built-ins.
Future<void> _showOverlayPresetPicker(
    BuildContext context, OverlayKind kind, ValueChanged<OverlayPreset> onPick) {
  final List<OverlayPreset> presets = OverlayPresets.forKind(kind);
  final List<String> cats = <String>[];
  for (final OverlayPreset p in presets) {
    if (!cats.contains(p.category)) cats.add(p.category);
  }
  final AppState app = context.read<AppState>();
  return showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter setD) {
        final List<({String name, OverlaySpec spec})> saved =
            app.userOverlaysFor(kind);
        return AlertDialog(
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
                  if (saved.isNotEmpty) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text('★ Saved',
                          style: Theme.of(ctx).textTheme.titleSmall),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final ({String name, OverlaySpec spec}) p in saved)
                          _PresetSwatch(
                            preset: OverlayPreset(p.name, 'Saved', p.spec),
                            useCache: false, // a re-saved name may differ
                            onTap: () {
                              Navigator.of(ctx).pop();
                              onPick(OverlayPreset(p.name, 'Saved', p.spec));
                            },
                            onDelete: () {
                              app.deleteOverlayPreset(p.name);
                              setD(() {});
                            },
                          ),
                      ],
                    ),
                  ],
                  for (final String cat in cats) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(cat, style: Theme.of(ctx).textTheme.titleSmall),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final OverlayPreset p in presets
                            .where((OverlayPreset e) => e.category == cat))
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
        );
      },
    ),
  );
}

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    required this.preset,
    required this.onTap,
    this.onDelete,
    this.useCache = true,
  });
  final OverlayPreset preset;
  final VoidCallback onTap;

  /// When non-null, a small × in the corner deletes this (saved) preset.
  final VoidCallback? onDelete;

  /// Built-ins cache their 56px thumbnail by name; saved presets don't (a name
  /// can be re-saved with a different spec), so they build fresh.
  final bool useCache;

  @override
  Widget build(BuildContext context) {
    final Uint8List thumb =
        useCache ? _overlayThumb(preset) : Codecs.encodePng(preset.build(56));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CheckerImage(bytes: thumb),
                    ),
                  ),
                ),
                if (onDelete != null)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: GestureDetector(
                      onTap: onDelete,
                      child: const CircleAvatar(
                        radius: 9,
                        backgroundColor: Color(0xFFB00020),
                        child: Icon(Icons.close_rounded,
                            size: 12, color: Colors.white),
                      ),
                    ),
                  ),
              ],
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
  @override
  void initState() {
    super.initState();
    // If the studio is already in Manual when re-entered, seed the current
    // sprite so its box matches the live preview straight away.
    if (widget.app.buttonFraming == CropFraming.manual) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _seedManual();
      });
    }
  }

  /// Keyboard focus for the manual framing area, so you can step through a whole
  /// cast and frame each pose without ever reaching for the navigation rail —
  /// the KFO complaint ("had to move the mouse to the top to pick the next
  /// sprite"). Shortcuts only fire while this node has primary focus, so typing
  /// in a value box never triggers them.
  final FocusNode _kbFocus = FocusNode(debugLabel: 'btnFramingKeys');

  @override
  void dispose() {
    _kbFocus.dispose();
    super.dispose();
  }

  /// Single-key framing shortcuts (active while the framing area is focused —
  /// click the sprite once to focus it). The keys are **rebindable** (and
  /// persist) via [AppState.framingKeys] — defaults are the plain arrow keys
  /// (prev/next), Enter (make it & next), R (reset), A (apply to all) and F
  /// (cycle framing). No `[`/`]` weirdness. Documented in the F1 cheat-sheet and
  /// docs/SHORTCUTS.md. Boxes commit live, so advancing *is* finishing the
  /// current sprite.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    final AppState app = widget.app;
    final int n = app.character?.emotes.length ?? 0;
    if (n == 0) return KeyEventResult.ignored;
    final int i = app.selectedEmote.clamp(0, n - 1);
    final LogicalKeyboardKey k = event.logicalKey;

    // Shift + arrows nudge the crop box precisely (plain arrows step sprites).
    if (HardwareKeyboard.instance.isShiftPressed) {
      final double step = (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed)
          ? 0.02
          : 0.005;
      double dx = 0, dy = 0;
      if (k == LogicalKeyboardKey.arrowLeft) dx = -step;
      if (k == LogicalKeyboardKey.arrowRight) dx = step;
      if (k == LogicalKeyboardKey.arrowUp) dy = -step;
      if (k == LogicalKeyboardKey.arrowDown) dy = step;
      if (dx != 0 || dy != 0) {
        final Emote? e = app.current;
        if (e != null && e.sprite.isNotEmpty) {
          final CropBox b = app.buttonCropFor(e.sprite);
          final double maxXY = (1 - b.side).clamp(0.0, 1.0);
          app.setButtonCrop(
              e.sprite,
              b.copyWith(
                x: (b.x + dx).clamp(0.0, maxXY),
                y: (b.y + dy).clamp(0.0, maxXY),
              ));
          setState(() {});
          widget.onChanged();
        }
        return KeyEventResult.handled;
      }
    }

    final Map<String, LogicalKeyboardKey> keys = app.framingKeys;

    // Match the pressed key against a bound action (Numpad Enter counts as Enter
    // for "make it & next").
    bool isAction(String id) {
      final LogicalKeyboardKey? bound = keys[id];
      if (bound == null) return false;
      if (k == bound) return true;
      return bound == LogicalKeyboardKey.enter &&
          k == LogicalKeyboardKey.numpadEnter;
    }

    if (isAction('next') || isAction('make')) {
      _gotoEmote(i + 1);
      return KeyEventResult.handled;
    }
    if (isAction('prev')) {
      _gotoEmote(i - 1);
      return KeyEventResult.handled;
    }
    if (isAction('reset')) {
      final Emote? e = app.current;
      if (e != null) {
        app.resetButtonCropFor(e).then((_) {
          if (mounted) {
            setState(() {});
            widget.onChanged();
          }
        });
      }
      return KeyEventResult.handled;
    }
    if (isAction('all')) {
      final Emote? e = app.current;
      if (e != null) {
        app.applyButtonCropToAll(app.buttonCropFor(e.sprite));
        setState(() {});
        widget.onChanged();
      }
      return KeyEventResult.handled;
    }
    if (isAction('framing')) {
      const List<CropFraming> order = <CropFraming>[
        CropFraming.head,
        CropFraming.full,
        CropFraming.manual,
      ];
      final CropFraming next =
          order[(order.indexOf(app.buttonFraming) + 1) % order.length];
      setState(() => app.buttonFraming = next);
      if (next == CropFraming.manual) _seedManual();
      widget.onChanged();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The manual-mode hint — built from the **live** [AppState.framingKeys] so it
  /// always shows the real (possibly rebound) keys instead of going stale.
  Widget _manualHint() {
    final Map<String, LogicalKeyboardKey> k = widget.app.framingKeys;
    String lbl(String id) => keyLabel(k[id]!);
    return Text(
      'Each sprite has its OWN box. Click the sprite to focus, then use the '
      'keyboard:  ${lbl('prev')} / ${lbl('next')} previous / next sprite · '
      '${lbl('make')} make it & next · ${lbl('reset')} reset this sprite to '
      'auto · ${lbl('all')} apply this box to all · ${lbl('framing')} cycle '
      'framing. Drag the box to move it, the corner to resize, or **Shift + '
      'arrows** to nudge it precisely (add Ctrl for a bigger step); sprites you '
      'never touch auto-frame the face. Rebind these keys in the F1 shortcuts '
      'dialog.',
      style: const TextStyle(fontSize: 12, color: Colors.white60),
    );
  }

  /// Seed the **current sprite's** manual box from its own auto head-square the
  /// first time it's shown in Manual mode (each sprite keeps its own box). If no
  /// emote is selected yet, point at the first one so the editor + preview have
  /// a sprite to act on.
  Future<void> _seedManual() async {
    final AppState app = widget.app;
    if (app.current == null && (app.character?.emotes.isNotEmpty ?? false)) {
      app.selectEmote(0);
    }
    await app.ensureButtonCropSeeded(app.current);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  /// Step the Button Studio's "current sprite" (drives both the per-sprite crop
  /// editor and the live preview), seeding the newly-shown sprite on arrival.
  /// Moving **forward** (Enter / →) carries your current box onto the next
  /// sprite if it has none yet, so advancing keeps your framing instead of
  /// resetting to that sprite's auto face. Going back seeds the auto face.
  Future<void> _gotoEmote(int index) async {
    await widget.app.navigateButtonFraming(index);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = widget.app;
    // Capture the current emote/sprite ONCE per build so the Manual editor's
    // display, its lookups, and its writes all agree. (`app.current` can change
    // without rebuilding this card — e.g. the global prev/next-emote shortcut —
    // which would otherwise show sprite A while a drag wrote to sprite B's box.)
    final Emote? cur = app.current;
    final String? curSprite = cur?.sprite;
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
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Regenerate buttons on export'),
              subtitle: const Text(
                  'Rebuild buttons + char_icon from this framing and drop the '
                  "imported emotions/ folder (fixes buttons that don't match the "
                  'sprite). Off keeps hand-imported buttons.'),
              value: app.regenerateButtonsOnExport,
              onChanged: (bool? v) =>
                  setState(() => app.setRegenerateButtonsOnExport(v ?? true)),
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
                        label: 'Button size (default 40 · AO classic)',
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
                      if (app.buttonFraming == CropFraming.manual)
                        Focus(
                          focusNode: _kbFocus,
                          autofocus: true,
                          onKeyEvent: _onKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const SizedBox(height: 8),
                              // The DRO-style **big** framing editor: a large
                              // zoom + pan canvas in its own full-screen view,
                              // so the sprite shows up big and you can frame the
                              // button precisely.
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () async {
                                    await openButtonFramingEditor(context, app);
                                    if (mounted) {
                                      setState(() {});
                                      widget.onChanged();
                                    }
                                  },
                                  icon: const Icon(Icons.open_in_full_rounded),
                                  label: const Text(
                                      'Open the BIG framing editor (zoom & pan)'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _manualHint(),
                              const SizedBox(height: 6),
                              _SpriteNav(app: app, onGoto: _gotoEmote),
                              const SizedBox(height: 6),
                              // Pointer-down on the framing canvas grabs
                              // keyboard focus, so the framing keys (← → Enter R
                              // A F) work straight after you click a sprite.
                              Listener(
                                onPointerDown: (_) => _kbFocus.requestFocus(),
                                child: _CropBoxEditor(
                                  app: app,
                                  emote: cur,
                                  revision: app.spriteRevision,
                                  box: app.buttonCropFor(curSprite),
                                  height: 440,
                                  // Live drag: write the box but don't rebuild
                                  // the card (the editor renders the drag).
                                  onChanged: (CropBox b) =>
                                      app.setButtonCrop(curSprite, b),
                                  // One rebuild + preview refresh on release.
                                  onCommit: () {
                                    setState(() {});
                                    widget.onChanged();
                                  },
                                ),
                              ),
                              _cropSliders(app.buttonCropFor(curSprite),
                                  (CropBox b) {
                                setState(() => app.setButtonCrop(curSprite, b));
                                widget.onChanged();
                              }),
                              _ManualCropActions(
                                app: app,
                                emote: cur,
                                onChanged: () {
                                  setState(() {});
                                  widget.onChanged();
                                },
                              ),
                            ],
                          ),
                        )
                      else ...<Widget>[
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
                      const Text(
                        'Applied to THIS sprite only — use "Apply to all '
                        'sprites" to give the whole cast the same border.',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      _OverlayControls(
                        label: 'Border (on top)',
                        slot: app.buttonOverlaySlotFor(curSprite, fg: true),
                        kind: OverlayKind.border,
                        onSet: (Uint8List? b, String e, OverlaySpec? s) => app
                            .setButtonOverlay(curSprite, b, fg: true, ext: e, spec: s),
                        onApplyAll: () =>
                            app.applyButtonOverlayToAll(curSprite, fg: true),
                        scopeNote: _overlayScopeNote(app),
                        onChanged: widget.onChanged,
                      ),
                      _OverlayControls(
                        label: 'Background',
                        slot: app.buttonOverlaySlotFor(curSprite, fg: false),
                        kind: OverlayKind.background,
                        onSet: (Uint8List? b, String e, OverlaySpec? s) => app
                            .setButtonOverlay(curSprite, b, fg: false, ext: e, spec: s),
                        onApplyAll: () =>
                            app.applyButtonOverlayToAll(curSprite, fg: false),
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
                          onChanged: (CropBox b) => app.iconCrop = b,
                          onCommit: () {
                            setState(() {});
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
                        onSet: (Uint8List? b, String e, OverlaySpec? s) =>
                            app.setOverlay(app.iconFg, b, ext: e, spec: s),
                        onChanged: widget.onChanged,
                      ),
                      _OverlayControls(
                        label: 'Background',
                        slot: app.iconBg,
                        kind: OverlayKind.background,
                        onSet: (Uint8List? b, String e, OverlaySpec? s) =>
                            app.setOverlay(app.iconBg, b, ext: e, spec: s),
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

/// The big framing editor ------------------------------------------------------

/// Open the **DRO-style big framing editor** — a full-screen view with a large
/// zoom + pan canvas, the sprite list, and the same per-sprite box + keyboard
/// flow as the inline studio. Ensures Manual framing + a seeded current sprite
/// first.
Future<void> openButtonFramingEditor(BuildContext context, AppState app) async {
  app.buttonFraming = CropFraming.manual;
  if (app.current == null && (app.character?.emotes.isNotEmpty ?? false)) {
    app.selectEmote(0);
  }
  await app.ensureButtonCropSeeded(app.current);
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => _ButtonFramingEditor(app: app),
  ));
}

class _ButtonFramingEditor extends StatelessWidget {
  const _ButtonFramingEditor({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Frame buttons — big editor'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Done'),
            ),
          ),
        ],
      ),
      body: Row(
        children: <Widget>[
          SizedBox(
            width: 240,
            child: _ButtonSpriteList(
              onSelect: (int i) => app.navigateButtonFraming(i),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _FramingPane(app: app)),
        ],
      ),
    );
  }
}

/// The middle + right of the big editor: a full-height zoom/pan canvas plus a
/// control sidebar (live button preview, box sliders as the always-works safety
/// net, reset/apply, hint). Keyboard framing keys (prev/next/make/reset/all)
/// work while the canvas is focused. Box drags rebuild only this pane — the
/// sprite list is a sibling, so a 196-cast list isn't rebuilt mid-drag.
class _FramingPane extends StatefulWidget {
  const _FramingPane({required this.app});
  final AppState app;

  @override
  State<_FramingPane> createState() => _FramingPaneState();
}

class _FramingPaneState extends State<_FramingPane> {
  final FocusNode _kbFocus = FocusNode(debugLabel: 'framingEditorKeys');
  final ValueNotifier<Uint8List?> _preview = ValueNotifier<Uint8List?>(null);
  Timer? _debounce;
  String? _lastPreviewedSprite;

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
    _kbFocus.dispose();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 90), _compute);
  }

  Future<void> _compute() async {
    final AppState app = widget.app;
    _lastPreviewedSprite = app.current?.sprite;
    final Uint8List? b = await app.previewButtonForEmote(
        app.current, math.max(app.buttonSize, CharFolder.buttonPreviewRenderPx));
    if (!mounted) return;
    _preview.value = b;
    app.bumpButtonStyle(); // refresh the list's tiny button thumbnails
  }

  Future<void> _goto(int index) async {
    await widget.app.navigateButtonFraming(index);
    if (mounted) {
      setState(() {});
      _schedule();
    }
  }

  /// Move the current sprite's crop box by ([dx],[dy]) fractions, clamped in
  /// bounds — the keyboard fine-nudge.
  void _nudgeBox(double dx, double dy) {
    final AppState app = widget.app;
    final Emote? e = app.current;
    if (e == null || e.sprite.isEmpty) return;
    final CropBox b = app.buttonCropFor(e.sprite);
    final double maxXY = (1 - b.side).clamp(0.0, 1.0);
    final CropBox next = b.copyWith(
      x: (b.x + dx).clamp(0.0, maxXY),
      y: (b.y + dy).clamp(0.0, maxXY),
    );
    app.setButtonCrop(e.sprite, next);
    setState(() {});
    _schedule();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    final AppState app = widget.app;
    final int n = app.character?.emotes.length ?? 0;
    if (n == 0) return KeyEventResult.ignored;
    final int i = app.selectedEmote.clamp(0, n - 1);
    final LogicalKeyboardKey k = event.logicalKey;

    // Shift + arrows **nudge the pink box precisely** (plain arrows step
    // sprites). Held = repeats; add Ctrl/⌘ for a bigger 2% jump.
    if (HardwareKeyboard.instance.isShiftPressed) {
      final double step = (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed)
          ? 0.02
          : 0.005;
      double dx = 0, dy = 0;
      if (k == LogicalKeyboardKey.arrowLeft) dx = -step;
      if (k == LogicalKeyboardKey.arrowRight) dx = step;
      if (k == LogicalKeyboardKey.arrowUp) dy = -step;
      if (k == LogicalKeyboardKey.arrowDown) dy = step;
      if (dx != 0 || dy != 0) {
        _nudgeBox(dx, dy);
        return KeyEventResult.handled;
      }
    }

    final Map<String, LogicalKeyboardKey> keys = app.framingKeys;
    bool isAction(String id) {
      final LogicalKeyboardKey? bound = keys[id];
      if (bound == null) return false;
      if (k == bound) return true;
      return bound == LogicalKeyboardKey.enter &&
          k == LogicalKeyboardKey.numpadEnter;
    }

    if (isAction('next') || isAction('make')) {
      _goto(i + 1);
      return KeyEventResult.handled;
    }
    if (isAction('prev')) {
      _goto(i - 1);
      return KeyEventResult.handled;
    }
    if (isAction('reset')) {
      final Emote? e = app.current;
      if (e != null) {
        app.resetButtonCropFor(e).then((_) {
          if (mounted) {
            setState(() {});
            _schedule();
          }
        });
      }
      return KeyEventResult.handled;
    }
    if (isAction('all')) {
      final Emote? e = app.current;
      if (e != null) {
        app.applyButtonCropToAll(app.buttonCropFor(e.sprite));
        setState(() {});
        _schedule();
      }
      return KeyEventResult.handled;
    }
    // 'framing' (F) is intentionally not handled — this editor is Manual-only.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.app,
      builder: (BuildContext context, _) {
        final AppState app = widget.app;
        final Emote? cur = app.current;
        final String? curSprite = cur?.sprite;
        // Keep the live preview in sync no matter who changed the selection
        // (list click or keyboard) — schedule a recompute when the sprite flips.
        if (cur?.sprite != _lastPreviewedSprite) {
          _lastPreviewedSprite = cur?.sprite;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _schedule();
          });
        }
        return Row(
          children: <Widget>[
            Expanded(
              child: Focus(
                focusNode: _kbFocus,
                autofocus: true,
                onKeyEvent: _onKey,
                child: Column(
                  children: <Widget>[
                    _SpriteNav(app: app, onGoto: _goto),
                    Expanded(
                      child: Listener(
                        onPointerDown: (_) => _kbFocus.requestFocus(),
                        child: Container(
                          color: const Color(0xFF1A1A1A),
                          child: _ManualCanvasLoader(
                            app: app,
                            emote: cur,
                            revision: app.spriteRevision,
                            box: app.buttonCropFor(curSprite),
                            // Live drag: write the box but DON'T rebuild the pane
                            // (the canvas renders the drag itself) — this is what
                            // keeps dragging smooth on a big cast.
                            onChanged: (CropBox b) =>
                                app.setButtonCrop(curSprite, b),
                            // Drag end: one rebuild (slider sync) + debounced
                            // preview, instead of doing it every frame.
                            onCommit: () {
                              if (mounted) {
                                setState(() {});
                                _schedule();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 280,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(child: _previewBox(_preview, '${app.buttonSize}px')),
                    const SizedBox(height: 12),
                    const Text(
                      'Scroll to zoom · drag the sprite to pan · drag the box to '
                      'move it, its corner to resize · Shift + arrows nudge the '
                      'box precisely (Ctrl for a bigger step). Sliders below '
                      'always work if you prefer exact values.',
                      style: TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                    const SizedBox(height: 8),
                    _ValueSlider(
                      label: 'Button size',
                      value: app.buttonSize.toDouble(),
                      min: CharFolder.minButtonSize.toDouble(),
                      max: CharFolder.maxButtonSize.toDouble(),
                      divisions:
                          CharFolder.maxButtonSize - CharFolder.minButtonSize,
                      suffix: ' px',
                      onChanged: (double v) {
                        setState(() => app.buttonSize = v.round());
                        _schedule();
                      },
                    ),
                    _cropSliders(app.buttonCropFor(curSprite), (CropBox b) {
                      setState(() => app.setButtonCrop(curSprite, b));
                      _schedule();
                    }),
                    _ManualCropActions(
                      app: app,
                      emote: cur,
                      onChanged: () {
                        setState(() {});
                        _schedule();
                      },
                    ),
                    const Divider(height: 24),
                    // Apply a KFO-style border / background to the buttons right
                    // here — pick a preset, build one (its own big editor), or
                    // import a PNG — so you can frame AND skin in one pass.
                    const Text('Overlays (KFO-style borders)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    const Text(
                      'This sprite only — "Apply to all sprites" gives the whole '
                      'cast the same border. See it live in the preview above.',
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                    _OverlayControls(
                      label: 'Border (on top)',
                      slot: app.buttonOverlaySlotFor(curSprite, fg: true),
                      kind: OverlayKind.border,
                      onSet: (Uint8List? b, String e, OverlaySpec? s) => app
                          .setButtonOverlay(curSprite, b, fg: true, ext: e, spec: s),
                      onApplyAll: () =>
                          app.applyButtonOverlayToAll(curSprite, fg: true),
                      scopeNote: _overlayScopeNote(app),
                      onChanged: _schedule,
                    ),
                    _OverlayControls(
                      label: 'Background',
                      slot: app.buttonOverlaySlotFor(curSprite, fg: false),
                      kind: OverlayKind.background,
                      onSet: (Uint8List? b, String e, OverlaySpec? s) => app
                          .setButtonOverlay(curSprite, b, fg: false, ext: e, spec: s),
                      onApplyAll: () =>
                          app.applyButtonOverlayToAll(curSprite, fg: false),
                      onChanged: _schedule,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Loads a sprite's bytes/aspect for [_ManualCanvas] (reloading when the emote
/// or its pixels change) while keeping the canvas mounted so its zoom/pan
/// **persist** as you step through similar poses.
class _ManualCanvasLoader extends StatefulWidget {
  const _ManualCanvasLoader({
    required this.app,
    required this.emote,
    required this.revision,
    required this.box,
    required this.onChanged,
    this.onCommit,
  });
  final AppState app;
  final Emote? emote;
  final int revision;
  final CropBox box;
  final ValueChanged<CropBox> onChanged;
  final VoidCallback? onCommit;

  @override
  State<_ManualCanvasLoader> createState() => _ManualCanvasLoaderState();
}

class _ManualCanvasLoaderState extends State<_ManualCanvasLoader> {
  Uint8List? _bytes;
  double? _aspect;
  bool _loading = false;
  Timer? _loadTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ManualCanvasLoader old) {
    super.didUpdateWidget(old);
    if (old.emote != widget.emote || old.revision != widget.revision) {
      // Debounce: when you blast through sprites with the keyboard, only the
      // sprite you settle on decodes/encodes — not every one you pass (the
      // canvas keeps showing the previous sprite until then).
      _loadTimer?.cancel();
      _loadTimer = Timer(const Duration(milliseconds: 70), _load);
    }
  }

  Future<void> _load() async {
    _loading = true;
    // NB: don't null `_bytes` here — keep showing the old sprite (and the canvas
    // mounted, so zoom/pan survive) until the new bytes arrive.
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
      return Center(
        child: _loading
            ? const CircularProgressIndicator()
            : const Text('Select a sprite to frame.',
                style: TextStyle(color: Colors.white60)),
      );
    }
    return _ManualCanvas(
      bytes: _bytes!,
      aspect: (_aspect == null || _aspect! <= 0) ? 1.0 : _aspect!,
      box: widget.box,
      onChanged: widget.onChanged,
      onCommit: widget.onCommit,
    );
  }
}

/// The zoom + pan crop-box canvas. **One coordinate origin** (top-left): a
/// base-fit sprite rect of [_baseW]×[_baseH] is drawn at `_pan + base·_scale`,
/// and the box overlays it at the same scale, so a point's screen position is
/// always `_pan + base·_scale`. A single [GestureDetector] hit-tests in that
/// screen space (corner → resize, inside box → move, else → pan), so there's no
/// gesture-arena ambiguity; scroll zooms about the cursor. The Box X/Y/Size
/// sliders (in the sidebar) write the box independently, so framing always works
/// even if a drag feels off.
class _ManualCanvas extends StatefulWidget {
  const _ManualCanvas({
    required this.bytes,
    required this.aspect,
    required this.box,
    required this.onChanged,
    this.onCommit,
  });
  final Uint8List bytes;
  final double aspect; // width / height
  final CropBox box;

  /// Called live while dragging the box (writes the new box to app state, but
  /// the caller should NOT rebuild on this — the canvas shows the drag itself).
  final ValueChanged<CropBox> onChanged;

  /// Called once when a box drag ends — the caller does the heavy refresh
  /// (slider sync + debounced preview) here, not per frame.
  final VoidCallback? onCommit;

  @override
  State<_ManualCanvas> createState() => _ManualCanvasState();
}

class _ManualCanvasState extends State<_ManualCanvas> {
  static const double _minScale = 0.25, _maxScale = 12.0;
  double _scale = 1.0;

  /// The box being dragged. While non-null the canvas renders THIS (so a drag is
  /// smooth without rebuilding the sidebar/preview every frame); it's cleared
  /// when the committed box arrives back via [didUpdateWidget].
  CropBox? _live;
  Offset? _pan; // viewport px; null until first layout (then centred)
  Size _viewport = Size.zero;
  double _baseW = 1, _baseH = 1;
  int _mode = 0; // 1 = pan, 2 = move box, 3 = resize box

  Offset _centerPan(double scale) => Offset(
        (_viewport.width - _baseW * scale) / 2,
        (_viewport.height - _baseH * scale) / 2,
      );

  void _resetView() => setState(() {
        _scale = 1.0;
        _pan = _centerPan(1.0);
      });

  void _zoomBy(double factor, Offset focal) {
    final double newScale = (_scale * factor).clamp(_minScale, _maxScale);
    final Offset pan = _pan ?? _centerPan(_scale);
    setState(() {
      // Keep the point under [focal] fixed while scaling.
      _pan = focal - (focal - pan) * (newScale / _scale);
      _scale = newScale;
    });
  }

  void _onDown(Offset local) {
    final CropBox b = _live ?? widget.box;
    final Offset pan = _pan ?? _centerPan(_scale);
    final double sLeft = pan.dx + b.x * _baseW * _scale;
    final double sTop = pan.dy + b.y * _baseH * _scale;
    final double sSide = b.side * _baseW * _scale;
    final Offset corner = Offset(sLeft + sSide, sTop + sSide);
    if ((local - corner).distance <= 28) {
      _mode = 3; // resize
    } else if (local.dx >= sLeft &&
        local.dx <= sLeft + sSide &&
        local.dy >= sTop &&
        local.dy <= sTop + sSide) {
      _mode = 2; // move box
    } else {
      _mode = 1; // pan
    }
  }

  @override
  void didUpdateWidget(_ManualCanvas old) {
    super.didUpdateWidget(old);
    // A committed/slider/sprite-switch box arrived — the external value is now
    // authoritative, so drop the transient drag copy.
    if (!identical(old.box, widget.box)) _live = null;
  }

  void _onMove(Offset delta) {
    if (_mode == 1) {
      setState(() => _pan = (_pan ?? _centerPan(_scale)) + delta);
      return;
    }
    final double denomW = _baseW * _scale, denomH = _baseH * _scale;
    if (denomW <= 0 || denomH <= 0) return;
    // Accumulate off the LIVE box (or the current box at drag start) — NOT
    // widget.box, which is intentionally frozen during the drag.
    final CropBox b = _live ?? widget.box;
    CropBox next;
    if (_mode == 2) {
      final double nx =
          (b.x + delta.dx / denomW).clamp(0.0, (1 - b.side).clamp(0.0, 1.0));
      final double maxY = (1 - b.side * widget.aspect).clamp(0.0, 1.0);
      final double ny = (b.y + delta.dy / denomH).clamp(0.0, maxY);
      next = b.copyWith(x: nx, y: ny);
    } else if (_mode == 3) {
      final double ns = (b.side + delta.dx / denomW).clamp(0.05, 1.0);
      final double nx = b.x.clamp(0.0, (1 - ns).clamp(0.0, 1.0));
      final double maxY = (1 - ns * widget.aspect).clamp(0.0, 1.0);
      final double ny = b.y.clamp(0.0, maxY);
      next = b.copyWith(side: ns, x: nx, y: ny);
    } else {
      return;
    }
    setState(() => _live = next); // re-render only the canvas (cheap)
    widget.onChanged(next); // write app state live, but DON'T rebuild the pane
  }

  void _onUp() {
    final bool wasBox = _mode == 2 || _mode == 3;
    _mode = 0;
    if (wasBox) widget.onCommit?.call(); // heavy refresh happens once, here
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        _viewport = Size(c.maxWidth, c.maxHeight);
        double bw = c.maxWidth;
        double bh = bw / widget.aspect;
        if (bh > c.maxHeight) {
          bh = c.maxHeight;
          bw = bh * widget.aspect;
        }
        _baseW = bw;
        _baseH = bh;
        _pan ??= _centerPan(_scale);
        final Offset pan = _pan!;
        final CropBox box = _live ?? widget.box; // show the live drag if any
        final double dispW = bw * _scale, dispH = bh * _scale;
        final double boxLeft = box.x * dispW,
            boxTop = box.y * dispH,
            boxSide = box.side * dispW;
        return Listener(
          onPointerSignal: (PointerSignalEvent e) {
            if (e is PointerScrollEvent) {
              _zoomBy(e.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12, e.localPosition);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (DragDownDetails d) => _onDown(d.localPosition),
            onPanUpdate: (DragUpdateDetails d) => _onMove(d.delta),
            onPanEnd: (_) => _onUp(),
            onPanCancel: _onUp,
            child: ClipRect(
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: pan.dx,
                    top: pan.dy,
                    width: dispW,
                    height: dispH,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: CheckerImage(
                              bytes: widget.bytes, fit: BoxFit.fill),
                        ),
                        Positioned(
                          left: boxLeft,
                          top: boxTop,
                          width: boxSide,
                          height: boxSide,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0x22FF4081),
                              border: Border.all(
                                  color: const Color(0xFFFF4081), width: 2),
                            ),
                          ),
                        ),
                        Positioned(
                          left: boxLeft + boxSide - 11,
                          top: boxTop + boxSide - 11,
                          width: 22,
                          height: 22,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xFFFF4081),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.open_in_full_rounded,
                                size: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(right: 8, bottom: 8, child: _zoomControls()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _zoomControls() {
    final Offset center = Offset(_viewport.width / 2, _viewport.height / 2);
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('${(_scale * 100).round()}%',
              style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 4),
        btn(Icons.remove_rounded, 'Zoom out', () => _zoomBy(1 / 1.2, center)),
        btn(Icons.add_rounded, 'Zoom in', () => _zoomBy(1.2, center)),
        btn(Icons.fit_screen_rounded, 'Reset view', _resetView),
      ],
    );
  }
}
