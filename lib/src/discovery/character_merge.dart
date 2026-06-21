/// Merge several **complete** Attorney Online characters into **one** — so two
/// (or more) correct character folders become a single character whose emote
/// list is their union, whose buttons still point at the right sprites, and
/// whose colliding file names are restructured (renamed) so nothing clobbers
/// anything.
///
/// The hard part of a character merge is that an AO character folder mixes three
/// *different* naming schemes that all have to stay consistent:
///  * **Sprites** are referenced by the emote's `sprite` base (`(a)<base>`,
///    `(b)<base>`, `(c)<base>`, `<base>` static). Two characters can both define
///    `(a)normal.webp` with *different* art.
///  * **Buttons** (`emotions/buttonN_*.png`) are keyed by the emote's **1-based
///    position**, not by the sprite name — so concatenating emote lists shifts
///    every secondary button's number.
///  * **Preanims** (`anim/…`) and bundled **sounds** are referenced by name too.
///
/// [CharacterMerge.merge] keeps all three consistent:
///  1. The **primary** (the first source) keeps its identity — `[Options]`,
///     `[Options2-5]`, `[Shouts]`, `[Time]`, unknown sections and its
///     `char_icon.png`. (Those are single-instance per character; a merge can't
///     keep two. Every secondary section that is therefore *not* carried is
///     recorded in [MergeReport.losses] — nothing is dropped silently.)
///  2. Each source's emotes are appended (as copies, so the originals are
///     untouched), and `Character.serialize()` then renumbers `[Emotions]` and
///     every `SoundN/SoundT/SoundL/SoundB/Videos/OptionsN` line for free.
///  3. A sprite **base** whose files would overwrite an already-placed file with
///     *different bytes* is renamed (`normal` → `normal_2`); **all** of that
///     base's files are renamed in lockstep and that source's emote `sprite`
///     fields + frame-effect section names are updated to match. Byte-identical
///     collisions are de-duplicated (kept once, no rename).
///  4. Buttons are renumbered positionally so they stay glued to their emote.
///
/// Pure Dart (no Flutter), so it stays testable and identical on every target —
/// it operates on in-memory `relPath → bytes` maps, not the filesystem.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/ao_constants.dart';
import '../core/ao_ini.dart';
import '../core/character.dart';
import '../core/emote.dart';
import '../core/frame_effect.dart';
import 'sprite_scanner.dart';

/// One character to merge: its parsed [Character] and its folder files (paths
/// **relative to the character folder** → bytes). The `char.ini` itself is
/// modelled by [character] and need not appear in [files].
class MergeSource {
  MergeSource(this.label, this.character, this.files);

  /// A human label (folder / character name) for the report.
  final String label;

  final Character character;

  /// Sprites, buttons, `char_icon.png`, audio and any other folder files, keyed
  /// by their path relative to the character folder (`/`-separated).
  final Map<String, Uint8List> files;
}

/// What a [CharacterMerge.merge] did — drives the status line, and makes every
/// rename and every *un-merged* secondary section visible (so a merge can never
/// quietly lose data).
class MergeReport {
  MergeReport();

  /// The primary character's label (its identity is what the merged file keeps).
  String primary = '';

  int sources = 0;
  int emotes = 0;
  int renamedSprites = 0;
  int renamedPreanims = 0;
  int renamedSounds = 0;
  int renumberedButtons = 0;

  /// Byte-identical files at the same path, kept once (harmless de-dupe).
  int droppedDuplicates = 0;

  /// *Different* files that wanted the same chrome path (e.g. two `char_icon.png`
  /// or two `objection.png`): the primary's was kept, the secondary's dropped.
  int conflictsKeptPrimary = 0;

  /// Human-readable rename / conflict lines.
  final List<String> notes = <String>[];

  /// Secondary data that a single merged character can't carry (a second
  /// `[Shouts]`, `[Options2-5]`, etc.) — surfaced so the loss is never silent.
  final List<String> losses = <String>[];

  bool get hasLosses => losses.isNotEmpty;

