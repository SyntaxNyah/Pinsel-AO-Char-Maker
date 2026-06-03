/// Splits a flat list of picked folder paths into one [FolderCharacter] per
/// top-level character sub-folder, so a *parent* folder of character sub-folders
/// can be turned into many characters in one go ("bulk folders").
///
/// The folder pickers hand back `/`-separated paths relative to whatever was
/// picked, but the leading segment differs by platform: the web upload prepends
/// the chosen folder's own name (`Cast/Bob/(a)x.png`) while the native picker
/// does not (`Bob/(a)x.png`). [BulkFolders.split] reconciles both without any
/// platform knowledge by stripping a leading **wrapper** directory — one shared
/// by every file that contains *only* sub-folders (no loose sprite sitting
/// directly inside it) — and then grouping by the next path segment. Each
/// distinct segment becomes a character named after it, with that segment
/// removed from each file's inner path, so the inner paths are exactly what the
/// scanner/organiser expect inside a single character folder (incl. nested
/// `anim/…`).
///
/// A folder of loose sprites with no per-character sub-folders collapses into a
/// single character named after the folder (or [fallbackName] when there's no
/// folder name to borrow).
library;

/// One character extracted from a bulk folder pick.
class FolderCharacter {
  FolderCharacter(this.name);

  /// Character (and target folder) name, taken from the sub-folder.
  final String name;

  /// Inner path (within the character folder) -> the original source path
  /// string, so callers can look the file's bytes back up unchanged.
  final Map<String, String> files = <String, String>{};
}

class BulkFolders {
  const BulkFolders._();

  /// Group [paths] (any picker's relative paths) into characters. See the
  /// library doc for the wrapper-stripping rules.
  static List<FolderCharacter> split(
    Iterable<String> paths, {
    String fallbackName = 'character',
  }) {
    // Keep the original strings (the lookup keys callers pass) alongside the
    // normalised segments we analyse, so we never hand back a mangled key.
    final List<String> original = <String>[];
    final List<List<String>> segs = <List<String>>[];
    for (final String raw in paths) {
      final String n = _norm(raw);
      if (n.isEmpty) continue;
      original.add(raw);
      segs.add(n.split('/'));
    }
    if (segs.isEmpty) return <FolderCharacter>[];

    // Count leading directory segments that are a *wrapper*: shared by every
    // path, never the file leaf, and never directly holding a file (so a single
    // character folder — which has loose sprites in it — is NOT stripped, while
    // a parent folder of character sub-folders is).
    int common = 0;
    while (true) {
      final int k = common;
      final String candidate = segs.first[k];
      bool wrapper = true;
      for (final List<String> s in segs) {
        // seg[k] must be a directory for this path (something follows it)…
        if (s.length <= k + 1) {
          wrapper = false;
          break;
        }
        // …shared by all…
        if (s[k] != candidate) {
          wrapper = false;
          break;
        }
        // …and must not directly contain a file (that would make it a character
        // folder, not a wrapper).
        if (s.length == k + 2) {
          wrapper = false;
          break;
        }
      }
      if (!wrapper) break;
      common++;
    }

    final String wrapperName = common > 0 ? segs.first[common - 1] : fallbackName;

    final Map<String, FolderCharacter> out = <String, FolderCharacter>{};
    for (int i = 0; i < segs.length; i++) {
      final List<String> rest = segs[i].sublist(common);
      final String key;
      final String inner;
      if (rest.length >= 2) {
        // A per-character sub-folder.
        key = rest.first;
        inner = rest.sublist(1).join('/');
      } else {
        // A file sitting directly in the (post-strip) root: a folder of loose
        // sprites with no per-character sub-folder — one character.
        key = wrapperName;
        inner = rest.join('/');
      }
      out.putIfAbsent(key, () => FolderCharacter(key)).files[inner] = original[i];
    }
    return out.values.toList();
  }

  static String _norm(String rel) {
    String r = rel.replaceAll(r'\', '/').trim();
    while (r.startsWith('/')) {
      r = r.substring(1);
    }
    return r;
  }
}
