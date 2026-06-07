import 'package:flutter_test/flutter_test.dart';
import 'package:pinsel/src/core/character.dart';
import 'package:pinsel/src/discovery/character_builder.dart';
import 'package:pinsel/src/discovery/ini_repair.dart';
import 'package:pinsel/src/discovery/sprite_scanner.dart';

void main() {
  test('repair reconciles emotes with the sprites actually present', () {
    // Build a valid character from two sprites, then serialize it to an INI.
    final ScanResult scan0 =
        const SpriteScanner().fromPaths(<String>['happy.png', 'angry.png']);
    final Character c0 = const CharacterBuilder()
        .build(scan0, config: const BuildConfig(name: 'bob'));
    expect(c0.emotes.length, 2);
    final String iniText = c0.serialize();

    // Repair that INI against a different sprite set: happy stays, angry is gone,
    // sad is new.
    final ({String ini, IniRepairReport report}) res =
        IniRepair.repairText(iniText, <String>['happy.png', 'sad.png']);
    expect(res.report.kept, 1); // happy
    expect(res.report.dropped, 1); // angry (file gone)
    expect(res.report.added, 1); // sad (new sprite)
    expect(res.report.total, 2);
    expect(res.report.changed, isTrue);

    final Character c2 = Character.parse(res.ini);
    final Set<String> sprites = c2.spriteReferences();
    expect(sprites.contains('happy'), isTrue);
    expect(sprites.contains('sad'), isTrue);
    expect(sprites.contains('angry'), isFalse);
    // [Options] survives the repair.
    expect(c2.options.name, 'bob');
  });

  test('an empty/garbage INI is rebuilt entirely from the sprites', () {
    final ({String ini, IniRepairReport report}) res = IniRepair.repairText(
        'this is not a valid char.ini at all',
        <String>['(a)normal.png', '(b)normal.png', 'point.png']);
    expect(res.report.added, greaterThanOrEqualTo(2)); // normal + point
    final Character c = Character.parse(res.ini);
    expect(c.spriteReferences().contains('normal'), isTrue);
    expect(c.spriteReferences().contains('point'), isTrue);
  });

  test('findCharFolders groups sprites by their char.ini folder (incl. nested)',
      () {
    final List<RepairTarget> targets = IniRepair.findCharFolders(<String>[
      'bob/char.ini',
      'bob/(a)happy.png',
      'bob/(b)happy.png',
      'bob/sub/char.ini', // a nested character
      'bob/sub/(a)x.png',
      'alice/char.ini',
      'alice/normal.png',
    ]);
    expect(targets.length, 3);
    final Map<String, RepairTarget> byDir = <String, RepairTarget>{
      for (final RepairTarget t in targets) t.charDir: t,
    };
    expect(byDir['bob']!.spriteRelPaths,
        containsAll(<String>['(a)happy.png', '(b)happy.png']));
    // The nested character claims its OWN sprite, not the parent.
    expect(byDir['bob/sub']!.spriteRelPaths, contains('(a)x.png'));
    expect(byDir['bob']!.spriteRelPaths.contains('sub/(a)x.png'), isFalse);
    expect(byDir['alice']!.spriteRelPaths, contains('normal.png'));
  });

  test('findCharFolders handles backslashes and a root-level char.ini', () {
    final List<RepairTarget> targets = IniRepair.findCharFolders(<String>[
      r'char.ini',
      r'a\b.png',
    ]);
    expect(targets.length, 1);
    expect(targets.first.charDir, '');
    expect(targets.first.spriteRelPaths, contains('a/b.png'));
  });
}
