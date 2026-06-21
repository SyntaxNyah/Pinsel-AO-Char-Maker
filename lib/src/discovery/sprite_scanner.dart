import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/ao_constants.dart';

/// Which animation role a file plays for its emote.
enum SpriteState { idle, talk, post, staticImage }

/// One image file discovered on disk, classified.
class SpriteFile {
  SpriteFile({
    required this.relPath,
    required this.ext,
    required this.state,
    required this.base,
  });

  /// Path relative to the character root, using `/`, *with* extension.
  final String relPath;

  /// Lower-case extension without the dot.
  final String ext;

  final SpriteState state;

  /// The emote `sprite` value this file contributes to (e.g. `Happy`,
  /// `/extrasprites/18`).
  final String base;

  bool get isAnimated => kAnimatedExtensions.contains(ext);

  int get _extPriority {
    final int i = kSpriteExtensionPriority.indexOf(ext);
    return i < 0 ? kSpriteExtensionPriority.length : i;
  }
}

/// All files that resolve to a single logical emote.
class SpriteGroup {
  SpriteGroup(this.base);

  /// The emote `sprite` field value.
  final String base;

  SpriteFile? idle;
  SpriteFile? talk;
  SpriteFile? post;

  /// Bare (prefix-less) files for this base. Usually a static sprite, but when
  /// an `(a)`/`(b)` pair also exists this is most likely a preanimation.
  final List<SpriteFile> statics = <SpriteFile>[];

  bool get hasDialogPair => idle != null || talk != null;
  bool get hasStatic => statics.isNotEmpty;

  bool get isAnimated =>
      (idle?.isAnimated ?? false) ||
      (talk?.isAnimated ?? false) ||
      statics.any((SpriteFile f) => f.isAnimated);

  /// The file the engine would render first for this emote (idle > talk > post
  /// > best static), used for previews and button generation.
  SpriteFile? get representative {
    if (idle != null) return idle;
    if (talk != null) return talk;
    if (post != null) return post;
    if (statics.isNotEmpty) return _bestStatic;
    return null;
  }

  SpriteFile? get _bestStatic {
    if (statics.isEmpty) return null;
    final List<SpriteFile> sorted = statics.toList()
      ..sort((SpriteFile a, SpriteFile b) =>
          a._extPriority.compareTo(b._extPriority));
    return sorted.first;
  }

  /// A nice default display name derived from the base.
  String get suggestedComment {
    final String leaf = base.split('/').where((String s) => s.isNotEmpty).last;
    return _humanize(leaf);
  }
}

/// The result of scanning a folder.
class ScanResult {
  ScanResult();

  final List<SpriteGroup> groups = <SpriteGroup>[];

  /// Files living under `anim/` (treated as preanimation candidates rather than
  /// emotes).
  final List<SpriteFile> preanimCandidates = <SpriteFile>[];

  /// Relative paths skipped because they are character chrome (char_icon, etc.)
  /// or live in ignored folders.
  final List<String> ignored = <String>[];

  bool get isEmpty => groups.isEmpty;
}

/// Turns a directory of loose images into classified [SpriteGroup]s, matching
/// the exact resolution rules of the AO2 reference client.
class SpriteScanner {
  const SpriteScanner();