  String get summary {
    final List<String> parts = <String>[
      'Merged $sources characters into "$primary" → $emotes emote(s)',
      if (renamedSprites > 0) '$renamedSprites sprite(s) renamed',
      if (renamedPreanims > 0) '$renamedPreanims preanim(s) renamed',
      if (renamedSounds > 0) '$renamedSounds sound(s) renamed',
      if (renumberedButtons > 0) '$renumberedButtons button(s) renumbered',
      if (conflictsKeptPrimary > 0)
        '$conflictsKeptPrimary conflicting file(s) kept from the primary',
      if (losses.isNotEmpty) '${losses.length} secondary section(s) not carried',
    ];
    return '${parts.join('; ')}.';
  }
}

/// The merged character plus its complete folder (incl. the rewritten
/// `char.ini`), ready to zip or write to disk.
class MergeResult {
  MergeResult(this.character, this.files, this.report);

  final Character character;

  /// Merged folder: path **relative to the character folder** → bytes, including
  /// `char.ini`.
  final Map<String, Uint8List> files;

  final MergeReport report;
}

/// Merges complete AO characters into one. See the library doc for the rules.
class CharacterMerge {
  const CharacterMerge._();

  /// `emotions/buttonN_on.png` / `…_off.png` — buttons are keyed by emote
  /// position, so they're renumbered, not name-matched.
  static final RegExp _buttonRe =
      RegExp(r'^emotions/button(\d+)_(on|off)\.png$', caseSensitive: false);

