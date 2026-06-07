import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../animation/anim_clip.dart';
import '../animation/anim_engine.dart';
import '../animation/jiggle.dart';
import '../animation/lipsync.dart';
import '../core/ao_constants.dart';
import '../core/character.dart';
import '../core/emote.dart';
import '../core/history.dart';
import '../core/validator.dart';
import '../discovery/bulk_folders.dart';
import '../discovery/bulk_rename.dart';
import '../discovery/character_builder.dart';
import '../discovery/ini_repair.dart';
import '../discovery/organizer.dart';
import '../discovery/sprite_scanner.dart';
import '../imaging/bulk_processor.dart';
import '../imaging/button_maker.dart';
import '../imaging/codecs.dart';
import '../imaging/color_matrix.dart';
import '../imaging/color_ops.dart';
import '../imaging/overlay_presets.dart';
import '../imaging/parallel.dart';
import '../imaging/sprite_edit.dart';
import '../imaging/sprite_sheet.dart';
import '../imaging/webp_codec.dart';
import '../platform/cpu.dart';
import '../platform/error_log.dart';
import '../platform/folder_export.dart';
import '../platform/save_file.dart';
import '../platform/settings_store.dart';
import '../platform/workspace.dart';
import '../theme/ao2_theme.dart';
import '../theme/theme_randomizer.dart';

/// A file handed to the app by a picker (name + bytes), platform-neutral.
class PickedFile {
  PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// A second sprite folder loaded **only** to graft parts from in the Mixer
/// (e.g. another character whose head you want on your project's body). It is
/// scanned into [SpriteGroup]s but deliberately kept out of the project [scan]
/// and the export, so loading it never disturbs the character you're building.
class MixSource {
  MixSource(this.label, this.groups);

  /// Display name (the folder's name, or `parts N`).
  final String label;

  /// Classified sprite groups from the folder.
  final List<SpriteGroup> groups;

  /// Base names available to snip from, in scan order.
  List<String> get bases => groups.map((SpriteGroup g) => g.base).toList();
}

/// An optional overlay image (a border/frame to lay over a button or icon, or a
/// background to sit behind the sprite). Holds the raw [bytes] (for a UI
/// thumbnail) and the decoded [image] (for compositing). Empty when unset.
class OverlaySlot {
  Uint8List? bytes;
  img.Image? image;

  /// The editable spec this overlay came from (a preset or the in-app builder),
  /// or null if it was an imported PNG. Lets "Build…" re-open and tweak it.
  OverlaySpec? spec;

  /// Bumped whenever this slot's art changes. Per-sprite button thumbnails fold
  /// the relevant slot's [rev] into their reload key, so changing **one**
  /// sprite's overlay re-renders only that one thumbnail (not all visible ones).
  int rev = 0;

  bool get isSet => image != null;

  /// Replace this slot's art (decoding [bytes] with [ext]); null clears it.
  void set(Uint8List? bytes, {String ext = 'png', OverlaySpec? spec}) {
    this.bytes = bytes;
    image = bytes == null ? null : Codecs.decodeFirstFrame(bytes, ext: ext);
    this.spec = bytes == null ? null : spec;
    rev++;
  }

  /// Copy [other]'s art into this slot (shares the decoded image — overlays are
  /// read-only when composited, so sharing is safe and cheap).
  void copyFrom(OverlaySlot? other) {
    bytes = other?.bytes;
    image = other?.image;
    spec = other?.spec;
    rev++;
  }
}

/// The single source of UI truth. Holds the working project (an in-memory
/// workspace so behaviour is identical on every platform), the parsed/auto-built
/// [Character], undo/redo, the live colour pipeline, and all the actions the
/// screens trigger.
class AppState extends ChangeNotifier {
  AppState() {
    // Restore rebindable keys saved in a previous session (best-effort; the
    // defaults are already in place if there's nothing to load).
    _loadPersistedSettings();
  }

  final MemoryWorkspace workspace = MemoryWorkspace();
  final EditHistory history = EditHistory();
  final SpriteScanner _scanner = const SpriteScanner();

  ScanResult? scan;
  Character? character;
  BuildConfig buildConfig = const BuildConfig();

  int selectedEmote = -1;
  String status = 'Import a folder of sprites to begin.';
  bool busy = false;

  /// The live colour-op pipeline edited in the Colour Lab.
  final List<ColorOp> livePipeline = <ColorOp>[];

  /// Decoded first-frame cache (rel -> image) to keep previews snappy.
  final Map<String, img.Image?> _decodeCache = <String, img.Image?>{};

  /// A **downscaled** (≤640px) first-frame cache used only for rendering the
  /// on-screen button **previews + list thumbnails** — cropping/resizing a small
  /// image instead of a full-res sprite makes a manual-crop drag commit + the
  /// 100+ list thumbnails an order of magnitude cheaper. The export path decodes
  /// full-res separately, so output quality is unaffected.
  final Map<String, img.Image?> _buttonSrcCache = <String, img.Image?>{};

  /// Encoded plain-sprite preview cache (`rel@maxEdge` -> PNG). Lets the Emotes
  /// screen show a sprite without re-decoding/re-encoding on every rebuild — so
  /// typing in a field never re-bakes the preview.
  final Map<String, Uint8List?> _previewCache = <String, Uint8List?>{};

  /// Memoised auto head-square (per sprite `rel`, as resolution-independent
  /// fractions). The silhouette scan is a per-pixel hotspot during rapid framing
  /// navigation / mouth seeding; cleared with the other caches on edit/reset.
  final Map<String, CropBox> _headSquareCache = <String, CropBox>{};

  /// Bumps whenever sprite *pixels/paths* change (recolour, edit, convert,
  /// rename, new composite…). UI previews watch this to know when to reload,
  /// without rebuilding on unrelated changes like typing an emote name.
  int spriteRevision = 0;

  // ---- Performance ("advanced" capabilities) --------------------------------

  /// Spread heavy bulk baking (animate-all, mouth-all, recolour-all, convert)
  /// across all CPU cores. When off, work is done one job at a time (the old
  /// behaviour) — useful if you want to keep the machine free for other apps.
  bool useAllCores = true;

  /// Logical CPU cores detected on this device.
  int get cpuCores => cpuCount;

  /// Whether we're on a memory-constrained mobile OS (Android/iOS), where each
  /// extra render isolate holds a full-res multi-frame clip in RAM.
  bool get isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// How many render/encode jobs to keep in flight during bulk operations.
  /// Capped so we never spawn an unreasonable number of background isolates
  /// (each `compute` is one isolate); 1 when multi-core is disabled.
  ///
  /// **Mobile is capped hard at 2.** On a phone/tablet, fanning a big bulk job
  /// (e.g. jiggling ~500 ripped sprites) across 8 isolates — each decoding a
  /// sprite and building a full-res multi-frame WebP clip — exhausts RAM and the
  /// OS **OOM-kills the app** (looks like "it crashed"), while saturating every
  /// core starves the UI isolate ("really bad lag"). Two in flight keeps a huge
  /// bulk run alive and the UI responsive (slower wall-time, but it finishes).
  int get maxConcurrency {
    if (!useAllCores) return 1;
    // Mobile: only ONE render in flight. Each isolate holds a full-res
    // multi-frame clip; even two at once OOM-killed the app on a tablet during a
    // big bulk job. Desktop keeps the multi-core speed-up.
    return isMobile ? 1 : cpuCount.clamp(1, 8);
  }

  /// Big bulk bakes are processed this many sprites **at a time**, freeing each
  /// batch before the next so peak memory doesn't grow with the cast size. This
  /// is the fix for the OOM crash on mobile that capped a big bulk jiggle around
  /// ~70 sprites (it had held every source byte and every encoded clip at once).
  /// Small on phones/tablets, larger on desktop.
  int get _bulkChunk => isMobile ? 16 : 100;

  /// Toggle multi-core baking.
  void setUseAllCores(bool v) {
    useAllCores = v;
    notifyListeners();
  }

  /// The GPU-preview colour matrix for [pipeline], or `null` when it isn't an
  /// exact linear transform (the UI then uses the CPU preview). See
  /// [ColorMatrix]. Exposed here so screens don't reach into `imaging/` directly.
  List<double>? liveColorMatrix(List<ColorOp> pipeline) =>
      ColorMatrix.tryBuild(pipeline);

  // ---- Button & char-icon generation settings (drive the export + studio) ----
  // Public so the Button Studio can tune them with zero rebuild overhead; the
  // export (`buildOutput`) reads them on demand.

  /// Generate `emotions/buttonN_off.png` for every emote on export.
  bool generateButtons = true;
  int buttonSize = CharFolder.defaultButtonSize;

  /// Button framing — **head/face by default** (AO buttons show expressions).
  CropFraming buttonFraming = CropFraming.defaultValue;
  double buttonZoom = 1.0;

  /// Generate `char_icon.png` for the character-select screen on export.
  bool generateCharIcon = true;
  int iconSize = CharFolder.defaultIconSize; // 40 by default (customisable 40–128)
  CropFraming iconFraming = CropFraming.defaultValue;
  double iconZoom = 1.0;

  /// Which emote (0-based) the char_icon is rendered from.
  int iconSourceEmote = 0;

  /// Nudge the crop square (fractions of its side, −0.5..0.5) so you can
  /// re-centre the framed face/body on a button or the icon.
  double buttonOffsetX = 0;
  double buttonOffsetY = 0;
  double iconOffsetX = 0;
  double iconOffsetY = 0;

  /// Manual crop boxes (KFO/DRO-style "drag a box on the sprite") used when the
  /// framing is [CropFraming.manual]. Buttons keep **one box per sprite** in
  /// [buttonCrops] (keyed by the emote's `sprite` base name) so different poses
  /// can each be framed by hand; a sprite with no entry auto-frames its own head
  /// (see [ButtonMaker.renderFramed]'s manual fallback), so you only customise
  /// the sprites you care about. The char_icon keeps its own single [iconCrop].
  /// All are seeded from the auto head-square on first switch.
  final Map<String, CropBox> buttonCrops = <String, CropBox>{};
  CropBox iconCrop = CropBox.initial;

  /// The stored manual box for [spriteBase], or null when that sprite hasn't
  /// been customised (the renderer then auto-frames its head — untouched sprites
  /// still get a good button without visiting all of them).
  CropBox? buttonCropRaw(String? spriteBase) =>
      (spriteBase == null || spriteBase.isEmpty) ? null : buttonCrops[spriteBase];

  /// The manual box for [spriteBase] to **edit/draw** — the stored box, or
  /// [CropBox.initial] as a neutral placeholder until [ensureButtonCropSeeded]
  /// fills in a real per-sprite head-square.
  CropBox buttonCropFor(String? spriteBase) =>
      buttonCropRaw(spriteBase) ?? CropBox.initial;

  /// Store [box] as [spriteBase]'s manual crop (the studio mutates this directly
  /// for lag-free dragging, then reschedules its own preview).
  void setButtonCrop(String? spriteBase, CropBox box) {
    if (spriteBase == null || spriteBase.isEmpty) return;
    buttonCrops[spriteBase] = box;
  }

  /// Seed [e]'s sprite with a manual box derived from its **own** auto
  /// head-square the first time it's shown in Manual mode, so every sprite
  /// starts at its detected face. No-op if it already has a box or no sprite.
  /// Returns true if it seeded (the caller should refresh).
  Future<bool> ensureButtonCropSeeded(Emote? e) async {
    if (e == null || e.sprite.isEmpty || buttonCrops.containsKey(e.sprite)) {
      return false;
    }
    buttonCrops[e.sprite] = await headCropFor(e);
    return true;
  }

  /// Seed [to]'s manual box when you **arrive** on it while framing. If [to]
  /// already has a custom box it's kept untouched. Otherwise, when [carryFrom]
  /// is given (you advanced *forward* from another sprite), [to] **inherits that
  /// framing** — so "make it & next" keeps the box you just set instead of
  /// snapping back to this sprite's own auto-detected face (the "it resets when
  /// I press Enter" complaint). With no [carryFrom] (going back / a fresh entry)
  /// it falls back to [to]'s own head-square.
  Future<void> arriveButtonCrop(Emote? to, {CropBox? carryFrom}) async {
    if (to == null || to.sprite.isEmpty) return;
    if (buttonCrops.containsKey(to.sprite)) return; // keep its own box
    buttonCrops[to.sprite] = carryFrom ?? await headCropFor(to);
  }

  /// Select emote [target] for **button framing**, carrying the current box
  /// forward when stepping to a later (un-framed) sprite. The single source of
  /// truth for framing navigation — the inline studio AND the big framing editor
  /// both call this so prev/next/Enter behave identically (no divergent copies).
  Future<void> navigateButtonFraming(int target) async {
    final int n = character?.emotes.length ?? 0;
    if (n == 0) return;
    final int t = target.clamp(0, n - 1);
    final Emote? from = current;
    final CropBox? carry = (t > selectedEmote &&
            from != null &&
            from.sprite.isNotEmpty)
        ? buttonCropRaw(from.sprite)
        : null;
    selectEmote(t); // notifies
    await arriveButtonCrop(current, carryFrom: carry);
    notifyListeners(); // surface the seeded/carried box
  }

  /// Re-seed [e]'s sprite box from its auto head-square — the Manual "reset this
  /// sprite to auto" action.
  Future<void> resetButtonCropFor(Emote? e) async {
    if (e == null || e.sprite.isEmpty) return;
    buttonCrops[e.sprite] = await headCropFor(e);
  }

  /// Copy [box] onto every emote's sprite — the Manual "apply this box to all
  /// sprites" action (handy when many poses share a framing).
  void applyButtonCropToAll(CropBox box) {
    for (final Emote e in character?.emotes ?? const <Emote>[]) {
      if (e.sprite.isNotEmpty) buttonCrops[e.sprite] = box;
    }
  }

  /// (customised, total) count of distinct non-empty sprite bases — the
  /// Manual-mode "k of N customised" caption.
  (int, int) get buttonCropCoverage {
    final Set<String> bases = <String>{
      for (final Emote e in character?.emotes ?? const <Emote>[])
        if (e.sprite.isNotEmpty) e.sprite,
    };
    return (bases.where(buttonCrops.containsKey).length, bases.length);
  }

  /// Optional art composited into a button: the **background** sits behind the
  /// sprite, the **border/frame** is laid on top (KFO-style). **Per sprite by
  /// default** — putting a border on one button only affects that sprite, so
  /// different poses can wear different frames (mirrors [buttonCrops]); the
  /// "Apply to all sprites" action copies one onto the whole cast. Keyed by the
  /// emote's `sprite` base name. The char_icon keeps its own single
  /// [iconBg]/[iconFg].
  final Map<String, OverlaySlot> buttonFgBySprite = <String, OverlaySlot>{};
  final Map<String, OverlaySlot> buttonBgBySprite = <String, OverlaySlot>{};
  final OverlaySlot iconBg = OverlaySlot();
  final OverlaySlot iconFg = OverlaySlot();

  /// The stored button overlay for [base] (`fg` = border on top, else
  /// background), or null when that sprite has none. The renderer treats null as
  /// "no overlay" — so an untouched sprite simply gets a plain button.
  OverlaySlot? buttonOverlay(String? base, {required bool fg}) =>
      (base == null || base.isEmpty)
          ? null
          : (fg ? buttonFgBySprite : buttonBgBySprite)[base];