  /// Scan a real character folder on disk.
  Future<ScanResult> scanDirectory(String charRoot) async {
    final Directory dir = Directory(charRoot);
    if (!dir.existsSync()) return ScanResult();
    final List<String> relPaths = <String>[];
    await for (final FileSystemEntity ent in dir.list(recursive: true)) {
      if (ent is! File) continue;
      final String rel =
          p.relative(ent.path, from: charRoot).replaceAll(r'\', '/');
      relPaths.add(rel);
    }
    return fromPaths(relPaths);
  }

  /// Pure, testable core: classify a list of relative paths.
  ScanResult fromPaths(Iterable<String> relPaths) {
    final ScanResult result = ScanResult();
    final Map<String, SpriteGroup> groups = <String, SpriteGroup>{};

    for (final String rawRel in relPaths) {
      final String rel = rawRel.replaceAll(r'\', '/');
      final String ext = p.extension(rel).replaceFirst('.', '').toLowerCase();
      if (!kImportableImageExtensions.contains(ext) &&
          ext != kStaticExtension) {
        continue;
      }
      if (_isIgnored(rel)) {
        result.ignored.add(rel);
        continue;
      }

      // `anim/...` files are preanimation candidates, not emotes.
      final String firstSeg = rel.split('/').first.toLowerCase();
      if (firstSeg == CharFolder.preanimDir) {
        result.preanimCandidates.add(SpriteFile(
          relPath: rel,
          ext: ext,
          state: SpriteState.staticImage,
          base: _stripExt(rel),
        ));
        continue;
      }

      final _Classified c = _classify(_stripExt(rel));
      final SpriteFile file = SpriteFile(
        relPath: rel,
        ext: ext,
        state: c.state,
        base: c.base,
      );
      final SpriteGroup g = groups.putIfAbsent(c.base, () => SpriteGroup(c.base));
      switch (c.state) {
        case SpriteState.idle:
          g.idle = _preferHigherPriority(g.idle, file);
        case SpriteState.talk:
          g.talk = _preferHigherPriority(g.talk, file);
        case SpriteState.post:
          g.post = _preferHigherPriority(g.post, file);
        case SpriteState.staticImage:
          g.statics.add(file);
      }
    }

    result.groups.addAll(groups.values);
    // Natural-ish ordering for predictable emote numbering.
    result.groups.sort((SpriteGroup a, SpriteGroup b) =>
        _natCompare(a.base.toLowerCase(), b.base.toLowerCase()));
    return result;
  }

  SpriteFile _preferHigherPriority(SpriteFile? existing, SpriteFile incoming) {
    if (existing == null) return incoming;
    return incoming._extPriority < existing._extPriority ? incoming : existing;
  }

  /// Given a relative path *without* extension, determine its state and base.
  _Classified _classify(String relNoExt) {
    for (final String prefix in <String>[
      SpritePrefix.idle,
      SpritePrefix.talk,
      SpritePrefix.post,
    ]) {
      if (relNoExt.startsWith(prefix)) {
        // Strip the bare prefix; what remains might begin with `/` (subfolder
        // mode, e.g. `(a)/def/thinking` -> base `/def/thinking`).
        final String base = relNoExt.substring(prefix.length);
        final SpriteState state = prefix == SpritePrefix.idle
            ? SpriteState.idle
            : prefix == SpritePrefix.talk
                ? SpriteState.talk
                : SpriteState.post;
        return _Classified(state, _normalizeBase(base));
      }
    }
    return _Classified(SpriteState.staticImage, _normalizeBase(relNoExt));
  }

  /// Subfolder bases are referenced with a leading `/` in the ini; root bases
  /// are not.
  String _normalizeBase(String base) {
    if (base.startsWith('/')) return base;
    if (base.contains('/')) return '/$base';
    return base;
  }

  bool _isIgnored(String rel) {
    final List<String> segs = rel.split('/');
    for (final String seg in segs) {
      if (CharFolder.ignoredScanDirs.contains(seg.toLowerCase())) return true;
    }
    final String baseLeaf = _stripExt(segs.last).toLowerCase();
    return CharFolder.ignoredScanBaseNames.contains(baseLeaf);
  }

  String _stripExt(String path) {
    final String ext = p.extension(path);
    return ext.isEmpty ? path : path.substring(0, path.length - ext.length);
  }
}

class _Classified {
  _Classified(this.state, this.base);
  final SpriteState state;
  final String base;
}

/// Case- and slash-tolerant `emote.sprite → SpriteGroup` resolver.
///
/// An emote's `sprite` field is matched against [SpriteGroup.base]. For a
/// character the app **auto-built**, this is always an exact match (the builder
/// sets `emote.sprite = group.base`). But for an **imported** `char.ini` the
/// `sprite` value is whatever the file's author typed, and the AO client resolves
/// the matching image files **case-insensitively** (and tolerates the subfolder
/// leading `/` being present or omitted). If resolution here required an exact
/// string match, an imported character whose ini casing differs from its on-disk
/// file names would silently lose **button generation and previews** for every
/// mismatched emote — the "only one emotion exports / char data deleted" bug,
/// because the exported `.zip` then contains a button for only the lone emote
/// whose casing happened to match.
///
/// [resolve] tries an **exact** match first — so a correct character is
/// byte-for-byte unaffected (no collisions, no behaviour change) — and only falls
/// back to a normalised (trimmed, `\`→`/`, lower-cased, leading-`/`-folded) match
/// when the exact lookup misses.
class SpriteGroupIndex {
  SpriteGroupIndex(Iterable<SpriteGroup> groups) {
    for (final SpriteGroup g in groups) {
      _exact[g.base] = g;
      // First-wins keeps the fallback deterministic if two bases fold together
      // (only possible on a case-sensitive filesystem — AO is ambiguous there too).
      _folded.putIfAbsent(foldBase(g.base), () => g);
    }
  }

  final Map<String, SpriteGroup> _exact = <String, SpriteGroup>{};
  final Map<String, SpriteGroup> _folded = <String, SpriteGroup>{};

  /// The group for [base], or null. Exact match first, then case/slash-folded.
  SpriteGroup? resolve(String base) => _exact[base] ?? _folded[foldBase(base)];

  /// Normalise a sprite base for tolerant matching: trim, `\`→`/`, lower-case,
  /// and drop a single leading `/` (the optional AO subfolder marker).
  static String foldBase(String base) {
    final String b = base.trim().replaceAll(r'\', '/').toLowerCase();
    return b.startsWith('/') ? b.substring(1) : b;
  }
}

/// Title-case a `snake_case`/`camelCase`/`kebab` leaf into a friendly label.
String _humanize(String raw) {
  final String spaced = raw
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'),
          (Match m) => '${m[1]} ${m[2]}')
      .trim();
  if (spaced.isEmpty) return raw;
  return spaced
      .split(RegExp(r'\s+'))
      .map((String w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// Natural comparison so `2` sorts before `10`.
int _natCompare(String a, String b) {
  final RegExp re = RegExp(r'(\d+)|(\D+)');
  final List<Match> am = re.allMatches(a).toList();
  final List<Match> bm = re.allMatches(b).toList();
  final int n = am.length < bm.length ? am.length : bm.length;
  for (int i = 0; i < n; i++) {
    final String at = am[i].group(0)!;
    final String bt = bm[i].group(0)!;
    final int? ai = int.tryParse(at);
    final int? bi = int.tryParse(bt);
    final int cmp = (ai != null && bi != null)
        ? ai.compareTo(bi)
        : at.compareTo(bt);
    if (cmp != 0) return cmp;
  }
  return a.length.compareTo(b.length);
}
