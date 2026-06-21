import 'dart:typed_data';

import '../core/ao_constants.dart';
import '../core/character.dart';
import '../platform/workspace.dart';
import 'sprite_scanner.dart';

/// Renders a square button / char-icon from a source image's first frame, with
/// the requested [CropFraming] (head/face vs full body) and head-crop [zoom].
/// Returns null if it cannot produce one. Injected from the imaging layer so the
/// organiser has no hard dependency on the image engine.
///
/// [spriteBase] is the emote's `sprite` base name, passed so the renderer can
/// look up a **per-sprite** manual crop box (Button Studio "Manual" mode). It's
/// `null` for the char_icon (which carries its own single box).
typedef ButtonRenderer = Future<Uint8List?> Function(
  Uint8List sourceBytes,
  String ext,
  int size,
  CropFraming framing,
  double zoom,
  String? spriteBase,
);

/// Progress callback: (completed, total, label).
typedef ProgressCallback = void Function(int done, int total, String label);

/// Options for an organise/export run.
class OrganizeConfig {
  const OrganizeConfig({
    this.targetCharDir,
    this.deleteOriginals = false,
    this.generateButtons = true,
    this.buttonSize = CharFolder.defaultButtonSize,
    this.buttonFraming = CropFraming.head,
    this.buttonZoom = 1.0,
    this.overwriteExistingButtons = false,
    this.generateCharIcon = true,
    this.iconSize = CharFolder.defaultIconSize,
    this.iconFraming = CropFraming.head,
    this.iconZoom = 1.0,
    this.iconSourceEmote = 0,
  });

  /// Where the character folder goes inside the target workspace. Defaults to
  /// the character's `name`.
  final String? targetCharDir;

  /// Move (delete source after copy) instead of copy. Only honoured when source
  /// and target are the same workspace.
  final bool deleteOriginals;

  /// Generate `emotions/buttonN_off.png` for every emote.
  final bool generateButtons;
  final int buttonSize;

  /// How buttons frame each sprite (head/face by default).
  final CropFraming buttonFraming;

  /// Head-crop zoom for buttons (see [ButtonRenderer]).
  final double buttonZoom;

  /// When false, an existing button / char_icon already in the target is kept.
  final bool overwriteExistingButtons;

  /// Generate a `char_icon.png` for the character-select screen.
  final bool generateCharIcon;

  /// char_icon edge in px (40–128; see [CharFolder]).
  final int iconSize;

  /// How the char_icon frames the sprite (head/face by default).
  final CropFraming iconFraming;

  /// Head-crop zoom for the char_icon.
  final double iconZoom;

  /// Which emote (0-based) the char_icon is rendered from. Clamped, and if that
  /// emote has no sprite the next emote with one is used.
  final int iconSourceEmote;
}

/// A single planned file relocation.
class FileOp {
  FileOp(this.fromRel, this.toRel);
  final String fromRel;
  final String toRel;
}

/// A single planned button to render.
class ButtonJob {
  ButtonJob({
    required this.emoteIndex,
    required this.sourceRel,
    required this.targetRel,
    this.spriteBase,
  });
  final int emoteIndex; // 0-based
  final String sourceRel; // within target workspace, after files are copied
  final String targetRel;

  /// The emote's sprite base name — handed to the [ButtonRenderer] so it can
  /// apply this sprite's own manual crop box. Null when unknown.
  final String? spriteBase;
}

/// The full, inspectable plan produced before anything touches the workspace.
class OrganizePlan {
  OrganizePlan(this.charDir);
  final String charDir;
  final List<FileOp> fileOps = <FileOp>[];
  final List<ButtonJob> buttonJobs = <ButtonJob>[];
  late String iniRel;
  String? iniText;

  /// Where the generated `char_icon.png` goes (null if not generating one or no
  /// usable source sprite was found).
  String? iconRel;

  /// The (already-copied) sprite the char_icon is rendered from.
  String? iconSourceRel;
}