  /// Merge [sources] (primary first) into a single character. The primary keeps
  /// its identity; later sources contribute their emotes + art.
  static MergeResult merge(List<MergeSource> sources) {
    final MergeReport report = MergeReport()..sources = sources.length;
    final Character merged = Character();
    final Map<String, Uint8List> out = <String, Uint8List>{};

    if (sources.isEmpty) {
      out[CharFolder.iniName] = _bytesOf(merged.serialize());
      return MergeResult(merged, out, report);
    }

    final MergeSource primary = sources.first;
    report.primary = primary.label;
    _copyPrimaryIdentity(merged, primary.character);

    for (int si = 0; si < sources.length; si++) {
      final MergeSource src = sources[si];
      final bool isPrimary = si == 0;
      final int emoteOffset = merged.emotes.length;
      final ScanResult scan = const SpriteScanner().fromPaths(src.files.keys);

      // Original relPaths consumed as sprites/preanims, so the buttons/audio/
      // chrome pass below can skip them.
      final Set<String> handled = <String>{};

      // --- 1) Sprites: resolve a per-base rename on byte-collision, place files.
      final Map<String, String> spriteRename = <String, String>{}; // old→new base
      for (final SpriteGroup g in scan.groups) {
        if (g.base.isEmpty) continue;
        final List<SpriteFile> gfiles = _groupFiles(g);
        final String oldLeaf = _leafOf(g.base);
        final ({String newBase, bool renamed}) r =
            _resolveBaseRename(g.base, oldLeaf, gfiles, src.files, out);
        if (r.renamed) {
          spriteRename[g.base] = r.newBase;
          report.renamedSprites++;
          report.notes.add(
              '${src.label}: sprite "${g.base}" → "${r.newBase}" (name clash)');
        }
        final String newLeaf = _leafOf(r.newBase);
        for (final SpriteFile f in gfiles) {
          final String newRel =
              r.renamed ? _renameRel(f.relPath, oldLeaf, newLeaf) : f.relPath;
          out[newRel] = src.files[f.relPath]!;
          handled.add(f.relPath);
        }
      }

      // --- 2) Preanims (anim/…): rename on byte-collision; remember the leaf
      // swap so emote `preanim` fields can follow.
      final Map<String, String> preanimLeaf = <String, String>{}; // old→new leaf
      for (final SpriteFile f in scan.preanimCandidates) {
        final Uint8List bytes = src.files[f.relPath]!;
        final String oldLeaf = _leafOf(_stripExt(f.relPath));
        final ({String newRel, bool renamed}) r =
            _resolveFileRename(f.relPath, oldLeaf, bytes, out);
        if (r.renamed) {
          final String newLeaf = _leafOf(_stripExt(r.newRel));
          preanimLeaf[oldLeaf] = newLeaf;
          report.renamedPreanims++;
          report.notes
              .add('${src.label}: preanim "$oldLeaf" → "$newLeaf" (name clash)');
        }
        out[r.newRel] = bytes;
        handled.add(f.relPath);
      }

      // --- 3) Buttons / audio / chrome.
      final Map<String, String> soundLeaf = <String, String>{}; // old→new leaf
      for (final String rel in src.files.keys) {
        if (handled.contains(rel)) continue;
        final Uint8List bytes = src.files[rel]!;
        final String low = rel.toLowerCase();

        // Button → renumber positionally (offset by the emotes already merged).
        final Match? bm = _buttonRe.firstMatch(low);
        if (bm != null) {
          final int k = int.parse(bm.group(1)!);
          final bool on = bm.group(2) == 'on';
          out['${CharFolder.emotionsDir}/'
              '${CharFolder.buttonName(emoteOffset + k, on: on)}'] = bytes;
          // The primary's buttons keep their number (offset 0); only a shifted
          // button counts as "renumbered".
          if (emoteOffset > 0) report.renumberedButtons++;
          continue;
        }

        // Bundled audio → rename on byte-collision; remember the leaf swap.
        if (kAudioExtensions.contains(_stripDot(_ext(rel)))) {
          final String oldLeaf = _leafOf(_stripExt(rel));
          final ({String newRel, bool renamed}) r =
              _resolveFileRename(rel, oldLeaf, bytes, out);
          if (r.renamed) {
            soundLeaf[oldLeaf] = _leafOf(_stripExt(r.newRel));
            report.renamedSounds++;
            report.notes.add(
                '${src.label}: sound "$oldLeaf" → "${soundLeaf[oldLeaf]}" (name clash)');
          }
          out[r.newRel] = bytes;
          continue;
        }

        // Everything else is chrome (char_icon, custom objection art, credits…):
        // the primary wins. Identical dupes vanish; different files at a taken
        // path keep the primary's and are reported (never silent).
        final Uint8List? existing = out[rel];
        if (existing == null) {
          out[rel] = bytes;
        } else if (_bytesEqual(existing, bytes)) {
          report.droppedDuplicates++;
        } else {
          report.conflictsKeptPrimary++;
          report.notes
              .add('${src.label}: kept the primary\'s "$rel" (both define it)');
        }
      }

      // --- 4) Emotes (copies, refs updated for any rename above).
      for (final Emote e in src.character.emotes) {
        final Emote ne = e.copy();
        final String? rb = spriteRename[ne.sprite];
        if (rb != null) ne.sprite = rb;
        if (ne.preanim != kNoPreanim && ne.preanim.isNotEmpty) {
          final String leaf = _leafOf(ne.preanim);
          final String? nl = preanimLeaf[leaf];
          if (nl != null) ne.preanim = _replaceTrailingLeaf(ne.preanim, leaf, nl);
        }
        if (ne.soundName != null && ne.soundName!.isNotEmpty) {
          final String ext = _ext(ne.soundName!);
          final String noExt = _stripExt(ne.soundName!);
          final String? nl = soundLeaf[_leafOf(noExt)];
          if (nl != null) {
            ne.soundName =
                _replaceTrailingLeaf(noExt, _leafOf(noExt), nl) + ext;
          }
        }
        // Alt-option blocks aren't merged (the primary's win), so a secondary
        // emote that pointed at one falls back to the default — surfaced.
        if (!isPrimary && ne.optionsBlock != null) {
          report.losses.add('${src.label}: emote "${ne.comment}" used '
              '[Options${ne.optionsBlock}] (alt-option blocks aren\'t merged)');
          ne.optionsBlock = null;
        }
        merged.emotes.add(ne);
      }

      // --- 5) Frame effects (re-keyed for any renamed sprite). The primary's
      // rename map is empty, so its sections pass through unchanged.
      for (final FrameEffectSet fx in src.character.frameEffects) {
        merged.frameEffects.add(FrameEffectSet(
          spriteRef: _remapSpriteRef(fx.spriteRef, spriteRename),
          kind: fx.kind,
          entries: <FrameEffectEntry>[
            for (final FrameEffectEntry en in fx.entries)
              FrameEffectEntry(en.frame, en.value),
          ],
        ));
      }

      // --- 6) Record the secondary single-instance sections we couldn't carry.
      if (!isPrimary) _noteSecondaryLosses(report, src);
    }

    report.emotes = merged.emotes.length;
    out[CharFolder.iniName] = _bytesOf(merged.serialize());
    return MergeResult(merged, out, report);
  }

