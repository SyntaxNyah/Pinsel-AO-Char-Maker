import '../core/ao_constants.dart';
import '../core/character.dart';
import '../core/emote.dart';
import 'sprite_scanner.dart';

/// What an [IniRepair] did to one `char.ini`.
class IniRepairReport {
  IniRepairReport({
    required this.kept,
    required this.added,
    required this.dropped,
  });

  /// Emotes kept (their sprite still exists on disk).
  final int kept;

  /// Emotes **added** for sprites that had no emote (the main repair).
  final int added;

  /// Emotes **removed** because their sprite file is gone (dangling refs).
  final int dropped;

  int get total => kept + added;
  bool get changed => added > 0 || dropped > 0;

  String get summary =>
      'kept $kept, added $added, removed $dropped → $total emote(s)';
}

/// Repairs a (possibly broken) `char.ini` against the sprites that are actually
/// present — so a busted INI becomes a working one rebuilt from the `emotions/`
/// folder (and wherever the sprites live).
///
/// The `[Options]`, shouts, timing and any unknown sections are **preserved**;
/// only the emote list is reconciled with reality:
///  * emotes whose sprite still exists are kept (with their comment / preanim /
///    sound / desk settings intact),
///  * emotes pointing at a missing sprite are dropped (a dangling reference is
///    exactly the kind of thing that breaks a character in-client), and
///  * every sprite with no emote gets one (named from the sprite), so a sprite
///    folder with a half-written or empty INI comes back fully populated.
///
/// [Character.serialize] then recomputes `number` and modernises the file, so the
/// output is a clean, valid INI.
class IniRepair {
  const IniRepair._();

  /// Reconcile [c]'s emotes with [scan] (the real sprite files). **Mutates [c]**
  /// (repair is inherently destructive — parse a fresh copy if you need the
  /// original) and returns a [IniRepairReport]. With [dropDangling] false, emotes
  /// whose sprite is missing are kept instead of removed.
  static IniRepairReport repair(Character c, ScanResult scan,
      {bool dropDangling = true}) {
    final Set<String> exists = <String>{
      for (final SpriteGroup g in scan.groups)
        if (g.base.isNotEmpty) g.base,
    };

    final List<Emote> out = <Emote>[];
    final Set<String> referenced = <String>{};
    int kept = 0, dropped = 0;
    for (final Emote e in c.emotes) {
      if (e.sprite.isNotEmpty && exists.contains(e.sprite)) {
        out.add(e);
        referenced.add(e.sprite);
        kept++;
      } else if (!dropDangling) {
        out.add(e);
      } else {
        dropped++;
      }
    }

    int added = 0;
    for (final SpriteGroup g in scan.groups) {
      if (g.base.isEmpty || referenced.contains(g.base)) continue;
      out.add(Emote(
        comment: g.suggestedComment,
        sprite: g.base,
        deskMod: DeskModifier.show,
      ));
      referenced.add(g.base);
      added++;
    }

    c.emotes
      ..clear()
      ..addAll(out);
    return IniRepairReport(kept: kept, added: added, dropped: dropped);
  }

  /// One-shot: parse [iniText], scan [spriteRelPaths] (paths relative to the
  /// character folder), repair, and return the **repaired INI text** + report.
  static ({String ini, IniRepairReport report}) repairText(
      String iniText, List<String> spriteRelPaths) {
    final Character c = Character.parse(iniText);
    final ScanResult scan = SpriteScanner().fromPaths(spriteRelPaths);
    final IniRepairReport report = repair(c, scan);
    return (ini: c.serialize(), report: report);
  }

  /// One character to repair: the folder that holds a `char.ini`, the ini's full
  /// path, and the sprite paths **relative to that folder**.
  static List<RepairTarget> findCharFolders(Iterable<String> allPaths) {
    final List<String> paths = <String>[
      for (final String p in allPaths) p.replaceAll('\\', '/'),
    ];
    final List<String> iniPaths = <String>[
      for (final String p in paths)
        if (_isCharIni(p)) p,
    ];
    if (iniPaths.isEmpty) return const <RepairTarget>[];

    // Char dirs, longest first, so a nested character claims its own sprites
    // before an ancestor folder does.
    final List<String> dirs = <String>[for (final String i in iniPaths) _dir(i)]
      ..sort((String a, String b) => b.length.compareTo(a.length));

    final Map<String, List<String>> spritesByDir = <String, List<String>>{
      for (final String d in dirs) d: <String>[],
    };
    for (final String p in paths) {
      if (_isCharIni(p)) continue;
      for (final String d in dirs) {
        if (_under(p, d)) {
          spritesByDir[d]!.add(_rel(p, d));
          break;
        }
      }
    }

    return <RepairTarget>[
      for (final String ini in iniPaths)
        RepairTarget(
          charDir: _dir(ini),
          iniPath: ini,
          spriteRelPaths: spritesByDir[_dir(ini)] ?? const <String>[],
        ),
    ];
  }

  static bool _isCharIni(String p) {
    final String low = p.toLowerCase();
    return low == 'char.ini' || low.endsWith('/char.ini');
  }

  static String _dir(String p) {
    final int i = p.lastIndexOf('/');
    return i < 0 ? '' : p.substring(0, i);
  }

  static bool _under(String p, String d) =>
      d.isEmpty ? true : (p.length > d.length && p.startsWith('$d/'));

  static String _rel(String p, String d) =>
      d.isEmpty ? p : p.substring(d.length + 1);
}

/// A character folder found by [IniRepair.findCharFolders].
class RepairTarget {
  const RepairTarget({
    required this.charDir,
    required this.iniPath,
    required this.spriteRelPaths,
  });

  /// The folder holding the `char.ini` (`''` = the picked root).
  final String charDir;

  /// Full path to the `char.ini`.
  final String iniPath;

  /// Sprite paths **relative to [charDir]** (for `SpriteScanner.fromPaths`).
  final List<String> spriteRelPaths;
}