/// Builds and executes a plan that turns scanned sprites + a built [Character]
/// into a tidy, AO-ready character folder.
class Organizer {
  const Organizer({this.buttonRenderer, this.iconRenderer});

  final ButtonRenderer? buttonRenderer;

  /// Renderer for the `char_icon.png`. Falls back to [buttonRenderer] when null,
  /// so callers only set this when the icon needs *different* overlays/framing
  /// than the buttons (e.g. a different border, or no border at all).
  final ButtonRenderer? iconRenderer;

  /// Compute the plan without performing any writes.
  OrganizePlan plan({
    required Character character,
    required ScanResult scan,
    required List<String> sourceFiles,
    OrganizeConfig config = const OrganizeConfig(),
  }) {
    final String charDir =
        Workspace.norm(config.targetCharDir ?? character.options.name);
    final OrganizePlan plan = OrganizePlan(charDir);

    // Copy every source file into the character folder, preserving structure.
    // EXCEPT, when the studio is regenerating buttons/icon in **overwrite mode**,
    // skip carrying the imported `emotions/` buttons + `char_icon.png` — otherwise
    // stale imported art (often named for a different emote order) survives and
    // the freshly-framed buttons never appear ("override the emotions folder when
    // you load a folder"). With the default `overwriteExistingButtons:false`,
    // imported chrome is still copied + kept as before.
    for (final String rel in sourceFiles) {
      if (config.overwriteExistingButtons && _isRegeneratedChrome(rel, config)) {
        continue;
      }
      plan.fileOps.add(FileOp(rel, joinRel(charDir, rel)));
    }

    plan.iniRel = joinRel(charDir, CharFolder.iniName);
    plan.iniText = character.serialize();

    // Case/slash-tolerant so an imported char.ini whose `sprite=` casing differs
    // from the on-disk file names still finds its sprites (otherwise only the
    // exactly-matching emote gets a button — the "only one emotion exports" bug).
    final SpriteGroupIndex byBase = SpriteGroupIndex(scan.groups);

    /// The (target-relative) representative sprite for emote [i], or null.
    String? repRel(int i) {
      if (i < 0 || i >= character.emotes.length) return null;
      final SpriteFile? rep =
          byBase.resolve(character.emotes[i].sprite)?.representative;
      return rep == null ? null : joinRel(charDir, rep.relPath);
    }

    if (config.generateButtons) {
      for (int i = 0; i < character.emotes.length; i++) {
        final String? src = repRel(i);
        if (src == null) continue;
        plan.buttonJobs.add(ButtonJob(
          emoteIndex: i,
          sourceRel: src,
          spriteBase: character.emotes[i].sprite,
          targetRel: joinRel(
            charDir,
            '${CharFolder.emotionsDir}/${CharFolder.buttonName(i + 1, on: false)}',
          ),
        ));
      }
    }

    if (config.generateCharIcon && character.emotes.isNotEmpty) {
      // Prefer the chosen emote; if it has no sprite, fall back to the first
      // emote that does, so the icon is never blank.
      final int start = config.iconSourceEmote.clamp(0, character.emotes.length - 1);
      String? iconSrc;
      for (int k = 0; k < character.emotes.length; k++) {
        iconSrc = repRel((start + k) % character.emotes.length);
        if (iconSrc != null) break;
      }
      if (iconSrc != null) {
        plan.iconSourceRel = iconSrc;
        plan.iconRel = joinRel(charDir, CharFolder.charIcon);
      }
    }
    return plan;
  }

  /// True when [rel] is button/icon "chrome" the studio is about to regenerate
  /// (a file inside an `emotions/` folder when [OrganizeConfig.generateButtons],
  /// or a `char_icon.png` when [OrganizeConfig.generateCharIcon]) — so it can be
  /// skipped from the copy in overwrite mode instead of shadowing the fresh art.
  static bool _isRegeneratedChrome(String rel, OrganizeConfig config) {
    final List<String> segs = Workspace.norm(rel).split('/');
    if (config.generateButtons &&
        segs.any((String s) => s.toLowerCase() == CharFolder.emotionsDir)) {
      return true;
    }
    if (config.generateCharIcon &&
        segs.isNotEmpty &&
        segs.last.toLowerCase() == CharFolder.charIcon.toLowerCase()) {
      return true;
    }
    return false;
  }