  /// The decoded button overlay image for [base], or null.
  img.Image? buttonOverlayImage(String? base, {required bool fg}) =>
      buttonOverlay(base, fg: fg)?.image;

  /// The button overlay slot for [base] to **edit** — created (and stored) on
  /// first access so the controls always have something to mutate.
  OverlaySlot buttonOverlaySlotFor(String? base, {required bool fg}) {
    final String key = (base == null || base.isEmpty) ? '__none__' : base;
    return (fg ? buttonFgBySprite : buttonBgBySprite)
        .putIfAbsent(key, OverlaySlot.new);
  }

  /// Set (or clear, with null [bytes]) the button overlay for sprite [base].
  /// Pass [spec] when the art came from a preset/builder (so "Build…" can
  /// re-open it); it's cleared for imported PNGs.
  void setButtonOverlay(String? base, Uint8List? bytes,
      {required bool fg, String ext = 'png', OverlaySpec? spec}) {
    if (base == null || base.isEmpty) return;
    buttonOverlaySlotFor(base, fg: fg).set(bytes, ext: ext, spec: spec);
    notifyListeners();
  }

  /// Copy sprite [fromBase]'s button overlay onto **every** sprite — the
  /// "Apply this border to all sprites" action.
  void applyButtonOverlayToAll(String? fromBase, {required bool fg}) {
    final OverlaySlot? src = buttonOverlay(fromBase, fg: fg);
    for (final Emote e in character?.emotes ?? const <Emote>[]) {
      if (e.sprite.isEmpty) continue;
      buttonOverlaySlotFor(e.sprite, fg: fg).copyFrom(src);
    }
    notifyListeners();
  }

  /// (customised, total) count of distinct sprite bases that have a button
  /// overlay (border or background) — for the studio's caption.
  (int, int) get buttonOverlayCoverage {
    final Set<String> bases = <String>{
      for (final Emote e in character?.emotes ?? const <Emote>[])
        if (e.sprite.isNotEmpty) e.sprite,
    };
    int n = 0;
    for (final String b in bases) {
      if (buttonOverlay(b, fg: true)?.isSet == true ||
          buttonOverlay(b, fg: false)?.isSet == true) {
        n++;
      }
    }
    return (n, bases.length);
  }

  /// Load (or clear, with null [bytes]) the **char_icon** overlay [slot]. [ext]
  /// helps decode. Pass [spec] when the art came from a preset/builder.
  void setOverlay(OverlaySlot slot, Uint8List? bytes,
      {String ext = 'png', OverlaySpec? spec}) {
    slot.set(bytes, ext: ext, spec: spec);
    notifyListeners();
  }

  /// User-saved overlay presets (built in the Button Studio's "Build…" editor,
  /// then **Saved**). They show up alongside the built-ins in the preset picker
  /// and **persist across sessions** (via `settings_store`, same file as the
  /// keybinds). Only the editable [OverlaySpec] is stored — it rebuilds to a
  /// crisp image at any size.
  final List<({String name, OverlaySpec spec})> userOverlayPresets =
      <({String name, OverlaySpec spec})>[];

  /// User presets whose kind (border / background) matches [kind].
  List<({String name, OverlaySpec spec})> userOverlaysFor(OverlayKind kind) =>
      userOverlayPresets
          .where((({String name, OverlaySpec spec}) p) => p.spec.kind == kind)
          .toList();

  /// Save [spec] as a named user preset (replacing any with the same [name]).
  void saveOverlayPreset(String name, OverlaySpec spec) {
    final String clean = name.trim();
    if (clean.isEmpty) return;
    userOverlayPresets
        .removeWhere((({String name, OverlaySpec spec}) p) => p.name == clean);
    userOverlayPresets.add((name: clean, spec: spec.copy()));
    _persistSettings();
    notifyListeners();
  }

  /// Delete the user preset named [name].
  void deleteOverlayPreset(String name) {
    userOverlayPresets
        .removeWhere((({String name, OverlaySpec spec}) p) => p.name == name);
    _persistSettings();
    notifyListeners();
  }

  /// Push the latest button/icon settings (the UI mutates fields directly for a
  /// lag-free studio); call this when something else needs to react.
  void notifyButtonSettings() => notifyListeners();

  /// Extra sprite folders loaded just for the Mixer (the "parts" you graft on).
  /// Stored separately so they never pollute the project or its export.
  final List<MixSource> mixSources = <MixSource>[];

  /// Workspace path namespace for [mixSources] files — filtered out of every
  /// project scan via [_projectFiles].
  static const String _mixPrefix = '__mixparts';

  bool get hasProject => character != null;

  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  List<LintIssue> get issues => character == null
      ? const <LintIssue>[]
      : CharacterValidator.validate(character!, scan: scan);

  // ---------------------------------------------------------------------------
  // Importing
  // ---------------------------------------------------------------------------

  /// Import [files] as a **fresh** project: the previous project is cleared
  /// first, so "Import" truly starts over (use [addSprites] to *grow* the
  /// current character instead — the old code accumulated onto the previous
  /// import). When [projectName] is given (the picked folder's name) the
  /// auto-built character is named after it instead of the generic "newchar".
  Future<void> importFiles(List<PickedFile> files, {String? projectName}) async {
    _setBusy(true, 'Importing ${files.length} files…');
    await logCrash('importFiles start: ${files.length} file(s)');
    _clearWorkspaceFiles();
    for (final PickedFile f in files) {
      workspace.put(f.name, f.bytes);
    }
    final String? clean = _cleanProjectName(projectName);
    if (clean != null) buildConfig = _buildConfigNamed(clean);
    await _rebuild();
    _setBusy(false, 'Imported ${files.length} files.');
  }

  /// Drop the working project's files + mixer parts (shared by a fresh
  /// [importFiles] and [resetProject]).
  void _clearWorkspaceFiles() {
    workspace.clear();
    mixSources.clear();
    buttonCrops.clear();
    buttonFgBySprite.clear();
    buttonBgBySprite.clear();
    _headSquareCache.clear();
    _decodeCache.clear();
    _buttonSrcCache.clear();
    _previewCache.clear();
    _thumbCache.clear();
  }

  /// Sanitise a picked folder name into a usable character/folder name, or null
  /// if there's nothing usable.
  String? _cleanProjectName(String? raw) {
    if (raw == null) return null;
    final String s =
        raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
    return s.isEmpty ? null : s;
  }

  /// **Start over**: wipe the entire project (sprites, character, history,
  /// previews, mixer parts) back to a clean slate. Studio/build *settings* are
  /// kept — only project data is cleared.
  void resetProject() {
    workspace.clear();
    mixSources.clear();
    buttonCrops.clear();
    buttonFgBySprite.clear();
    buttonBgBySprite.clear();
    history.clear();
    character = null;
    scan = null;
    selectedEmote = -1;
    livePipeline.clear();
    ripperSheetBytes = null;
    _invalidateImageCaches();
    _setBusy(false, 'Project reset — import sprites to begin.');
  }

  /// Pull every file from an external workspace (e.g. a real directory) into the
  /// in-memory project.
  Future<void> importWorkspace(Workspace external) async {
    _setBusy(true, 'Importing folder…');
    final List<String> files = await external.listFiles();
    for (final String rel in files) {
      workspace.put(rel, await external.readBytes(rel));
    }
    await _rebuild();
    _setBusy(false, 'Imported ${files.length} files.');
  }

  /// **Add sprites to the current character** without losing your work. Drops
  /// [files] into the project, rescans, and appends an emote for every *new*
  /// sprite group (one not already referenced by an existing emote) — keeping
  /// the existing `char.ini`, emotes and edits intact. This is "update an
  /// existing character / add more sprites": grow a character you already
  /// imported (e.g. drop in a few new expressions) instead of rebuilding from
  /// scratch. With no project loaded yet it behaves like [importFiles]. Returns
  /// the number of new emotes added.
  Future<int> addSprites(List<PickedFile> files) async {
    if (files.isEmpty) return 0;
    if (character == null) {
      await importFiles(files);
      return character?.emotes.length ?? 0;
    }
    _setBusy(true, 'Adding ${files.length} sprite file(s)…');
    await logCrash('addSprites start: ${files.length} file(s)');
    for (final PickedFile f in files) {
      workspace.put(f.name, f.bytes);
    }
    _invalidateImageCaches();
    scan = _scanner.fromPaths(await _projectFiles());

    final Set<String> known = character!.spriteReferences();
    int added = 0;
    for (final SpriteGroup g in scan!.groups) {
      if (g.base.isEmpty || known.contains(g.base)) continue;
      character!.emotes.add(Emote(
        comment: g.suggestedComment,
        sprite: g.base,
        deskMod: DeskModifier.show,
      ));
      known.add(g.base);
      added++;
    }
    if (added > 0) {
      selectedEmote = character!.emotes.length - 1;
      history.push(character!);
    }
    _setBusy(
        false,
        added > 0
            ? 'Added $added new emote(s) from new sprites.'
            : 'Imported sprites — no new emotes (all already referenced).');
    return added;
  }

  /// **Repair every char.ini in a picked folder** (and its subfolders): find
  /// each `char.ini`, scan its sibling sprites, and rebuild its emote list from
  /// what's actually on disk — drop emotes whose sprite is gone, add an emote for
  /// every sprite that has none, keep the `[Options]`/shouts intact. The repaired
  /// inis download as a `.zip` (each at its original relative path). The project
  /// you have open is **untouched**. Returns a human summary.
  Future<String> repairInisInFolder(List<PickedFile> files) async {
    _setBusy(true, 'Scanning for char.ini files…');
    await logCrash('repairInis start: ${files.length} file(s)');
    final Map<String, Uint8List> byPath = <String, Uint8List>{
      for (final PickedFile f in files) Workspace.norm(f.name): f.bytes,
    };
    final List<RepairTarget> targets = IniRepair.findCharFolders(byPath.keys);
    if (targets.isEmpty) {
      _setBusy(false, 'No char.ini found in that folder.');
      return 'No char.ini found in that folder.';
    }
    final Archive archive = Archive();
    int changed = 0, addedTotal = 0, droppedTotal = 0;
    for (int i = 0; i < targets.length; i++) {
      final RepairTarget t = targets[i];
      final Uint8List? iniBytes = byPath[t.iniPath];
      if (iniBytes == null) continue;
      final String iniText = utf8.decode(iniBytes, allowMalformed: true);
      final ({String ini, IniRepairReport report}) res =
          IniRepair.repairText(iniText, t.spriteRelPaths);
      final List<int> outBytes = utf8.encode(res.ini);
      archive.addFile(ArchiveFile(t.iniPath, outBytes.length, outBytes));
      if (res.report.changed) changed++;
      addedTotal += res.report.added;
      droppedTotal += res.report.dropped;
      _progress(i + 1, targets.length, 'Repair inis');
    }
    final List<int>? zip = ZipEncoder().encode(archive);
    if (zip != null) {
      await saveBytes('repaired_inis.zip', Uint8List.fromList(zip));
    }
    final String summary = 'Repaired ${targets.length} char.ini '
        '($changed changed; +$addedTotal emote(s), −$droppedTotal dangling). '
        'Saved repaired_inis.zip.';
    await logCrash('repairInis done: $summary');
    _setBusy(false, summary);
    return summary;
  }

  /// Workspace files that belong to the project (everything except the Mixer's
  /// loaded "parts" folders, which live under [_mixPrefix]).
  Future<List<String>> _projectFiles() async => <String>[
        for (final String f in await workspace.listFiles())
          if (!f.startsWith('$_mixPrefix/')) f,
      ];

  /// Sound names the Emotes-tab **sound picker** offers for the `[SoundN]`
  /// field: names already used by other emotes, the built-in sfx guesses, and
  /// any audio files bundled with the imported character (offered by *base*
  /// name, since AO references a sound without its extension). Sorted,
  /// de-duplicated, and free of the "no sound" sentinels. This is only a list of
  /// suggestions — the field still lets you type any name you like.
  Future<List<String>> availableSoundNames() async {
    final Set<String> names = <String>{};
    for (final Emote e in character?.emotes ?? const <Emote>[]) {
      if (e.hasMeaningfulSound && e.soundName != null) names.add(e.soundName!);
    }
    names.addAll(soundGuessNames());
    for (final String rel in await _projectFiles()) {
      final String ext = p.extension(rel).replaceFirst('.', '').toLowerCase();
      if (kAudioExtensions.contains(ext)) {
        names.add(p.basenameWithoutExtension(rel));
      }
    }
    names.removeWhere((String s) => s.trim().isEmpty);
    final List<String> out = names.toList()..sort();
    return out;
  }

  Future<void> _rebuild() async {
    _invalidateImageCaches();
    final List<String> files = await _projectFiles();
    scan = _scanner.fromPaths(files);

    // If an existing char.ini is present, honour it; otherwise auto-build.
    final String? iniRel = files.firstWhereOrNull(
        (String f) => p.basename(f).toLowerCase() == CharFolder.iniName);
    if (iniRel != null) {
      character = Character.parse(await workspace.readString(iniRel));
      status = 'Loaded existing ${CharFolder.iniName} '
          '(${character!.emotes.length} emotes).';
    } else {
      character = const CharacterBuilder().build(scan!, config: buildConfig);
      status = 'Auto-built ${character!.emotes.length} emotes from sprites.';
    }
    history.seed(character!);
    selectedEmote = character!.emotes.isEmpty ? -1 : 0;
  }

  void updateBuildConfig(BuildConfig c) {
    buildConfig = c;
    notifyListeners();
  }