  // ---------------------------------------------------------------------------
  // Identity / losses
  // ---------------------------------------------------------------------------

  /// Copy the primary's single-instance data (everything but emotes + frame
  /// effects, which are added per-source so renames apply uniformly).
  static void _copyPrimaryIdentity(Character merged, Character primary) {
    final CharacterOptions o = primary.options;
    merged.options
      ..name = o.name
      ..showname = o.showname
      ..needsShowname = o.needsShowname
      ..side = o.side
      ..blips = o.blips
      ..chat = o.chat
      ..effects = o.effects
      ..realization = o.realization
      ..category = o.category
      ..scaling = o.scaling
      ..stretch = o.stretch;
    merged.options.extra
        .addAll(o.extra.map((IniEntry e) => IniEntry(e.key, e.value)));
    primary.alternateOptions.forEach((int k, List<IniEntry> v) {
      merged.alternateOptions[k] =
          v.map((IniEntry e) => IniEntry(e.key, e.value)).toList();
    });
    merged.shouts
        .addAll(primary.shouts.map((IniEntry e) => IniEntry(e.key, e.value)));
    merged.time
        .addAll(primary.time.map((IniEntry e) => IniEntry(e.key, e.value)));
    merged.soundLoopByName.addAll(
        primary.soundLoopByName.map((IniEntry e) => IniEntry(e.key, e.value)));
    // Unknown sections are written verbatim and never mutated, so sharing the
    // refs is safe.
    merged.unknownSections.addAll(primary.unknownSections);
  }

  static void _noteSecondaryLosses(MergeReport report, MergeSource src) {
    final Character c = src.character;
    void note(bool when, String what) {
      if (when) report.losses.add('${src.label}: $what');
    }

    note(c.shouts.isNotEmpty, '[Shouts] not merged (kept the primary\'s)');
    note(c.alternateOptions.isNotEmpty,
        '[Options ${c.alternateOptions.keys.join('/')}] not merged');
    note(c.time.isNotEmpty, '[Time] not merged');
    note(c.soundLoopByName.isNotEmpty, 'named [SoundL] loop(s) not merged');
    note(c.options.extra.isNotEmpty,
        '${c.options.extra.length} custom [Options] key(s) not merged');
    for (final IniSectionData s in c.unknownSections) {
      report.losses.add('${src.label}: section [${s.name}] not merged');
    }
  }

  // ---------------------------------------------------------------------------
  // Collision resolution
  // ---------------------------------------------------------------------------

  /// Find a base name for [base] whose every file is either free or byte-equal in
  /// [out]. Tries the original first (no rename / de-dupe), then `<leaf>_2`,
  /// `<leaf>_3`, … until all of the group's files land cleanly.
  static ({String newBase, bool renamed}) _resolveBaseRename(
    String base,
    String oldLeaf,
    List<SpriteFile> files,
    Map<String, Uint8List> src,
    Map<String, Uint8List> out,
  ) {
    for (int attempt = 0;; attempt++) {
      final String newLeaf = attempt == 0 ? oldLeaf : '${oldLeaf}_${attempt + 1}';
      final String newBase =
          attempt == 0 ? base : _replaceTrailingLeaf(base, oldLeaf, newLeaf);
      bool ok = true;
      for (final SpriteFile f in files) {
        final String newRel =
            attempt == 0 ? f.relPath : _renameRel(f.relPath, oldLeaf, newLeaf);
        final Uint8List? existing = out[newRel];
        if (existing != null && !_bytesEqual(existing, src[f.relPath]!)) {
          ok = false;
          break;
        }
      }
      if (ok) return (newBase: newBase, renamed: attempt != 0);
    }
  }