  /// Execute a [plan]: copy/move files, write the ini, and render buttons.
  Future<void> execute(
    OrganizePlan plan, {
    required Workspace source,
    required Workspace target,
    OrganizeConfig config = const OrganizeConfig(),
    ProgressCallback? onProgress,
  }) async {
    final bool sameWs = identical(source, target);
    final int total = plan.fileOps.length +
        1 /* ini */ +
        plan.buttonJobs.length +
        (plan.iconRel != null ? 1 : 0);
    int done = 0;
    void tick(String label) => onProgress?.call(++done, total, label);

    for (final FileOp op in plan.fileOps) {
      final Uint8List bytes = await source.readBytes(op.fromRel);
      await target.writeBytes(op.toRel, bytes);
      if (config.deleteOriginals && sameWs && op.fromRel != op.toRel) {
        await source.delete(op.fromRel);
      }
      tick('Copied ${op.toRel}');
    }

    await target.writeString(plan.iniRel, plan.iniText ?? '');
    tick('Wrote ${plan.iniRel}');

    // Stamp every exported character with a Pinsel attribution file.
    await target.writeString(
      joinRel(plan.charDir, CharFolder.pinselCreditsFile),
      kPinselCreditsText,
    );

    if (buttonRenderer != null) {
      for (final ButtonJob job in plan.buttonJobs) {
        if (!config.overwriteExistingButtons &&
            await target.exists(job.targetRel)) {
          tick('Kept existing ${job.targetRel}');
          continue;
        }
        final Uint8List src = await target.readBytes(job.sourceRel);
        final String ext = job.sourceRel.split('.').last.toLowerCase();
        final Uint8List? png = await buttonRenderer!(src, ext, config.buttonSize,
            config.buttonFraming, config.buttonZoom, job.spriteBase);
        if (png != null) {
          await target.writeBytes(job.targetRel, png);
        }
        tick('Button ${job.emoteIndex + 1}');
        // Yield to the event loop between buttons. Each button render
        // (decode + face-detect + encode) is synchronous CPU work on the UI
        // isolate; with a big cast (e.g. 100 emotes) doing them back-to-back
        // blocks the thread long enough that the OS marks the app "not
        // responding" and the user force-closes it (looks like a crash). One
        // yield per button keeps the message pump + progress bar alive.
        await Future<void>.delayed(Duration.zero);
      }

      // char_icon.png for the character-select screen.
      if (plan.iconRel != null && plan.iconSourceRel != null) {
        final bool keepExisting = !config.overwriteExistingButtons &&
            await target.exists(plan.iconRel!);
        if (!keepExisting) {
          final Uint8List src = await target.readBytes(plan.iconSourceRel!);
          final String ext = plan.iconSourceRel!.split('.').last.toLowerCase();
          final ButtonRenderer render = iconRenderer ?? buttonRenderer!;
          // The icon carries its own single crop box, so no per-sprite key.
          final Uint8List? png = await render(
              src, ext, config.iconSize, config.iconFraming, config.iconZoom, null);
          if (png != null) await target.writeBytes(plan.iconRel!, png);
        }
        tick('char_icon');
      }
    }
  }

  /// One-shot convenience: plan + execute.
  Future<OrganizePlan> organize({
    required Character character,
    required ScanResult scan,
    required Workspace source,
    required Workspace target,
    OrganizeConfig config = const OrganizeConfig(),
    ProgressCallback? onProgress,
  }) async {
    final List<String> files = await source.listFiles();
    final OrganizePlan p = plan(
      character: character,
      scan: scan,
      sourceFiles: files,
      config: config,
    );
    await execute(p,
        source: source, target: target, config: config, onProgress: onProgress);
    return p;
  }
}