  /// Re-run the auto-builder with the current [buildConfig] (discards manual
  /// emote edits — used from the "regenerate" action).
  Future<void> regenerate() async {
    if (scan == null) return;
    character = const CharacterBuilder().build(scan!, config: buildConfig);
    history.seed(character!);
    selectedEmote = character!.emotes.isEmpty ? -1 : 0;
    status = 'Regenerated ${character!.emotes.length} emotes.';
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Editing
  // ---------------------------------------------------------------------------

  Emote? get current =>
      (character != null && selectedEmote >= 0 && selectedEmote < character!.emotes.length)
          ? character!.emotes[selectedEmote]
          : null;

  void selectEmote(int index) {
    selectedEmote = index;
    notifyListeners();
  }

  /// Notify listeners without recording an undo step (live typing).
  void touch() => notifyListeners();

  void commitEdit() {
    if (character != null) history.push(character!);
    notifyListeners();
  }

  void addEmote() {
    if (character == null) return;
    character!.emotes.add(Emote(comment: 'New', deskMod: DeskModifier.show));
    selectedEmote = character!.emotes.length - 1;
    commitEdit();
  }

  void deleteEmote(int index) {
    if (character == null || index < 0 || index >= character!.emotes.length) return;
    character!.emotes.removeAt(index);
    selectedEmote = character!.emotes.isEmpty
        ? -1
        : index.clamp(0, character!.emotes.length - 1);
    commitEdit();
  }

  /// Delete several emotes at once (multi-select). Removes high index → low so
  /// earlier removals don't shift the rest; records a single undo step.
  void deleteEmotes(Set<int> indices) {
    if (character == null || indices.isEmpty) return;
    final List<int> sorted = indices.toList()
      ..sort((int a, int b) => b.compareTo(a));
    for (final int i in sorted) {
      if (i >= 0 && i < character!.emotes.length) {
        character!.emotes.removeAt(i);
      }
    }
    selectedEmote = character!.emotes.isEmpty
        ? -1
        : selectedEmote.clamp(0, character!.emotes.length - 1);
    commitEdit();
  }

  void moveEmote(int from, int to) {
    if (character == null) return;
    final List<Emote> e = character!.emotes;
    if (from < 0 || from >= e.length || to < 0 || to >= e.length) return;
    e.insert(to, e.removeAt(from));
    selectedEmote = to;
    commitEdit();
  }

  /// Reorder a **multi-selection** as one contiguous block: move every emote in
  /// [selected] (keeping their relative order) so the block lands at [newIndex]
  /// (a `ReorderableListView` raw drop index, 0..length). Returns the new index
  /// of the first moved emote, or -1 if it didn't move (needs ≥2 selected). This
  /// is what lets you drag several ticked emotes together instead of one at a
  /// time.
  int moveEmotes(Set<int> selected, int newIndex) {
    if (character == null) return -1;
    final List<Emote> e = character!.emotes;
    final List<int> sorted =
        selected.where((int i) => i >= 0 && i < e.length).toList()..sort();
    if (sorted.isEmpty) return -1;
    final List<Emote> moved = <Emote>[for (final int i in sorted) e[i]];
    // Selected items before the drop point shift the insertion left once removed.
    final int selBefore = sorted.where((int i) => i < newIndex).length;
    for (final int i in sorted.reversed) {
      e.removeAt(i);
    }
    final int insertAt = (newIndex - selBefore).clamp(0, e.length);
    e.insertAll(insertAt, moved);
    selectedEmote = insertAt;
    commitEdit();
    return insertAt;
  }

  /// Move the [selected] emotes (as a block, keeping order) so the block's first
  /// emote lands at **exactly** [finalIndex] (0-based) in the resulting list —
  /// the "move to position N" action (e.g. the middle, or a few down), unlike the
  /// drag's raw-drop semantics. Returns the block's new start index, or -1.
  int moveEmotesToIndex(Set<int> selected, int finalIndex) {
    if (character == null) return -1;
    final List<Emote> e = character!.emotes;
    final List<int> sorted =
        selected.where((int i) => i >= 0 && i < e.length).toList()..sort();
    if (sorted.isEmpty) return -1;
    final List<Emote> moved = <Emote>[for (final int i in sorted) e[i]];
    for (final int i in sorted.reversed) {
      e.removeAt(i);
    }
    final int insertAt = finalIndex.clamp(0, e.length);
    e.insertAll(insertAt, moved);
    selectedEmote = insertAt;
    commitEdit();
    return insertAt;
  }

  void undo() {
    final Character? c = history.undo();
    if (c != null) {
      character = c;
      selectedEmote = selectedEmote.clamp(-1, c.emotes.length - 1);
      notifyListeners();
    }
  }

  void redo() {
    final Character? c = history.redo();
    if (c != null) {
      character = c;
      selectedEmote = selectedEmote.clamp(-1, c.emotes.length - 1);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Sprite resolution + previews
  // ---------------------------------------------------------------------------

  /// The representative sprite file (rel path) for an emote, if discovered.
  String? spriteRelFor(Emote e) {
    final SpriteGroup? g =
        scan?.groups.firstWhereOrNull((SpriteGroup g) => g.base == e.sprite);
    return g?.representative?.relPath;
  }

  Future<img.Image?> decodeFirstFrame(String rel) async {
    if (_decodeCache.containsKey(rel)) return _decodeCache[rel];
    img.Image? image;
    if (await workspace.exists(rel)) {
      final Uint8List bytes = await workspace.readBytes(rel);
      image = Codecs.decodeFirstFrame(bytes, ext: p.extension(rel).replaceFirst('.', ''));
    }
    _decodeCache[rel] = image;
    return image;
  }

  /// First frame of [rel] **downscaled to ≤640px** (cached) for rendering button
  /// previews/thumbnails fast. Falls back to the full frame if it's already
  /// small. Not for export (that path uses the full-res decode).
  Future<img.Image?> _decodeButtonSource(String rel) async {
    if (_buttonSrcCache.containsKey(rel)) return _buttonSrcCache[rel];
    final img.Image? full = await decodeFirstFrame(rel);
    img.Image? small = full;
    if (full != null) {
      final int longest = full.width > full.height ? full.width : full.height;
      if (longest > 640) {
        final double s = 640 / longest;
        small = img.copyResize(full,
            width: (full.width * s).round(),
            height: (full.height * s).round(),
            interpolation: img.Interpolation.average);
      }
    }
    _buttonSrcCache[rel] = small;
    return small;
  }

  /// PNG bytes of [rel] with [pipeline] applied to a downscaled copy — used for
  /// the real-time Colour Lab preview.
  Future<Uint8List?> previewWithPipeline(String rel, List<ColorOp> pipeline,
      {int maxEdge = 640}) async {
    final img.Image? src = await decodeFirstFrame(rel);
    if (src == null) return null;
    img.Image work = src.clone();
    final int longest = work.width > work.height ? work.width : work.height;
    if (longest > maxEdge) {
      final double s = maxEdge / longest;
      // Use a good downscale filter so the preview isn't pixelated.
      work = img.copyResize(work,
          width: (work.width * s).round(),
          height: (work.height * s).round(),
          interpolation: img.Interpolation.average);
    }
    if (pipeline.isNotEmpty) ImageOps.applyAll(work, pipeline);
    return Codecs.encodePng(work);
  }

  /// Cached PNG preview of a sprite with **no** pipeline — for the Emotes screen.
  /// Memoised per `rel@maxEdge` (cleared on [spriteRevision] changes) so showing
  /// the selected sprite never re-decodes/re-encodes while you type in a field.
  Future<Uint8List?> previewSprite(String rel, {int maxEdge = 1024}) async {
    final String key = '$rel@$maxEdge';
    if (_previewCache.containsKey(key)) return _previewCache[key];
    final Uint8List? bytes =
        await previewWithPipeline(rel, const <ColorOp>[], maxEdge: maxEdge);
    _previewCache[key] = bytes;
    return bytes;
  }

  /// Bulk-rename emote names (and optionally their sprite files) using [spec].
  /// Returns the number of emotes whose name changed.
  Future<int> bulkRename(RenameSpec spec) async {
    if (character == null || spec.isNoop && !spec.renameSprites) return 0;
    _setBusy(true, 'Renaming…');
    int changed = 0;
    bool movedFiles = false;
    for (int i = 0; i < character!.emotes.length; i++) {
      final Emote e = character!.emotes[i];

      if (spec.renameSprites && e.sprite.isNotEmpty && !e.sprite.contains('/')) {
        final String newSprite = _safeSprite(BulkRename.newName(e.sprite, i, spec));
        if (newSprite.isNotEmpty && newSprite != e.sprite) {
          await _renameSpriteFiles(e.sprite, newSprite);
          e.sprite = newSprite;
          movedFiles = true;
        }
      }

      final String newComment = BulkRename.newName(e.comment, i, spec);
      if (newComment != e.comment) {
        e.comment = newComment;
        changed++;
      }
    }
    if (movedFiles) {
      // Refresh sprite groups from the renamed files (keeps edits intact).
      scan = _scanner.fromPaths(await _projectFiles());
      _invalidateImageCaches();
    }
    history.push(character!);
    _setBusy(false, 'Renamed $changed emote(s).');
    return changed;
  }

  String _safeSprite(String s) => s.replaceAll(RegExp(r'[\\/]+'), '_').trim();

  Future<void> _renameSpriteFiles(String oldBase, String newBase) async {
    final SpriteGroup? g =
        scan?.groups.firstWhereOrNull((SpriteGroup g) => g.base == oldBase);
    if (g == null) return;
    final List<SpriteFile> files =
        <SpriteFile?>[g.idle, g.talk, g.post, ...g.statics].whereType<SpriteFile>().toList();
    for (final SpriteFile f in files) {
      final String prefix = switch (f.state) {
        SpriteState.idle => '(a)',
        SpriteState.talk => '(b)',
        SpriteState.post => '(c)',
        SpriteState.staticImage => '',
      };
      final String newRel = '$prefix$newBase.${f.ext}';
      if (newRel != f.relPath && await workspace.exists(f.relPath)) {
        await workspace.move(f.relPath, newRel);
      }
    }
  }

  /// Sprite base names available for mixing/compositing (the project's own).
  List<String> spriteBases() =>
      (scan?.groups ?? <SpriteGroup>[]).map((SpriteGroup g) => g.base).toList();

  String? relForBase(String base) => scan?.groups
      .firstWhereOrNull((SpriteGroup g) => g.base == base)
      ?.representative
      ?.relPath;

  // ---------------------------------------------------------------------------
  // Mixer "parts" sources — load a SECOND folder to graft sprites from
  // ---------------------------------------------------------------------------

  /// Load a folder of sprites as a Mixer "parts" source (e.g. another
  /// character's sprites you want to snip a head/limb from). Scanned for clean
  /// `(a)`/`(b)`/`(c)` grouping but stashed under [_mixPrefix] and excluded from
  /// the project, so dumping a second folder here never touches the character
  /// you're building or its export.
  Future<void> importMixParts(List<PickedFile> files, {String? label}) async {
    if (files.isEmpty) return;
    final String safe = (label == null || label.trim().isEmpty)
        ? 'parts ${mixSources.length + 1}'
        : label.trim().replaceAll('/', '_');
    _setBusy(true, 'Loading "$safe" sprites…');

    // Scan by the files' own names (so (a)/(b)/(c) + bases resolve normally),
    // but store the bytes under the mix namespace.
    final List<String> names = <String>[];
    for (final PickedFile f in files) {
      final String name = Workspace.norm(f.name);
      workspace.put('$_mixPrefix/$safe/$name', f.bytes);
      names.add(name);
    }
    final ScanResult s = _scanner.fromPaths(names);
    mixSources.removeWhere((MixSource m) => m.label == safe);
    if (s.groups.isNotEmpty) mixSources.add(MixSource(safe, s.groups));
    _decodeCache.clear();
    _setBusy(false,
        'Loaded ${s.groups.length} sprite group(s) from "$safe" for mixing.');
  }

  /// Forget a loaded parts source (its files stay in the workspace but are
  /// already excluded from the project; they're harmless dead weight).
  void removeMixSource(String label) {
    mixSources.removeWhere((MixSource m) => m.label == label);
    notifyListeners();
  }

  /// Representative file path for [base] inside the loaded parts [sourceLabel].
  String? relForMixBase(String sourceLabel, String base) {
    final MixSource? m =
        mixSources.firstWhereOrNull((MixSource m) => m.label == sourceLabel);
    final SpriteFile? rep = m?.groups
        .firstWhereOrNull((SpriteGroup g) => g.base == base)
        ?.representative;
    if (m == null || rep == null) return null;
    return Workspace.norm('$_mixPrefix/${m.label}/${rep.relPath}');
  }

  /// Save a freshly composited image as a brand-new static sprite + emote, so
  /// "head-on-body" creations become first-class emotes in the project.
  Future<void> addCompositeSprite(String name, Uint8List png) async {
    final String safe = name.trim().isEmpty ? 'mix' : name.trim();
    final String rel = '$safe.png';
    await workspace.writeBytes(rel, png);
    _invalidateImageCaches();

    // Register it with the scan so previews/buttons resolve it.
    final SpriteGroup group = SpriteGroup(safe)
      ..statics.add(SpriteFile(
        relPath: rel,
        ext: 'png',
        state: SpriteState.staticImage,
        base: safe,
      ));
    scan?.groups.add(group);

    character?.emotes.add(Emote(comment: safe, sprite: safe, deskMod: DeskModifier.show));
    selectedEmote = (character?.emotes.length ?? 1) - 1;
    commitEdit();
    status = 'Added composite sprite "$safe".';
  }

  // ---------------------------------------------------------------------------
  // Crop / trim / background removal
  // ---------------------------------------------------------------------------

  /// The selected sprite's pixel dimensions (first frame), for the Edit screen's
  /// resize fields. Null if no sprite. Uses the decode cache.
  Future<({int w, int h})?> currentSpriteSize() async {
    final Emote? e = current;
    if (e == null) return null;
    final String? rel = spriteRelFor(e);
    if (rel == null) return null;
    final img.Image? im = await decodeFirstFrame(rel);
    if (im == null) return null;
    return (w: im.width, h: im.height);
  }

  /// PNG preview of the selected sprite with [spec] applied (downscaled).
  Future<Uint8List?> previewEdit(String rel, SpriteEditSpec spec,
      {int maxEdge = 640}) async {
    final img.Image? src = await decodeFirstFrame(rel);
    if (src == null) return null;
    img.Image work = src.clone();
    final int longest = work.width > work.height ? work.width : work.height;
    if (longest > maxEdge) {
      final double s = maxEdge / longest;
      work = img.copyResize(work,
          width: (work.width * s).round(),
          height: (work.height * s).round(),
          interpolation: img.Interpolation.average);
    }
    return Codecs.encodePng(SpriteEdit.apply(work, spec));
  }

  /// Bake [spec] (crop / auto-trim / background removal) into the selected
  /// emote's sprite files, or every sprite. All files in an emote group share
  /// one crop rect so (a)/(b) stay aligned.
  Future<int> applyEdit(SpriteEditSpec spec, {required bool allSprites}) async {
    if (scan == null || spec.isNoop) return 0;
    _setBusy(true, 'Editing sprites…');
    final List<SpriteGroup> groups = <SpriteGroup>[];
    if (allSprites) {
      groups.addAll(scan!.groups);
    } else if (current != null) {
      final SpriteGroup? g =
          scan!.groups.firstWhereOrNull((SpriteGroup g) => g.base == current!.sprite);
      if (g != null) groups.add(g);
    }

    int edited = 0;
    for (final SpriteGroup g in groups) {
      final List<SpriteFile> files =
          <SpriteFile?>[g.idle, g.talk, g.post, ...g.statics].whereType<SpriteFile>().toList();
      final Map<String, img.Image> decoded = <String, img.Image>{};
      for (final SpriteFile f in files) {
        if (!await workspace.exists(f.relPath)) continue;
        final img.Image? im = Codecs.decode(await workspace.readBytes(f.relPath), ext: f.ext);
        if (im != null) decoded[f.relPath] = im;
      }
      if (decoded.isEmpty) continue;

      // Remove background first, then compute one shared crop rect.
      for (final img.Image im in decoded.values) {
        SpriteEdit.removeBg(im, spec);
      }
      final IntRect rect = SpriteEdit.computeRect(decoded.values.toList(), spec);

      for (final MapEntry<String, img.Image> e in decoded.entries) {
        img.Image out = SpriteEdit.cropTo(e.value, rect);
        out = SpriteEdit.resize(out, spec.scaleX, spec.scaleY);
        await _writeSpriteInPlace(e.key, out);
        edited++;
      }
      // Keep the UI responsive between (heavy) sprite groups.
      await Future<void>.delayed(Duration.zero);
    }
    _invalidateImageCaches();
    scan = _scanner.fromPaths(await _projectFiles());
    _setBusy(false, 'Edited $edited sprite file(s).');
    return edited;
  }

  /// Re-encode [image] and write it back over the sprite at [rel], preserving
  /// the container format wherever the platform can. Returns the path actually
  /// written — identical to [rel] except when a source format we can't re-encode
  /// here (a WebP without the encoder, or a non-AO format like JPG/BMP) has to be
  /// rewritten as APNG/PNG; in that case the original file is deleted so a file's
  /// bytes and extension never disagree.
  ///
  /// This is what makes "Apply" land on the file the app previews and exports:
  /// the old code routed every WebP sprite (the default format here) through a
  /// fixed `webp → .apng` rename, writing a phantom `.apng` next to the
  /// untouched `.webp` the scan still pointed at — so recolours/edits silently
  /// "did nothing".
  Future<String> _writeSpriteInPlace(String rel, img.Image image) async {
    final String ext = p.extension(rel).replaceFirst('.', '').toLowerCase();
    if (ext == 'webp') {
      final WebpResult r = image.frames.length > 1
          ? await WebpEncoder.instance.encodeAnimation(
              image.frames.toList(),
              image.frames
                  .map((img.Image f) => f.frameDuration <= 0 ? 100 : f.frameDuration)
                  .toList(),
              lossless: true)
          : await WebpEncoder.instance.encode(image, lossless: true);
      if (r.ok && r.bytes != null) {
        await workspace.writeBytes(rel, r.bytes!);
        return rel;
      }
      // WebP encoder unavailable here — fall through to the APNG fallback so the
      // edit still lands (just in a different container).
    }
    final String outExt = ext == 'webp' ? 'apng' : Codecs.outputExtensionFor(ext);
    final String outRel =
        ext == outExt ? rel : '${rel.substring(0, rel.length - ext.length)}$outExt';
    await workspace.writeBytes(outRel, Codecs.encodeForExtension(image, outExt));
    if (outRel != rel) await workspace.delete(rel);
    return outRel;
  }

  // ---------------------------------------------------------------------------
  // Colour pipeline editing
  // ---------------------------------------------------------------------------

  void setLivePipeline(List<ColorOp> ops) {
    livePipeline
      ..clear()
      ..addAll(ops);
    notifyListeners();
  }

  void addLiveOp(ColorOp op) {
    livePipeline.add(op);
    notifyListeners();
  }

  void clearLivePipeline() {
    livePipeline.clear();
    notifyListeners();
  }

  /// Bake the live pipeline into the project's sprites: every file of the
  /// selected emote (so its `(a)`/`(b)`/`(c)` and all animation frames recolour
  /// together) or, when [allSprites] is set, every sprite. Each sprite is
  /// re-encoded **in place** in its original format via [_writeSpriteInPlace]
  /// (WebP stays WebP, falling back to APNG only when the encoder is missing) so
  /// the recolour actually lands on the file the app previews and exports.
  Future<int> applyPipeline({required bool allSprites}) async {
    if (livePipeline.isEmpty || scan == null) return 0;
    _setBusy(true, 'Applying colour pipeline…');

    final List<SpriteGroup> groups = <SpriteGroup>[];
    if (allSprites) {
      groups.addAll(scan!.groups);
    } else if (current != null) {
      final SpriteGroup? g =
          scan!.groups.firstWhereOrNull((SpriteGroup g) => g.base == current!.sprite);
      if (g != null) groups.add(g);
    }

    final List<String> targets = <String>[
      for (final SpriteGroup g in groups)
        for (final SpriteFile f
            in <SpriteFile?>[g.idle, g.talk, g.post, ...g.statics].whereType<SpriteFile>())
          f.relPath,
    ];

    int ok = 0;
    int done = 0;
    for (final String rel in targets) {
      if (await workspace.exists(rel)) {
        final img.Image? im = Codecs.decode(await workspace.readBytes(rel),
            ext: p.extension(rel).replaceFirst('.', ''));
        if (im != null) {
          ImageOps.applyAll(im, livePipeline);
          await _writeSpriteInPlace(rel, im);
          ok++;
        }
      }
      _progress(++done, targets.length, 'Recolour');
      // Yield to the event loop so the progress bar repaints and the UI stays
      // responsive instead of freezing for the whole batch.
      if (done % 3 == 0) await Future<void>.delayed(Duration.zero);
    }

    _invalidateImageCaches();
    // Paths can shift on fallback (webp → apng), so refresh the scan.
    scan = _scanner.fromPaths(await _projectFiles());
    _setBusy(false, 'Recoloured $ok sprite(s).');
    return ok;
  }

  /// Preview the auto-generated **button** for the selected emote at [size] px,
  /// using the current [buttonFraming]/[buttonZoom]. Reuses the decode cache.
  Future<Uint8List?> previewAutoButton(int size) async =>
      previewButtonForEmote(current, size);

  /// The same framed-button render as [previewAutoButton] but for **any** [e]
  /// — so the Button Studio's sprite list can show a tiny preview of the actual
  /// *button*, not the raw sprite. Reuses the decode cache; lazy per visible row.
  Future<Uint8List?> previewButtonForEmote(Emote? e, int size) async {
    if (e == null) return null;
    final String? rel = spriteRelFor(e);
    if (rel == null) return null;
    // Downscaled source: previews/thumbnails never need the full-res sprite, and
    // cropping/resizing a ≤640px image is far cheaper (the export uses full res).
    final img.Image? frame = await _decodeButtonSource(rel);
    if (frame == null) return null;
    return ButtonMaker.renderFramed(frame, size,
        framing: buttonFraming,
        zoom: buttonZoom,
        offsetX: buttonOffsetX,
        offsetY: buttonOffsetY,
        background: buttonOverlayImage(e.sprite, fg: false),
        foreground: buttonOverlayImage(e.sprite, fg: true),
        manualCrop:
            buttonFraming == CropFraming.manual ? buttonCropRaw(e.sprite) : null);
  }

  /// Bumped (debounced by the studio) whenever a button *style* setting changes
  /// — framing mode, size, zoom, offsets, a manual box, or an overlay. Its only
  /// job now is to **notify** so the sprite list rebuilds; which thumbnails
  /// actually re-render is decided per-sprite by [buttonThumbKey] (so editing
  /// one sprite's box no longer re-renders the whole visible list = the freeze).
  int buttonStyleRevision = 0;

  /// Tell the button thumbnails to refresh (after a debounced settings change).
  void bumpButtonStyle() {
    buttonStyleRevision++;
    notifyListeners();
  }

  /// Rendered button-thumbnail cache, keyed by sprite base → (thumbKey, png).
  /// **The fix for scroll lag on a big cast:** the sprite-list `ListView`
  /// recycles rows, so without this each thumbnail re-decodes + re-renders the
  /// framed button every time it scrolls back into view. With it, a re-appearing
  /// row is an instant cache hit; a row only actually renders when ITS framing
  /// inputs change ([buttonThumbKey] mismatches). One entry per sprite (bounded).
  final Map<String, ({int key, Uint8List bytes})> _thumbCache =
      <String, ({int key, Uint8List bytes})>{};

  /// **Synchronous** cache lookup — returns [e]'s thumbnail PNG instantly if it's
  /// current, else null. Lets a recycled list row paint immediately on scroll
  /// with no placeholder flash and no async work.
  Uint8List? cachedButtonThumb(Emote? e) {
    if (e == null) return null;
    final ({int key, Uint8List bytes})? cached = _thumbCache[e.sprite];
    return (cached != null && cached.key == buttonThumbKey(e))
        ? cached.bytes
        : null;
  }

  /// A cached rendered button thumbnail for [e] (96px). Returns the cached PNG
  /// instantly when [e]'s framing inputs are unchanged; otherwise renders once
  /// (from the downscaled source) and caches it.
  Future<Uint8List?> buttonThumb(Emote? e, {int size = 96}) async {
    if (e == null) return null;
    final String base = e.sprite;
    final int key = buttonThumbKey(e);
    final ({int key, Uint8List bytes})? cached = _thumbCache[base];
    if (cached != null && cached.key == key) return cached.bytes;
    final Uint8List? bytes = await previewButtonForEmote(e, size);
    if (bytes != null && base.isNotEmpty) {
      _thumbCache[base] = (key: key, bytes: bytes);
    }
    return bytes;
  }

  /// A cheap per-sprite signature of everything that changes [e]'s rendered
  /// button thumbnail. The list passes this as each thumbnail's reload key, so a
  /// thumbnail only re-renders when **its own** framing inputs change — dragging
  /// one sprite's crop box re-renders exactly one thumbnail, not all the visible
  /// ones (the fix for the drag-stop freeze on a big cast).
  int buttonThumbKey(Emote e) {
    int h = spriteRevision;
    h = h * 31 + buttonFraming.index;
    h = h * 31 + (buttonZoom * 100).round();
    h = h * 31 + (buttonOffsetX * 100).round();
    h = h * 31 + (buttonOffsetY * 100).round();
    // Per-sprite overlay: fold in THIS sprite's slot revisions so changing one
    // sprite's border re-renders only its own thumbnail (not the whole list).
    h = h * 31 + (buttonOverlay(e.sprite, fg: true)?.rev ?? 0);
    h = h * 31 + (buttonOverlay(e.sprite, fg: false)?.rev ?? 0);
    if (buttonFraming == CropFraming.manual) {
      final CropBox? box = buttonCropRaw(e.sprite);
      if (box != null) {
        h = h * 31 + (box.x * 1000).round();
        h = h * 31 + (box.y * 1000).round();
        h = h * 31 + (box.side * 1000).round();
      }
    }
    return h;
  }

  /// The plain base sprite (bytes + aspect) for the manual crop-box editor, for
  /// the given [e]mote. Reloads via the decode/preview caches; the editor calls
  /// this on emote-change and [spriteRevision] change.
  Future<({Uint8List? bytes, double? aspect})> spriteEditorSource(Emote? e) async {
    if (e == null) return (bytes: null, aspect: null);
    final String? rel = spriteRelFor(e);
    if (rel == null) return (bytes: null, aspect: null);
    final img.Image? im = await decodeFirstFrame(rel);
    final Uint8List? bytes = await previewSprite(rel);
    final double? aspect =
        (im == null || im.height == 0) ? null : im.width / im.height;
    return (bytes: bytes, aspect: aspect);
  }

  /// A [CropBox] seeded from [e]'s auto head-square, so Manual mode starts at the
  /// detected face and you adjust from there. Falls back to [CropBox.initial].
  ///
  /// Perf: uses the **downscaled** (≤640px) source — `headSquare` is a per-pixel
  /// silhouette scan, and the result is a *fraction* (resolution-independent), so
  /// detecting the face on a small copy is identical but ~10× cheaper. This is
  /// what made rapidly pressing "make it & next" through a cast jank — every
  /// arrival on an un-framed sprite ran this synchronously on the full-res image.
  Future<CropBox> headCropFor(Emote? e) async {
    if (e == null) return CropBox.initial;
    final String? rel = spriteRelFor(e);
    if (rel == null) return CropBox.initial;
    // The head-square is a per-pixel silhouette scan and the result is a
    // resolution-independent fraction, so memoise it per sprite path: stepping
    // back and forth through a cast (or re-seeding boxes) is then a map hit
    // instead of re-scanning the image each time.
    final CropBox? cached = _headSquareCache[rel];
    if (cached != null) return cached;
    final img.Image? im = await _decodeButtonSource(rel);
    if (im == null) return CropBox.initial;
    final CropBox box =
        CropBox.fromPixels(ButtonMaker.headSquare(im), im.width, im.height);
    return _headSquareCache[rel] = box;
  }

  /// The emote the char_icon is rendered from: [iconSourceEmote] (clamped), or
  /// the next emote with a sprite so the icon is never blank.
  Emote? iconEmote() {
    final List<Emote>? es = character?.emotes;
    if (es == null || es.isEmpty) return null;
    final int start = iconSourceEmote.clamp(0, es.length - 1);
    for (int k = 0; k < es.length; k++) {
      final Emote e = es[(start + k) % es.length];
      if (spriteRelFor(e) != null) return e;
    }
    return es[start];
  }

  /// Preview the auto-generated **char_icon**, using the current
  /// [iconFraming]/[iconZoom] and [iconSourceEmote]. Renders at [size] px when
  /// given (the studio passes a larger preview resolution so a small icon still
  /// frames crisply on screen), otherwise at the real [iconSize] that
  /// [saveCharIcon] bakes into the export.
  Future<Uint8List?> previewCharIcon([int? size]) async {
    final Emote? e = iconEmote();
    if (e == null) return null;
    final String? rel = spriteRelFor(e);
    if (rel == null) return null;
    final img.Image? frame = await decodeFirstFrame(rel);
    if (frame == null) return null;
    return ButtonMaker.renderFramed(frame, size ?? iconSize,
        framing: iconFraming,
        zoom: iconZoom,
        offsetX: iconOffsetX,
        offsetY: iconOffsetY,
        background: iconBg.image,
        foreground: iconFg.image,
        manualCrop: iconFraming == CropFraming.manual ? iconCrop : null);
  }

  /// Bake `char_icon.png` into the project root (so it's part of the export) and
  /// download/save it. Returns the saved path, or null if nothing to render.
  Future<String?> saveCharIcon() async {
    final Uint8List? png = await previewCharIcon();
    if (png == null) {
      status = 'No sprite to make a char_icon from.';
      notifyListeners();
      return null;
    }
    await workspace.writeBytes(CharFolder.charIcon, png);
    _invalidateImageCaches();
    _setBusy(false, 'Saved ${CharFolder.charIcon} (${iconSize}px).');
    return saveBytes(CharFolder.charIcon, png);
  }

  /// Convert every sprite to [format] (with optional WebP settings).
  Future<int> bulkConvert(
    OutputFormat format, {
    bool webpLossless = false,
    int webpQuality = 90,
    bool deleteOriginal = false,
  }) async {
    if (scan == null) return 0;
    _setBusy(true, 'Converting sprites…');
    final List<String> targets = <String>[];
    for (final SpriteGroup g in scan!.groups) {
      for (final SpriteFile f
          in <SpriteFile?>[g.idle, g.talk, g.post, ...g.statics].whereType<SpriteFile>()) {
        targets.add(f.relPath);
      }
    }
    final List<BulkResult> res = await BulkProcessor(workspace).run(
      files: targets,
      output: format,
      webpLossless: webpLossless,
      webpQuality: webpQuality,
      deleteOriginalOnConvert: deleteOriginal,
      onProgress: (int d, int t, String l) => _progress(d, t, 'Convert'),
    );
    _invalidateImageCaches();
    if (deleteOriginal) await _rebuild();
    final int ok = res.where((BulkResult r) => r.ok).length;
    final int fail = res.length - ok;
    _setBusy(false, 'Converted $ok sprite(s)${fail > 0 ? ', $fail failed' : ''}.');
    return ok;
  }

  // ---------------------------------------------------------------------------
  // Animation generation
  // ---------------------------------------------------------------------------

  /// Render a preview clip for the selected sprite using [recipes].
  Future<List<Uint8List>> renderAnimationPreview(
    List<AnimRecipe> recipes, {
    int frames = 12,
    int fps = 12,
    int maxEdge = 360,
  }) async {
    final Emote? e = current;
    if (e == null) return <Uint8List>[];
    final String? rel = spriteRelFor(e);
    if (rel == null) return <Uint8List>[];
    img.Image? base = await decodeFirstFrame(rel);
    if (base == null) return <Uint8List>[];
    // Downscale for the live preview so rendering N frames stays snappy (the
    // real export renders at full resolution).
    final int longest = base.width > base.height ? base.width : base.height;
    if (longest > maxEdge) {
      final double s = maxEdge / longest;
      base = img.copyResize(base,
          width: (base.width * s).round(),
          height: (base.height * s).round(),
          interpolation: img.Interpolation.average);
    }
    final AnimClip clip = AnimEngine.render(base, recipes, frames: frames, fps: fps);
    return clip.frames.map((AnimFrame f) => Codecs.encodePng(f.image)).toList();
  }

  /// Render an animation onto the selected sprite at full resolution and save it
  /// (e.g. as a talking `(b)` sprite) as an APNG/GIF.
  Future<String?> saveAnimation(
    List<AnimRecipe> recipes, {
    int frames = 12,
    int fps = 12,
    String prefix = SpritePrefix.talk,
    // WebP is the default. Lossless by default so quality is preserved. Falls
    // back to APNG only if the platform genuinely can't encode WebP.
    bool preferWebp = true,
    bool lossless = true,
    int quality = 95,
  }) async {
    final Emote? e = current;
    if (e == null) return null;
    final String? rel = spriteRelFor(e);
    if (rel == null) return null;
    final img.Image? base = await decodeFirstFrame(rel);
    if (base == null) return null;
    _setBusy(true, 'Rendering animation…');
    final AnimClip clip = AnimEngine.render(base, recipes, frames: frames, fps: fps);

    final Uint8List bytes;
    final String ext;
    String? webpError;
    if (preferWebp) {
      final ({Uint8List bytes, String ext, String? webpError}) r =
          await clip.encodePreferWebp(lossless: lossless, quality: quality);
      bytes = r.bytes;
      ext = r.ext;
      webpError = r.webpError;
    } else {
      bytes = clip.encode(ext: 'apng');
      ext = 'apng';
    }

    // Also drop it into the project so it becomes part of the export.
    final String spriteName = e.sprite.isEmpty ? 'anim' : e.sprite;
    final String outRel = '$prefix$spriteName.$ext';
    await workspace.writeBytes(outRel, bytes);
    _invalidateImageCaches();
    _setBusy(false, 'Saved $outRel as ${_animNote(ext, webpError)}.');
    return saveBytes('$prefix$spriteName.$ext', bytes);
  }

  /// Human-readable note for an animation save: plain `WebP`, or an APNG
  /// fallback that says **why** WebP wasn't used — so a stray APNG is something
  /// you can fix (bundle/locate `libwebpmux`) instead of a silent mystery.
  String _animNote(String ext, String? webpError) => ext == 'webp'
      ? 'animated WebP'
      : 'APNG — animated WebP unavailable (${webpError ?? 'no native libwebpmux'})';

  /// **Bulk-animate every sprite** with one effect stack: render [recipes] onto
  /// each sprite group's representative frame at full resolution and save each as
  /// an animated WebP (APNG fallback) under [prefix] (talk `(b)` by default).
  /// This is "animate all sprites at once" — e.g. give every expression the same
  /// idle sway/breathe in a single action.
  ///
  /// The heavy render+encode for each sprite runs **off the UI isolate** (via
  /// `compute`) so the app stays responsive instead of freezing — while staying
  /// **lossless** (no quality loss), same as the single-sprite save. Any existing
  /// sprite of the same state (a/b/c) for a base is replaced, so you never end up
  /// with a stale `(b)foo.png` beside a fresh `(b)foo.webp`. Returns the number
  /// of sprites animated.
  Future<int> bulkAnimateAll(
    List<AnimRecipe> recipes, {
    int frames = 16,
    int fps = 12,
    String prefix = SpritePrefix.talk,
    // Lossless by default — bulk export must not degrade quality. Responsiveness
    // comes from the background isolate, not from dropping to lossy.
    bool lossless = true,
    int quality = 95,
  }) async {
    if (recipes.isEmpty || scan == null) return 0;
    final List<SpriteGroup> groups = scan!.groups.toList();
    if (groups.isEmpty) return 0;
    _setBusy(true, 'Animating ${groups.length} sprites…');
    await logCrash('bulkAnimate start: ${groups.length} sprite(s), '
        'chunk=$_bulkChunk, concurrency=$maxConcurrency, mobile=$isMobile');

    final List<Map<String, dynamic>> recipeJson =
        recipes.map((AnimRecipe r) => r.toJson()).toList();

    // Lightweight descriptors first (no preloaded bytes) so memory doesn't grow
    // with the cast size.
    final List<SpriteGroup> jobGroups = <SpriteGroup>[];
    final List<String> jobRels = <String>[];
    for (final SpriteGroup g in groups) {
      final String? rel = g.representative?.relPath;
      if (rel == null || !await workspace.exists(rel)) continue;
      jobGroups.add(g);
      jobRels.add(rel);
    }

    int ok = 0;
    int webp = 0;
    String? lastError;
    // Render + write in chunks (see [bulkJiggleAll]) so a big cast doesn't hold
    // every source + every clip at once and OOM on mobile. `compute` runs inline
    // on web / on error so the bake still completes; order preserved per chunk.
    final int chunk = _bulkChunk;
    for (int start = 0; start < jobRels.length; start += chunk) {
      final int end =
          start + chunk < jobRels.length ? start + chunk : jobRels.length;
      final List<SpriteGroup> chunkGroups = <SpriteGroup>[];
      final List<_AnimJob> jobs = <_AnimJob>[];
      for (int i = start; i < end; i++) {
        chunkGroups.add(jobGroups[i]);
        jobs.add(_AnimJob(
          bytes: await workspace.readBytes(jobRels[i]),
          ext: p.extension(jobRels[i]).replaceFirst('.', ''),
          recipes: recipeJson,
          frames: frames,
          fps: fps,
          lossless: lossless,
          quality: quality,
        ));
      }

      final List<({Uint8List bytes, String ext, String? webpError})> results =
          await mapParallel<_AnimJob,
              ({Uint8List bytes, String ext, String? webpError})>(
        jobs,
        _computeAnim,
        concurrency: maxConcurrency,
        onProgress: (int d, int t) =>
            _progress(start + d, jobRels.length, 'Animate all'),
      );

      for (int j = 0; j < chunkGroups.length; j++) {
        final SpriteGroup g = chunkGroups[j];
        final ({Uint8List bytes, String ext, String? webpError}) r = results[j];
        if (r.bytes.isEmpty || r.ext == 'none') continue;
        final String outRel = '$prefix${g.base}.${r.ext}';
        // Replace an existing same-state sprite for this base (different ext) so
        // we don't leave two talk sprites for one pose.
        final SpriteFile? existing = switch (prefix) {
          SpritePrefix.idle => g.idle,
          SpritePrefix.talk => g.talk,
          SpritePrefix.post => g.post,
          _ => null,
        };
        if (existing != null &&
            existing.relPath != outRel &&
            await workspace.exists(existing.relPath)) {
          await workspace.delete(existing.relPath);
        }
        await workspace.writeBytes(outRel, r.bytes);
        ok++;
        if (r.ext == 'webp') {
          webp++;
        } else {
          lastError = r.webpError;
        }
      }
      await Future<void>.delayed(Duration.zero);
    }

    _invalidateImageCaches();
    scan = _scanner.fromPaths(await _projectFiles());
    final String note = ok == 0
        ? 'no sprites to animate'
        : webp == ok
            ? '$ok sprite(s) as animated WebP'
            : '$ok sprite(s) — $webp WebP, ${ok - webp} APNG '
                '(${lastError ?? 'native WebP unavailable'})';
    _setBusy(false, 'Animated $note.');
    return ok;
  }

  /// `compute` the effect-stack render for one sprite, falling back inline if
  /// the isolate handoff fails (and always inline on web).
  Future<({Uint8List bytes, String ext, String? webpError})> _computeAnim(
      _AnimJob job) async {
    try {
      return await compute(_bulkAnimateWorker, job);
    } catch (_) {
      return await _bulkAnimateWorker(job);
    }
  }

  // ---------------------------------------------------------------------------
  // Jiggle physics — bounce a region (chest/body/hair/anything)
  // ---------------------------------------------------------------------------

  /// Preview the jiggle [specs] on the **selected** sprite: decode → downscale →
  /// render the region bounce → return looping PNG frames. The recipes are built
  /// against the *downscaled* dimensions so the box lines up with the preview.
  Future<List<Uint8List>> previewJiggle(
    List<JiggleSpec> specs, {
    int frames = 18,
    int fps = 16,
    int maxEdge = 360,
  }) async {
    final Emote? e = current;
    if (e == null || specs.isEmpty) return const <Uint8List>[];
    final String? rel = spriteRelFor(e);
    if (rel == null) return const <Uint8List>[];
    img.Image? base = await decodeFirstFrame(rel);
    if (base == null) return const <Uint8List>[];
    final int longest = base.width > base.height ? base.width : base.height;
    if (longest > maxEdge) {
      final double s = maxEdge / longest;
      base = img.copyResize(base,
          width: (base.width * s).round(),
          height: (base.height * s).round(),
          interpolation: img.Interpolation.average);
    }
    final List<AnimRecipe> recipes = <AnimRecipe>[
      for (final JiggleSpec j in specs) ...j.toRecipes(base.width, base.height),
    ];
    final AnimClip clip =
        AnimEngine.render(base, recipes, frames: frames, fps: fps);
    return clip.frames.map((AnimFrame f) => Codecs.encodePng(f.image)).toList();
  }

  /// Bake the jiggle [specs] onto the **selected** sprite at full resolution and
  /// save it. Jiggle is an **idle** motion, so it saves as the `(a)` sprite by
  /// default (so it plays while the character is just standing there). WebP,
  /// APNG fallback.
  Future<String?> saveJiggle(
    List<JiggleSpec> specs, {
    int frames = 18,
    int fps = 16,
    String prefix = SpritePrefix.idle,
    bool lossless = true,
    int quality = 95,
  }) async {
    final Emote? e = current;
    if (e == null || specs.isEmpty) return null;
    final String? rel = spriteRelFor(e);
    if (rel == null) return null;
    final img.Image? base = await decodeFirstFrame(rel);
    if (base == null) return null;
    final List<AnimRecipe> recipes = <AnimRecipe>[
      for (final JiggleSpec j in specs) ...j.toRecipes(base.width, base.height),
    ];
    // Reuse the tested full-res render+encode+write path.
    return saveAnimation(recipes,
        frames: frames,
        fps: fps,
        prefix: prefix,
        lossless: lossless,
        quality: quality);
  }

  /// **Jiggle every sprite** with the same fractional [specs] (a chest box sits
  /// in roughly the same place across a character's poses). Each sprite's recipe
  /// is built from its own dimensions, then rendered + encoded across all CPU
  /// cores. Saves as `(a)` idle by default. Returns how many were animated.
  Future<int> bulkJiggleAll(
    List<JiggleSpec> specs, {
    int frames = 18,
    int fps = 16,
    String prefix = SpritePrefix.idle,
    bool lossless = true,
    int quality = 95,
  }) async {
    if (specs.isEmpty || scan == null) return 0;
    final List<SpriteGroup> groups = scan!.groups.toList();
    if (groups.isEmpty) return 0;
    _setBusy(true, 'Jiggling ${groups.length} sprites…');
    // Breadcrumb: a hard OOM kills the app before any Dart error handler runs, so
    // the *last* breadcrumb written here is how we know where a big bulk run died.
    await logCrash('bulkJiggle start: ${groups.length} sprite(s), '
        'chunk=$_bulkChunk, concurrency=$maxConcurrency, mobile=$isMobile, '
        'boxes=${specs.length}');

    // Lightweight descriptors first — NO preloaded source bytes — so memory
    // doesn't grow with the cast size.
    final List<SpriteGroup> jobGroups = <SpriteGroup>[];
    final List<String> jobRels = <String>[];
    for (final SpriteGroup g in groups) {
      final String? rel = g.representative?.relPath;
      if (rel == null || !await workspace.exists(rel)) continue;
      jobGroups.add(g);
      jobRels.add(rel);
    }

    int ok = 0;
    // Render + write in **chunks**, freeing each batch before the next. Without
    // this a big cast held every source byte AND every encoded clip in RAM at
    // once and OOM-crashed on mobile (the ~70-sprite ceiling). [_bulkChunk] caps
    // the batch; [maxConcurrency] caps in-flight renders (1 on mobile).
    final int chunk = _bulkChunk;
    for (int start = 0; start < jobRels.length; start += chunk) {
      final int end =
          start + chunk < jobRels.length ? start + chunk : jobRels.length;
      final List<SpriteGroup> chunkGroups = <SpriteGroup>[];
      final List<_AnimJob> jobs = <_AnimJob>[];
      for (int i = start; i < end; i++) {
        final String rel = jobRels[i];
        // Per-sprite dims → per-sprite pixel regions (fractions are shared).
        final img.Image? dims = await decodeFirstFrame(rel);
        if (dims == null) continue;
        final List<Map<String, dynamic>> recipeJson = <Map<String, dynamic>>[
          for (final JiggleSpec j in specs)
            for (final AnimRecipe r in j.toRecipes(dims.width, dims.height))
              r.toJson(),
        ];
        chunkGroups.add(jobGroups[i]);
        jobs.add(_AnimJob(
          bytes: await workspace.readBytes(rel),
          ext: p.extension(rel).replaceFirst('.', ''),
          recipes: recipeJson,
          frames: frames,
          fps: fps,
          lossless: lossless,
          quality: quality,
        ));
      }

      final List<({Uint8List bytes, String ext, String? webpError})> results =
          await mapParallel<_AnimJob,
              ({Uint8List bytes, String ext, String? webpError})>(
        jobs,
        _computeAnim,
        concurrency: maxConcurrency,
        onProgress: (int d, int t) =>
            _progress(start + d, jobRels.length, 'Jiggle all'),
      );

      for (int j = 0; j < chunkGroups.length; j++) {
        final SpriteGroup g = chunkGroups[j];
        final ({Uint8List bytes, String ext, String? webpError}) r = results[j];
        if (r.bytes.isEmpty || r.ext == 'none') continue;
        final String outRel = '$prefix${g.base}.${r.ext}';
        final SpriteFile? existing = switch (prefix) {
          SpritePrefix.idle => g.idle,
          SpritePrefix.talk => g.talk,
          SpritePrefix.post => g.post,
          _ => null,
        };
        if (existing != null &&
            existing.relPath != outRel &&
            await workspace.exists(existing.relPath)) {
          await workspace.delete(existing.relPath);
        }
        await workspace.writeBytes(outRel, r.bytes);
        ok++;
      }
      await logCrash('bulkJiggle: $end/${jobRels.length} sprite(s) done');
      await Future<void>.delayed(Duration.zero); // let the batch GC + UI breathe
    }

    await logCrash('bulkJiggle finished: $ok sprite(s)');
    _invalidateImageCaches();
    scan = _scanner.fromPaths(await _projectFiles());
    _setBusy(false, 'Jiggled $ok sprite(s).');
    return ok;
  }

  // ---------------------------------------------------------------------------
  // Mouth / lip-sync animation — fake a talking (b) sprite from one drawing
  // ---------------------------------------------------------------------------

  /// An optional **open-mouth sprite** to *mesh* in: when set, the talking
  /// animation cross-fades this real open mouth (cut at the mouth box, feathered)
  /// onto the closed sprite, instead of the procedural cavity / drawn shape. Use
  /// it when you have art of the same character with their mouth open.
  img.Image? meshOpenSprite;

  /// Thumbnail bytes of the loaded mesh sprite (for the UI), null when unset.
  Uint8List? meshOpenThumb;

  bool get hasMeshSprite => meshOpenSprite != null;

  /// Load an open-mouth sprite to mesh from (its first frame). Null clears it.
  void setMeshSprite(Uint8List? bytes, {String ext = 'png'}) {
    if (bytes == null) {
      meshOpenSprite = null;
      meshOpenThumb = null;
    } else {
      meshOpenSprite = Codecs.decodeFirstFrame(bytes, ext: ext);
      meshOpenThumb = meshOpenSprite == null ? null : bytes;
    }
    notifyListeners();
  }

  /// The face-derived default mouth box for sprite [rel], as fractions (so it
  /// survives previews/resizes). Used to seed the Mouth tab so most sprites need
  /// no adjustment. Returns null if the sprite can't be decoded.
  Future<MouthRegion?> defaultMouthRegionFor(String rel) async {
    final img.Image? base = await decodeFirstFrame(rel);
    if (base == null) return null;
    return MouthRegion.defaultFor(base);
  }

  /// Width÷height of the **selected** sprite's first frame (for drawing the
  /// adjustable mouth box at the right aspect). Null if nothing is selected.
  Future<double?> currentSpriteAspect() async {
    final Emote? e = current;
    if (e == null) return null;
    final String? rel = spriteRelFor(e);
    if (rel == null) return null;
    final img.Image? im = await decodeFirstFrame(rel);
    if (im == null || im.height == 0) return null;
    return im.width / im.height;
  }

  /// Preview the talking-mouth animation for the **selected** sprite: decode →
  /// drop the jaw inside [mouth] with a speech-like cadence → return downscaled
  /// PNG frames the Animation Studio loops. The mouth box is in fractions so it
  /// maps onto the downscaled preview unchanged.
  Future<List<Uint8List>> previewMouthTalk(
    MouthRegion mouth, {
    int frames = 8,
    int fps = 10,
    double openAmount = LipSync.defaultOpenAmount,
    TalkStyle? style,
    MouthShape? shape,
    bool mesh = false,
    int maxEdge = 360,
  }) async {
    final Emote? e = current;
    if (e == null) return const <Uint8List>[];
    final String? rel = spriteRelFor(e);
    if (rel == null) return const <Uint8List>[];
    final img.Image? decoded = await decodeFirstFrame(rel);
    if (decoded == null) return const <Uint8List>[];
    // Downscale for a snappy preview; the engine clones internally so the cached
    // decode is never mutated even when `_fitEdge` returns it unchanged.
    final img.Image base = _fitEdge(decoded, maxEdge);
    final IntRect regionPx = mouth.toPixels(base.width, base.height);
    final AnimClip clip = _buildTalkClip(base, regionPx, mouth,
        style: style ?? LipSync.defaultStyle,
        shape: shape,
        mesh: mesh,
        frames: frames,
        fps: fps,
        openAmount: openAmount,
        maxEdge: maxEdge);
    return clip.frames.map((AnimFrame f) => Codecs.encodePng(f.image)).toList();
  }

  /// Build a talking clip for [base] (already sized): mesh a real open mouth if
  /// one is loaded, else a drawn [shape], else the procedural cavity. [maxEdge]
  /// is used to scale the mesh sprite to match a downscaled preview ([base]); for
  /// the full-res save pass `maxEdge: 0` so the mesh sprite is used at full size.
  AnimClip _buildTalkClip(
    img.Image base,
    IntRect regionPx,
    MouthRegion mouthFrac, {
    required TalkStyle style,
    MouthShape? shape,
    bool mesh = false,
    required int frames,
    required int fps,
    required double openAmount,
    int maxEdge = 0,
  }) {
    if (mesh && meshOpenSprite != null) {
      final img.Image open =
          maxEdge > 0 ? _fitEdge(meshOpenSprite!, maxEdge) : meshOpenSprite!;
      final img.Image piece = LipSync.cutMouthPiece(
          open, mouthFrac.toPixels(open.width, open.height));
      return LipSync.talkMeshed(base, piece, regionPx, style,
          frames: frames, fps: fps, openAmount: openAmount);
    }
    return LipSync.talkStyled(base, style,
        mouth: regionPx,
        frames: frames,
        fps: fps,
        openAmount: openAmount,
        shape: shape);
  }

  /// Bake the talking-mouth animation for the **selected** sprite at full
  /// resolution and save it under [prefix] (talk `(b)` by default) — both into
  /// the project (so it's exported) and as a download. WebP, APNG fallback.
  Future<String?> saveMouthTalk(
    MouthRegion mouth, {
    int frames = 8,
    int fps = 10,
    double openAmount = LipSync.defaultOpenAmount,
    TalkStyle? style,
    MouthShape? shape,
    bool mesh = false,
    String prefix = SpritePrefix.talk,
    bool lossless = true,
    int quality = 95,
  }) async {
    final Emote? e = current;
    if (e == null) return null;
    final String? rel = spriteRelFor(e);
    if (rel == null) return null;
    final img.Image? base = await decodeFirstFrame(rel);
    if (base == null) return null;
    _setBusy(true, 'Rendering mouth animation…');
    // Full-res: mesh sprite used at full size (maxEdge: 0).
    final AnimClip clip = _buildTalkClip(
        base, mouth.toPixels(base.width, base.height), mouth,
        style: style ?? LipSync.defaultStyle,
        shape: shape,
        mesh: mesh,
        frames: frames,
        fps: fps,
        openAmount: openAmount);
    final ({Uint8List bytes, String ext, String? webpError}) r =
        await clip.encodePreferWebp(lossless: lossless, quality: quality);

    final String spriteName = e.sprite.isEmpty ? 'anim' : e.sprite;
    final String outRel = '$prefix$spriteName.${r.ext}';
    await _replaceStateSprite(e.sprite, prefix, outRel);
    await workspace.writeBytes(outRel, r.bytes);
    _invalidateImageCaches();
    scan = _scanner.fromPaths(await _projectFiles());
    _setBusy(false, 'Saved $outRel as ${_animNote(r.ext, r.webpError)}.');
    return saveBytes(outRel, r.bytes);
  }

  /// **Give every sprite a talking mouth at once.** Each sprite's mouth box is
  /// auto-placed from its own face, then a talking `(b)` animation is baked and
  /// saved (WebP, APNG fallback). Rendering + encoding run across all CPU cores
  /// (see [maxConcurrency]). Returns how many sprites were animated.
  Future<int> bulkMouthTalkAll({
    int frames = 8,
    int fps = 10,
    double openAmount = LipSync.defaultOpenAmount,
    TalkStyle? style,
    MouthShape? shape,
    String prefix = SpritePrefix.talk,
    bool lossless = true,
    int quality = 95,
  }) async {
    if (scan == null) return 0;
    final List<SpriteGroup> groups = scan!.groups.toList();
    if (groups.isEmpty) return 0;
    _setBusy(true, 'Adding talking mouths to ${groups.length} sprites…');
    await logCrash('bulkMouth start: ${groups.length} sprite(s), '
        'chunk=$_bulkChunk, concurrency=$maxConcurrency, mobile=$isMobile');

    // Lightweight descriptors first (no preloaded bytes) so memory doesn't grow
    // with the cast size.
    final List<SpriteGroup> jobGroups = <SpriteGroup>[];
    final List<String> jobRels = <String>[];
    for (final SpriteGroup g in groups) {
      final String? rel = g.representative?.relPath;
      if (rel == null || !await workspace.exists(rel)) continue;
      jobGroups.add(g);
      jobRels.add(rel);
    }

    int ok = 0;
    int webp = 0;
    String? lastError;
    // Chunk it (see [bulkJiggleAll]) so a big cast doesn't OOM on mobile.
    final int chunk = _bulkChunk;
    for (int start = 0; start < jobRels.length; start += chunk) {
      final int end =
          start + chunk < jobRels.length ? start + chunk : jobRels.length;
      final List<SpriteGroup> chunkGroups = <SpriteGroup>[];
      final List<_MouthJob> jobs = <_MouthJob>[];
      for (int i = start; i < end; i++) {
        chunkGroups.add(jobGroups[i]);
        jobs.add(_MouthJob(
          bytes: await workspace.readBytes(jobRels[i]),
          ext: p.extension(jobRels[i]).replaceFirst('.', ''),
          frames: frames,
          fps: fps,
          openAmount: openAmount,
          style: style ?? LipSync.defaultStyle,
          shape: shape,
          lossless: lossless,
          quality: quality,
        ));
      }

      final List<({Uint8List bytes, String ext, String? webpError})> results =
          await mapParallel<_MouthJob,
              ({Uint8List bytes, String ext, String? webpError})>(
        jobs,
        _computeMouth,
        concurrency: maxConcurrency,
        onProgress: (int d, int t) =>
            _progress(start + d, jobRels.length, 'Mouth animate all'),
      );

      for (int j = 0; j < chunkGroups.length; j++) {
        final SpriteGroup g = chunkGroups[j];
        final ({Uint8List bytes, String ext, String? webpError}) r = results[j];
        if (r.bytes.isEmpty || r.ext == 'none') continue;
        final String outRel = '$prefix${g.base}.${r.ext}';
        await _replaceStateSprite(g.base, prefix, outRel);
        await workspace.writeBytes(outRel, r.bytes);
        ok++;
        if (r.ext == 'webp') {
          webp++;
        } else {
          lastError = r.webpError;
        }
      }
      await Future<void>.delayed(Duration.zero);
    }

    _invalidateImageCaches();
    scan = _scanner.fromPaths(await _projectFiles());
    final String note = ok == 0
        ? 'no sprites to animate'
        : webp == ok
            ? '$ok sprite(s) as animated WebP'
            : '$ok sprite(s) — $webp WebP, ${ok - webp} APNG '
                '(${lastError ?? 'native WebP unavailable'})';
    _setBusy(false, 'Added talking mouths to $note.');
    return ok;
  }

  /// `compute` the mouth render for one sprite, falling back inline on failure.
  Future<({Uint8List bytes, String ext, String? webpError})> _computeMouth(
      _MouthJob job) async {
    try {
      return await compute(_mouthWorker, job);
    } catch (_) {
      return await _mouthWorker(job);
    }
  }

  /// Delete the existing sprite of state [prefix] for [base] when it differs
  /// from [outRel] (avoids leaving e.g. a stale `(b)foo.png` next to a fresh
  /// `(b)foo.webp`). No-op if the group/file isn't found.
  Future<void> _replaceStateSprite(
      String base, String prefix, String outRel) async {
    final SpriteGroup? g =
        scan?.groups.firstWhereOrNull((SpriteGroup g) => g.base == base);
    if (g == null) return;
    final SpriteFile? existing = switch (prefix) {
      SpritePrefix.idle => g.idle,
      SpritePrefix.talk => g.talk,
      SpritePrefix.post => g.post,
      _ => null,
    };
    if (existing != null &&
        existing.relPath != outRel &&
        await workspace.exists(existing.relPath)) {
      await workspace.delete(existing.relPath);
    }
  }

  // ---------------------------------------------------------------------------
  // One-click "auto-magic" — sprites → finished, exported character
  // ---------------------------------------------------------------------------

  /// **Do everything, in one click.** Build the finished character — auto
  /// `char.ini`, `emotions/` buttons and `char_icon.png` using the current
  /// Button & Icon Studio settings — and download it as a ready-to-drop `.zip`,
  /// via the **same export path as "Export .zip"** (so it's just as reliable).
  ///
  /// [convertToWebp] is **off by default**: force-converting every sprite to WebP
  /// through the native `libwebp` FFI is the heaviest, most fragile step and was
  /// *hard-crashing* the app (the window just closing — an OOM/native crash Dart
  /// can't catch) on some sprite sets. So One-Click now copies sprites in their
  /// existing format (still AO-compatible); convert deliberately via **Bulk →
  /// WebP** when you want it, where any encoder problem is isolated to that step.
  /// Sprites the maker *generates* (animations/mouths) are already WebP.
  /// Emotes/edits are preserved; nothing is rebuilt. Returns the saved `.zip`.
  Future<String?> autoMagicExport({bool convertToWebp = false}) async {
    if (character == null || scan == null) {
      _setBusy(false, 'Import some sprites first (Home).');
      return null;
    }
    _setBusy(true, 'One-click: finishing your character…');
    // Breadcrumb to pinsel_crash.log: a HARD crash (OOM / native segfault) can't
    // be caught in Dart, but the last breadcrumb before the window dies tells us
    // which phase did it.
    await logCrash('one-click start: ${scan!.groups.length} sprite group(s), '
        'convertToWebp=$convertToWebp');

    int converted = 0;
    int convertFail = 0;
    if (convertToWebp) {
      final List<String> targets = <String>[
        for (final SpriteGroup g in scan!.groups)
          for (final SpriteFile f in <SpriteFile?>[
            g.idle,
            g.talk,
            g.post,
            ...g.statics
          ].whereType<SpriteFile>())
            f.relPath,
      ];
      // Lossless so quality is preserved; delete the original so the export is
      // clean WebP. We refresh `scan` afterwards WITHOUT rebuilding the
      // character, so emote edits survive (base names are unchanged).
      await logCrash('one-click: converting ${targets.length} sprite(s) to WebP');
      final List<BulkResult> res = await BulkProcessor(workspace).run(
        files: targets,
        output: OutputFormat.webp,
        webpLossless: true,
        deleteOriginalOnConvert: true,
        onProgress: (int d, int t, String l) => _progress(d, t, 'To WebP'),
      );
      converted = res.where((BulkResult r) => r.ok).length;
      convertFail = res.length - converted;
      _invalidateImageCaches();
      scan = _scanner.fromPaths(await _projectFiles());
    }

    // exportZip rebuilds the output folder (ini + buttons + icon) and downloads.
    await logCrash('one-click: building + zipping export');
    final String? path = await exportZip();
    await logCrash('one-click done: ${path ?? "no path"}');
    final String convNote = convertToWebp
        ? ' · $converted→WebP${convertFail > 0 ? " ($convertFail kept as-is)" : ""}'
        : '';
    _setBusy(
        false,
        path == null
            ? 'One-click finished$convNote.'
            : 'Done! Exported your character .zip$convNote.');
    return path;
  }

  // ---------------------------------------------------------------------------
  // Frame-sequence animation — assemble chosen frames into ONE animation
  // (classic frame-by-frame, no procedural effect required).
  // ---------------------------------------------------------------------------

  /// Every sprite file in the project, as `(rel, label)`, for the frame picker.
  List<({String rel, String label})> spriteFiles() {
    final List<({String rel, String label})> out = <({String rel, String label})>[];
    for (final SpriteGroup g in scan?.groups ?? const <SpriteGroup>[]) {
      for (final SpriteFile f
          in <SpriteFile?>[g.idle, g.talk, g.post, ...g.statics].whereType<SpriteFile>()) {
        out.add((rel: f.relPath, label: f.relPath));
      }
    }
    return out;
  }

  /// Pad frames onto a shared canvas (max width/height) so a sequence of
  /// differently-sized sprites lines up. [align] 0=top, 1=center, 2=bottom
  /// (default — AO sprites stand on the floor).
  List<img.Image> _normalizeFrames(List<img.Image> imgs, int align) {
    int w = 0, h = 0;
    for (final img.Image im in imgs) {
      if (im.width > w) w = im.width;
      if (im.height > h) h = im.height;
    }
    if (w == 0 || h == 0) return imgs;
    final List<img.Image> out = <img.Image>[];
    for (final img.Image im in imgs) {
      if (im.width == w && im.height == h) {
        out.add(im);
        continue;
      }
      final img.Image canvas = img.Image(width: w, height: h, numChannels: 4);
      final int dx = ((w - im.width) / 2).round();
      final int dy = align == 0
          ? 0
          : align == 1
              ? ((h - im.height) / 2).round()
              : h - im.height;
      out.add(img.compositeImage(canvas, im, dstX: dx, dstY: dy));
    }
    return out;
  }

  List<img.Image> _orderFrames(List<img.Image> frames,
      {required bool reverse, required bool pingPong}) {
    List<img.Image> seq =
        reverse ? frames.reversed.toList() : List<img.Image>.of(frames);
    if (pingPong && seq.length > 2) {
      seq = <img.Image>[...seq, ...seq.sublist(1, seq.length - 1).reversed];
    }
    return seq;
  }

  img.Image _fitEdge(img.Image im, int maxEdge) {
    final int longest = im.width > im.height ? im.width : im.height;
    if (longest <= maxEdge) return im;
    final double s = maxEdge / longest;
    return img.copyResize(im,
        width: (im.width * s).round(),
        height: (im.height * s).round(),
        interpolation: img.Interpolation.average);
  }

  /// Preview a frame sequence assembled from [rels] (downscaled PNG frames).
  Future<List<Uint8List>> renderFrameSequence(
    List<String> rels, {
    int fps = 10,
    bool reverse = false,
    bool pingPong = false,
    int align = 2,
    int maxEdge = 360,
  }) async {
    if (rels.isEmpty) return const <Uint8List>[];
    final List<img.Image> imgs = <img.Image>[];
    for (final String rel in rels) {
      final img.Image? im = await decodeFirstFrame(rel);
      if (im != null) imgs.add(im);
    }
    if (imgs.isEmpty) return const <Uint8List>[];
    List<img.Image> frames = _normalizeFrames(imgs, align);
    frames = <img.Image>[for (final img.Image im in frames) _fitEdge(im, maxEdge)];
    frames = _orderFrames(frames, reverse: reverse, pingPong: pingPong);
    return frames.map((img.Image im) => Codecs.encodePng(im)).toList();
  }

  /// Assemble [rels] into one animation and save it (WebP, APNG fallback) — both
  /// dropped into the project and downloaded. Returns the saved path.
  Future<String?> saveFrameSequence(
    List<String> rels, {
    int fps = 10,
    bool reverse = false,
    bool pingPong = false,
    int align = 2,
    String prefix = SpritePrefix.talk,
    String name = 'frames',
    bool preferWebp = true,
    bool lossless = true,
    int quality = 95,
  }) async {
    if (rels.isEmpty) return null;
    _setBusy(true, 'Assembling frames…');
    final List<img.Image> imgs = <img.Image>[];
    for (final String rel in rels) {
      final img.Image? im = await decodeFirstFrame(rel);
      if (im != null) imgs.add(im);
    }
    if (imgs.isEmpty) {
      _setBusy(false, 'No frames to assemble.');
      return null;
    }
    final List<img.Image> ordered = _orderFrames(
        _normalizeFrames(imgs, align),
        reverse: reverse,
        pingPong: pingPong);
    final int delay = (100 / fps).round().clamp(1, 1000);
    // Clone each frame: AnimClip.toImage appends the rest into the FIRST frame's
    // image, so we must not hand it (or alias) a cached/decoded image.
    final AnimClip clip = AnimClip(<AnimFrame>[
      for (final img.Image im in ordered) AnimFrame(im.clone(), delayCentis: delay),
    ]);

    final Uint8List bytes;
    final String ext;
    String? webpError;
    if (preferWebp) {
      final ({Uint8List bytes, String ext, String? webpError}) r =
          await clip.encodePreferWebp(lossless: lossless, quality: quality);
      bytes = r.bytes;
      ext = r.ext;
      webpError = r.webpError;
    } else {
      bytes = clip.encode(ext: 'apng');
      ext = 'apng';
    }

    final String safe = name.trim().isEmpty ? 'frames' : name.trim();
    final String outRel = '$prefix$safe.$ext';
    await workspace.writeBytes(outRel, bytes);
    _invalidateImageCaches();
    scan = _scanner.fromPaths(await _projectFiles());
    _setBusy(false,
        'Saved $outRel — ${ordered.length} frames as ${_animNote(ext, webpError)}.');
    return saveBytes('$prefix$safe.$ext', bytes);
  }

  // ---------------------------------------------------------------------------
  // Sprite-sheet ripper — slice a sheet of VN sprites into individual sprites
  // ---------------------------------------------------------------------------

  /// The loaded sprite sheet (raw bytes), kept on the hub so the Ripper screen
  /// survives navigation. The screen decodes it for preview/detection.
  Uint8List? ripperSheetBytes;
  String ripperSheetName = 'sheet';

  /// Load a sprite sheet for ripping.
  void loadSheet(Uint8List bytes, String name) {
    ripperSheetBytes = bytes;
    final int dot = name.lastIndexOf('.');
    ripperSheetName = dot > 0 ? name.substring(0, dot) : name;
    status = 'Loaded sheet "$name".';
    notifyListeners();
  }

  /// Export the enabled [cells] of [sheet] as individual sprite PNGs. When
  /// [toProject] they're added to the current character (or build a new one via
  /// [addSprites]); otherwise they're zipped and downloaded. Background removal
  /// runs per cell. Returns how many sprites were written.
  Future<int> exportSheetCells(
    img.Image sheet,
    List<SheetCell> cells, {
    required bool toProject,
    bool removeBg = true,
    int? bgColor,
    int tolerance = 24,
    String namePrefix = 'sprite',
  }) async {
    final List<SheetCell> enabled =
        cells.where((SheetCell c) => c.enabled).toList();
    if (enabled.isEmpty) return 0;
    _setBusy(true, 'Ripping ${enabled.length} sprite(s)…');
    await logCrash('exportSheetCells start: ${enabled.length} cell(s), '
        'toProject=$toProject');
    // When adding to the project, seed the namer with the sprites **already
    // there** so a second sheet's auto names continue past them (sprite5, 6, …)
    // instead of restarting at sprite1 and overwriting the first sheet's files.
    final Set<String> existing = <String>{};
    if (toProject) {
      for (final String rel in await _projectFiles()) {
        final String b = p.basenameWithoutExtension(rel);
        if (b.isNotEmpty) existing.add(b);
      }
    }
    final List<String> names = SpriteSheet.uniqueNames(
        existing, <String>[for (final SheetCell c in enabled) c.name], namePrefix);

    final List<PickedFile> out = <PickedFile>[];
    for (int i = 0; i < enabled.length; i++) {
      final SheetCell c = enabled[i];
      final img.Image piece = SpriteSheet.extract(sheet, c.rect,
          removeBg: removeBg, bgColor: bgColor, tolerance: tolerance);
      final Uint8List png = Codecs.encodePng(piece);
      out.add(PickedFile('${names[i]}.png', png));
      _progress(i + 1, enabled.length, 'Rip');
      if (i % 3 == 0) await Future<void>.delayed(Duration.zero);
    }

    if (toProject) {
      await addSprites(out);
      _setBusy(false, 'Ripped ${out.length} sprite(s) into the project.');
    } else {
      final Archive archive = Archive();
      for (final PickedFile f in out) {
        archive.addFile(ArchiveFile(f.name, f.bytes.length, f.bytes));
      }
      final List<int>? zip = ZipEncoder().encode(archive);
      _setBusy(false, 'Ripped ${out.length} sprite(s).');
      if (zip != null) {
        await saveBytes('${ripperSheetName}_sprites.zip', Uint8List.fromList(zip));
      }
    }
    return out.length;
  }

  // ---------------------------------------------------------------------------
  // AO2 theme maker — design a full AO2/webAO client theme
  // ---------------------------------------------------------------------------

  /// The working AO2 theme (held on the hub so the Theme Maker screen survives
  /// navigation). Null until you start or import one.
  Ao2Theme? theme;

  bool get hasTheme => theme != null;

  /// **Rebindable** keys for nudging the selected widget in the Theme Maker's
  /// Arrange canvas. Held here so the choice persists across navigation. Default
  /// = the arrow keys; the user can remap each direction to any key.
  final Map<String, LogicalKeyboardKey> nudgeKeys = <String, LogicalKeyboardKey>{
    'up': LogicalKeyboardKey.arrowUp,
    'down': LogicalKeyboardKey.arrowDown,
    'left': LogicalKeyboardKey.arrowLeft,
    'right': LogicalKeyboardKey.arrowRight,
  };

  /// Rebind one nudge direction (`up`/`down`/`left`/`right`) to [key].
  void setNudgeKey(String dir, LogicalKeyboardKey key) {
    nudgeKeys[dir] = key;
    _persistSettings();
    notifyListeners();
  }

  /// Restore the default arrow-key nudge bindings.
  void resetNudgeKeys() {
    nudgeKeys
      ..['up'] = LogicalKeyboardKey.arrowUp
      ..['down'] = LogicalKeyboardKey.arrowDown
      ..['left'] = LogicalKeyboardKey.arrowLeft
      ..['right'] = LogicalKeyboardKey.arrowRight;
    _persistSettings();
    notifyListeners();
  }

  /// **Rebindable** single keys for the Button Studio's Manual framing flow
  /// (active only while the framing canvas is focused). Defaults are plain,
  /// obvious keys — **no `[` / `]` weirdness**: the arrow keys step sprites and
  /// Enter makes the current button & advances. Remap any of them from the F1
  /// "Keyboard shortcuts" dialog; rebinds **persist across app restarts** via
  /// [settings_store] (see [_persistSettings] / [_loadPersistedSettings]).
  static Map<String, LogicalKeyboardKey> _defaultFramingKeys() =>
      <String, LogicalKeyboardKey>{
        'prev': LogicalKeyboardKey.arrowLeft,
        'next': LogicalKeyboardKey.arrowRight,
        'make': LogicalKeyboardKey.enter,
        'reset': LogicalKeyboardKey.keyR,
        'all': LogicalKeyboardKey.keyA,
        'framing': LogicalKeyboardKey.keyF,
      };

  final Map<String, LogicalKeyboardKey> framingKeys = _defaultFramingKeys();

  /// Human labels for the framing actions, in display order (drives the rebind
  /// UI + the in-app hint so they can never drift from the real bindings).
  static const List<({String id, String label})> framingActions =
      <({String id, String label})>[
    (id: 'prev', label: 'Previous sprite'),
    (id: 'next', label: 'Next sprite'),
    (id: 'make', label: 'Make this button & go to next sprite'),
    (id: 'reset', label: 'Reset this sprite to auto'),
    (id: 'all', label: 'Apply this box to all sprites'),
    (id: 'framing', label: 'Cycle framing (Face / Full / Manual)'),
  ];

  /// Rebind one framing action (`prev`/`next`/`make`/`reset`/`all`/`framing`).
  void setFramingKey(String action, LogicalKeyboardKey key) {
    if (!framingKeys.containsKey(action)) return;
    framingKeys[action] = key;
    _persistSettings();
    notifyListeners();
  }

  /// Restore the default (arrow keys + Enter/R/A/F) framing bindings.
  void resetFramingKeys() {
    framingKeys
      ..clear()
      ..addAll(_defaultFramingKeys());
    _persistSettings();
    notifyListeners();
  }

  // --- Persistence of the rebindable keys (survives app restarts) ------------

  /// Load saved prefs (rebindable keys + user overlay presets) and apply them
  /// over the defaults. Keys are stored as integer `keyId`s. Best-effort.
  Future<void> _loadPersistedSettings() async {
    final Map<String, dynamic> s = await loadSettings();
    bool changed = false;
    changed |= _applySavedKeys(s['framingKeys'], framingKeys);
    changed |= _applySavedKeys(s['nudgeKeys'], nudgeKeys);
    changed |= _applySavedOverlayPresets(s['overlayPresets']);
    if (changed) notifyListeners();
  }

  /// Restore saved overlay presets (`[{name, spec}]`). Returns whether any
  /// loaded. Unknown styles (a preset saved by a newer build) are skipped.
  bool _applySavedOverlayPresets(Object? saved) {
    if (saved is! List) return false;
    bool changed = false;
    for (final Object? item in saved) {
      if (item is! Map) continue;
      final Object? name = item['name'];
      final Object? specJson = item['spec'];
      if (name is! String || specJson is! Map) continue;
      final OverlaySpec? spec =
          OverlaySpec.fromJson(specJson.cast<String, dynamic>());
      if (spec == null) continue;
      userOverlayPresets
          .removeWhere((({String name, OverlaySpec spec}) p) => p.name == name);
      userOverlayPresets.add((name: name, spec: spec));
      changed = true;
    }
    return changed;
  }

  /// Overlay saved `name -> keyId` pairs onto [target] (only known names),
  /// reconstructing each [LogicalKeyboardKey] from its id. Returns whether it
  /// changed anything.
  bool _applySavedKeys(Object? saved, Map<String, LogicalKeyboardKey> target) {
    if (saved is! Map) return false;
    bool changed = false;
    saved.forEach((Object? name, Object? id) {
      if (name is String && target.containsKey(name) && id is int) {
        // `findKeyByKeyId` returns the canonical known key (nicer label); the
        // `LogicalKeyboardKey(id)` fallback is enough on its own (equality +
        // keyLabel are keyId-based), so if `findKeyByKeyId` ever fails to
        // resolve, just drop it and keep the constructor.
        final LogicalKeyboardKey key =
            LogicalKeyboardKey.findKeyByKeyId(id) ?? LogicalKeyboardKey(id);
        if (target[name] != key) {
          target[name] = key;
          changed = true;
        }
      }
    });
    return changed;
  }

  /// Persist all session-surviving prefs in one write (framing + nudge keys +
  /// user overlay presets). Fire-and-forget; callers debounce by being rare.
  void _persistSettings() {
    saveSettings(<String, dynamic>{
      'framingKeys': <String, int>{
        for (final MapEntry<String, LogicalKeyboardKey> e
            in framingKeys.entries)
          e.key: e.value.keyId,
      },
      'nudgeKeys': <String, int>{
        for (final MapEntry<String, LogicalKeyboardKey> e in nudgeKeys.entries)
          e.key: e.value.keyId,
      },
      'overlayPresets': <Map<String, dynamic>>[
        for (final ({String name, OverlaySpec spec}) p in userOverlayPresets)
          <String, dynamic>{'name': p.name, 'spec': p.spec.toJson()},
      ],
    });
  }

  /// Start a fresh theme from the built-in starter layout.
  void newTheme() {
    theme = Ao2Theme.starter();
    status = 'Started a new theme.';
    notifyListeners();
  }

  /// Import an AO2 theme folder (its `relPath -> bytes`). Modeled inis/css become
  /// editable; images and everything else are preserved for lossless export.
  Future<void> importThemeFiles(Map<String, Uint8List> picked) async {
    if (picked.isEmpty) return;
    _setBusy(true, 'Importing theme…');
    final (String name, Map<String, Uint8List> files) =
        Ao2Theme.normalizePicked(picked);
    theme = Ao2Theme.fromFiles(name, files);
    _setBusy(
        false,
        'Imported theme "$name" — ${theme!.courtroom.elements.length} elements, '
        '${theme!.fonts.length} fonts, ${theme!.images.length} images.');
  }

  /// Randomise the current theme's colours/fonts. Returns the seed used.
  int randomizeTheme({
    bool colors = true,
    bool fonts = true,
    bool jitter = false,
    int? seed,
  }) {
    if (theme == null) return 0;
    final int s = ThemeRandomizer.randomize(theme!,
        colors: colors, fonts: fonts, jitterPositions: jitter, seed: seed);
    status = 'Randomised theme (seed $s).';
    notifyListeners();
    return s;
  }

  /// Replace (or clear, with null [bytes]) a theme image asset by file name.
  void setThemeImage(String fileName, Uint8List? bytes, {String ext = 'png'}) {
    if (theme == null) return;
    if (bytes == null) {
      theme!.images.remove(fileName);
    } else {
      theme!.images[fileName] = ThemeImage(fileName, bytes: bytes, ext: ext);
    }
    notifyListeners();
  }

  /// Notify after the Theme Maker mutates the model directly (lag-free editing).
  void touchTheme() => notifyListeners();

  /// Build the theme into a `<name>/…` `.zip` ready to drop into AO2's
  /// `base/themes/`. Returns the saved path.
  Future<String?> exportTheme() async {
    if (theme == null) return null;
    _setBusy(true, 'Building theme…');
    final Map<String, Uint8List> files = theme!.buildFiles();
    final String folder =
        theme!.name.trim().isEmpty ? 'theme' : theme!.name.trim();
    final Archive archive = Archive();
    files.forEach((String rel, Uint8List bytes) {
      archive.addFile(ArchiveFile('$folder/$rel', bytes.length, bytes));
    });
    final List<int>? zip = ZipEncoder().encode(archive);
    _setBusy(false, 'Theme "$folder" built (${files.length} files).');
    if (zip == null) return null;
    return saveBytes('$folder.zip', Uint8List.fromList(zip));
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// An [Organizer] wired to the studio's offsets + overlays. Buttons and the
  /// icon get their own renderer so each can carry a different (or no) border.
  /// Shared by single export ([buildOutput]) and [bulkBuildCharacters].
  Organizer _studioOrganizer() => Organizer(
        buttonRenderer: (Uint8List b, String e, int s, CropFraming f, double z,
                String? spriteBase) =>
            ButtonMaker.renderAutoOverlaid(b, e, s,
                framing: f,
                zoom: z,
                offsetX: buttonOffsetX,
                offsetY: buttonOffsetY,
                // Each button uses its own sprite's overlay + box; an untouched
                // sprite (null) gets a plain button auto-framed in renderFramed.
                background: buttonOverlayImage(spriteBase, fg: false),
                foreground: buttonOverlayImage(spriteBase, fg: true),
                manualCrop:
                    f == CropFraming.manual ? buttonCropRaw(spriteBase) : null),
        iconRenderer: (Uint8List b, String e, int s, CropFraming f, double z,
                String? spriteBase) =>
            ButtonMaker.renderAutoOverlaid(b, e, s,
                framing: f,
                zoom: z,
                offsetX: iconOffsetX,
                offsetY: iconOffsetY,
                background: iconBg.image,
                foreground: iconFg.image,
                manualCrop: f == CropFraming.manual ? iconCrop : null),
      );

  /// The current button/char_icon studio settings as an [OrganizeConfig] for a
  /// character folder named [targetCharDir]. A fresh folder is built, so missing
  /// buttons/icon are always generated with these settings; any button or
  /// char_icon the user imported (or saved) is copied in first and kept as-is.
  OrganizeConfig _studioConfig({required String targetCharDir}) => OrganizeConfig(
        targetCharDir: targetCharDir,
        generateButtons: generateButtons,
        buttonSize: buttonSize,
        buttonFraming: buttonFraming,
        buttonZoom: buttonZoom,
        generateCharIcon: generateCharIcon,
        iconSize: iconSize,
        iconFraming: iconFraming,
        iconZoom: iconZoom,
        iconSourceEmote: iconSourceEmote,
      );

  /// [buildConfig] with its [BuildConfig.name] overridden (the rest of the
  /// auto-build heuristics are kept) — used to name each bulk-built character
  /// after its sub-folder.
  BuildConfig _buildConfigNamed(String name) => BuildConfig(
        name: name,
        showname: buildConfig.showname,
        side: buildConfig.side,
        blips: buildConfig.blips,
        chat: buildConfig.chat,
        scaling: buildConfig.scaling,
        defaultDeskMod: buildConfig.defaultDeskMod,
        treatBareAsPreanim: buildConfig.treatBareAsPreanim,
        guessSounds: buildConfig.guessSounds,
        preferredFirstNames: buildConfig.preferredFirstNames,
      );

  /// Organise into a tidy character folder (with auto buttons + ini) and return
  /// the resulting in-memory workspace.
  Future<MemoryWorkspace> buildOutput() async {
    final MemoryWorkspace out = MemoryWorkspace();
    if (character == null || scan == null) return out;
    await logCrash('buildOutput start: ${character!.emotes.length} emote(s)');
    await _studioOrganizer().organize(
      character: character!,
      scan: scan!,
      source: workspace,
      target: out,
      config: _studioConfig(targetCharDir: character!.options.name),
      onProgress: (int d, int t, String l) => _progress(d, t, l),
    );
    return out;
  }

  /// **Bulk-build many characters from one parent folder.** Each top-level
  /// sub-folder of [files] becomes its own AO-ready character (auto ini, copied
  /// sprites, and buttons + char_icon using the current Button Studio settings),
  /// and they're all packed into a single `.zip` ready to drop into AO's
  /// `characters/`. This is the "5 folders of sprites → 5 characters in one
  /// click" workflow.
  ///
  /// A sub-folder that already contains a `char.ini` is honoured (parsed, not
  /// rebuilt); otherwise the auto-builder runs with the current [buildConfig],
  /// naming the character after the sub-folder. Sub-folders with no sprites (and
  /// no ini) are skipped. The current project is left untouched — bulk runs in
  /// throwaway in-memory workspaces. Returns the number of characters built.
  Future<int> bulkBuildCharacters(List<PickedFile> files) async {
    if (files.isEmpty) return 0;
    final Map<String, Uint8List> all = <String, Uint8List>{
      for (final PickedFile f in files) f.name: f.bytes,
    };
    final List<FolderCharacter> chars = BulkFolders.split(all.keys);
    if (chars.isEmpty) {
      _setBusy(false, 'No folders found to build.');
      return 0;
    }
    _setBusy(true, 'Bulk-building ${chars.length} character(s)…');

    final Organizer organizer = _studioOrganizer();
    final MemoryWorkspace out = MemoryWorkspace();
    int built = 0;
    int skipped = 0; // sub-folders with no sprites/ini
    int failed = 0; // sub-folders that threw while building
    String? lastError;
    for (final FolderCharacter fc in chars) {
      // Each character is isolated: a bad sprite or a malformed sub-folder must
      // NOT abort the whole batch (the old code had no try/catch, so a single
      // odd folder silently killed every character + the .zip).
      try {
        // A throwaway workspace holding just this character's sprites.
        final MemoryWorkspace src = MemoryWorkspace();
        fc.files.forEach((String inner, String key) {
          final Uint8List? bytes = all[key];
          if (bytes != null) src.put(Workspace.norm(inner), bytes);
        });
        final List<String> innerFiles = await src.listFiles();
        final ScanResult charScan = _scanner.fromPaths(innerFiles);

        // Honour an existing char.ini in the sub-folder; else auto-build.
        final String? iniRel = innerFiles.firstWhereOrNull(
            (String f) => p.basename(f).toLowerCase() == CharFolder.iniName);
        if (iniRel == null && charScan.groups.isEmpty) {
          skipped++; // nothing usable in this sub-folder
          _progress(built + skipped + failed, chars.length, 'Skipped ${fc.name}');
          continue;
        }
        final Character builtChar = iniRel != null
            ? Character.parse(await src.readString(iniRel))
            : const CharacterBuilder()
                .build(charScan, config: _buildConfigNamed(fc.name));

        await organizer.organize(
          character: builtChar,
          scan: charScan,
          source: src,
          target: out,
          config: _studioConfig(targetCharDir: fc.name),
          onProgress: (int d, int t, String l) =>
              _progress(built + 1, chars.length, 'Building ${fc.name}'),
        );
        built++;
        _progress(built, chars.length, 'Built ${fc.name}');
      } catch (e) {
        failed++;
        lastError = '${fc.name}: $e';
      }
      await Future<void>.delayed(Duration.zero);
    }

    if (built == 0) {
      // Be specific so an empty result is diagnosable, not a black box.
      final String why = failed > 0
          ? '$failed folder(s) failed to build (${lastError ?? 'unknown error'})'
          : 'detected ${chars.length} folder(s) but none had sprites or a char.ini'
              ' — make sure each character\'s sprites are *inside* its sub-folder';
      _setBusy(false, 'Bulk build produced nothing: $why.');
      return 0;
    }

    // One zip with every character folder.
    final Archive archive = Archive();
    out.snapshot.forEach((String rel, Uint8List bytes) {
      archive.addFile(ArchiveFile(rel, bytes.length, bytes));
    });
    final List<int>? zip = ZipEncoder().encode(archive);
    final String extra = <String>[
      if (skipped > 0) '$skipped skipped (empty)',
      if (failed > 0) '$failed failed',
    ].join(', ');
    _setBusy(
        false,
        'Bulk-built $built/${chars.length} character(s) into one .zip'
        '${extra.isEmpty ? '' : ' — $extra'}.');
    if (zip != null) {
      await saveBytes('characters.zip', Uint8List.fromList(zip));
    }
    return built;
  }

  /// Build the character and download/save it as a `.zip` ready to drop into AO.
  Future<String?> exportZip() async {
    _setBusy(true, 'Building character…');
    final MemoryWorkspace out = await buildOutput();
    final Archive archive = Archive();
    out.snapshot.forEach((String rel, Uint8List bytes) {
      archive.addFile(ArchiveFile(rel, bytes.length, bytes));
    });
    final List<int>? zip = ZipEncoder().encode(archive);
    _setBusy(false, 'Character built.');
    if (zip == null) return null;
    final String name = '${character?.options.name ?? 'character'}.zip';
    return saveBytes(name, Uint8List.fromList(zip));
  }

  /// Build the character and write it into a **plain folder** the user picks —
  /// no zip, so the finished character folder just *appears* on disk (DRO/KFO
  /// button-maker style) ready to drop into AO's `characters/`. Native desktop
  /// only; on web (no filesystem) it transparently falls back to [exportZip].
  Future<String?> exportFolder() async {
    if (character == null) return null;
    _setBusy(true, 'Building character…');
    final MemoryWorkspace out = await buildOutput();
    final String? dir = await exportToFolder(out.snapshot);
    if (dir != null) {
      _setBusy(false, 'Saved the character folder to $dir.');
      return dir;
    }
    // Null = cancelled, or this platform can't write a folder (web). On web,
    // give them the .zip instead of a silent no-op.
    if (kIsWeb) {
      _setBusy(false, 'Folders aren\'t supported on the web build — saving a .zip instead.');
      return exportZip();
    }
    _setBusy(false, 'Folder export cancelled.');
    return null;
  }

  /// Save just the char.ini.
  Future<String?> exportIni() async {
    if (character == null) return null;
    final Uint8List bytes = Uint8List.fromList(character!.serialize().codeUnits);
    return saveBytes(CharFolder.iniName, bytes);
  }

  // ---------------------------------------------------------------------------
  // helpers
  // ---------------------------------------------------------------------------

  /// Drop cached decoded frames + encoded previews and signal that sprite pixels
  /// or paths changed (so previews reload). Call this instead of clearing the
  /// decode cache directly whenever sprite files are written/moved.
  void _invalidateImageCaches() {
    _decodeCache.clear();
    _buttonSrcCache.clear();
    _previewCache.clear();
    _thumbCache.clear();
    _headSquareCache.clear();
    spriteRevision++;
  }

  void _setBusy(bool b, String msg) {
    busy = b;
    status = msg;
    notifyListeners();
  }

  void _progress(int done, int total, String label) {
    status = '$label  $done/$total';
    notifyListeners();
  }
}

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final E e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

/// Sendable job for [_bulkAnimateWorker]: one sprite's animation parameters.
class _AnimJob {
  const _AnimJob({
    required this.bytes,
    required this.ext,
    required this.recipes,
    required this.frames,
    required this.fps,
    required this.lossless,
    required this.quality,
  });
  final Uint8List bytes;
  final String ext;
  final List<Map<String, dynamic>> recipes;
  final int frames;
  final int fps;
  final bool lossless;
  final int quality;
}

/// Off-main-isolate worker for [AppState.bulkAnimateAll] (runs via `compute` on
/// native; inline on web): decode → render the effect stack → encode one
/// sprite's animation as WebP (APNG fallback). Top-level so `compute` can call
/// it. Built-in recipes only — plugin-registered recipe types don't exist in
/// the worker isolate, but the effect chips that feed bulk-animate are all
/// built in.
Future<({Uint8List bytes, String ext, String? webpError})> _bulkAnimateWorker(
    _AnimJob job) async {
  final img.Image? base = Codecs.decodeFirstFrame(job.bytes, ext: job.ext);
  if (base == null) {
    return (bytes: Uint8List(0), ext: 'none', webpError: 'could not decode sprite');
  }
  final List<AnimRecipe> recipes =
      job.recipes.map(AnimRecipe.fromJson).toList();
  final AnimClip clip =
      AnimEngine.render(base, recipes, frames: job.frames, fps: job.fps);
  return clip.encodePreferWebp(lossless: job.lossless, quality: job.quality);
}

/// Sendable job for [_mouthWorker]: one sprite's talking-mouth parameters. The
/// mouth box is auto-placed from each sprite's own face inside the worker.
class _MouthJob {
  const _MouthJob({
    required this.bytes,
    required this.ext,
    required this.frames,
    required this.fps,
    required this.openAmount,
    required this.style,
    required this.shape,
    required this.lossless,
    required this.quality,
  });
  final Uint8List bytes;
  final String ext;
  final int frames;
  final int fps;
  final double openAmount;
  final TalkStyle style;
  final MouthShape? shape;
  final bool lossless;
  final int quality;
}

/// Off-main-isolate worker for [AppState.bulkMouthTalkAll]: decode → fake a
/// talking mouth (face-derived region) → encode WebP (APNG fallback). Top-level
/// so `compute` can call it.
Future<({Uint8List bytes, String ext, String? webpError})> _mouthWorker(
    _MouthJob job) async {
  final img.Image? base = Codecs.decodeFirstFrame(job.bytes, ext: job.ext);
  if (base == null) {
    return (bytes: Uint8List(0), ext: 'none', webpError: 'could not decode sprite');
  }
  final AnimClip clip = LipSync.talkStyled(base, job.style,
      frames: job.frames,
      fps: job.fps,
      openAmount: job.openAmount,
      shape: job.shape);
  return clip.encodePreferWebp(lossless: job.lossless, quality: job.quality);
}