  /// Single-file variant (preanims / bundled audio): the original path if free or
  /// byte-equal, else `<leaf>_2`, `<leaf>_3`, …
  static ({String newRel, bool renamed}) _resolveFileRename(
    String rel,
    String oldLeaf,
    Uint8List bytes,
    Map<String, Uint8List> out,
  ) {
    for (int attempt = 0;; attempt++) {
      final String newRel = attempt == 0
          ? rel
          : _renameRel(rel, oldLeaf, '${oldLeaf}_${attempt + 1}');
      final Uint8List? existing = out[newRel];
      if (existing == null || _bytesEqual(existing, bytes)) {
        return (newRel: newRel, renamed: attempt != 0);
      }
    }
  }

  /// Re-key a frame-effect `spriteRef` (e.g. `(a)Happy`, `(b)/def/think`) when its
  /// underlying sprite base was renamed. Matched by the *full* base, not just the
  /// leaf, so `arm` can't accidentally rewrite `forearm`.
  static String _remapSpriteRef(String ref, Map<String, String> rename) {
    if (rename.isEmpty) return ref;
    final String base = _spriteRefToBase(ref);
    final String? nb = rename[base];
    if (nb == null) return ref;
    return _replaceTrailingLeaf(ref, _leafOf(base), _leafOf(nb));
  }

  // ---------------------------------------------------------------------------
  // Path helpers (mirror SpriteScanner's base normalisation)
  // ---------------------------------------------------------------------------

  static List<SpriteFile> _groupFiles(SpriteGroup g) => <SpriteFile>[
        if (g.idle != null) g.idle!,
        if (g.talk != null) g.talk!,
        if (g.post != null) g.post!,
        ...g.statics,
      ];

  /// Strip a leading `(a)`/`(b)`/`(c)` then normalise like the scanner (subfolder
  /// bases carry a leading `/`).
  static String _spriteRefToBase(String ref) {
    String r = ref;
    for (final String pfx in SpritePrefix.all) {
      if (r.startsWith(pfx)) {
        r = r.substring(pfx.length);
        break;
      }
    }
    if (r.startsWith('/')) return r;
    if (r.contains('/')) return '/$r';
    return r;
  }

  static String _leafOf(String base) {
    final int i = base.lastIndexOf('/');
    return i < 0 ? base : base.substring(i + 1);
  }

  /// Replace the trailing [oldLeaf] of [s] with [newLeaf]. Only used where [s] is
  /// already known to end with [oldLeaf] at a path/prefix boundary.
  static String _replaceTrailingLeaf(String s, String oldLeaf, String newLeaf) {
    if (oldLeaf.isEmpty || !s.endsWith(oldLeaf)) return s;
    return s.substring(0, s.length - oldLeaf.length) + newLeaf;
  }

  /// Swap the trailing leaf of a file path, keeping its directory + extension:
  /// `(a)normal.webp` + (`normal`→`normal_2`) ⇒ `(a)normal_2.webp`.
  static String _renameRel(String rel, String oldLeaf, String newLeaf) {
    final String ext = _ext(rel);
    final String noExt = ext.isEmpty ? rel : rel.substring(0, rel.length - ext.length);
    return _replaceTrailingLeaf(noExt, oldLeaf, newLeaf) + ext;
  }

  /// Extension *including* the dot (`.webp`), or `''`. Ignores dots in folders.
  static String _ext(String rel) {
    final int slash = rel.lastIndexOf('/');
    final int dot = rel.lastIndexOf('.');
    return dot <= slash ? '' : rel.substring(dot);
  }

  static String _stripExt(String rel) {
    final String e = _ext(rel);
    return e.isEmpty ? rel : rel.substring(0, rel.length - e.length);
  }

  static String _stripDot(String ext) =>
      (ext.startsWith('.') ? ext.substring(1) : ext).toLowerCase();

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Uint8List _bytesOf(String s) => Uint8List.fromList(utf8.encode(s));
}
