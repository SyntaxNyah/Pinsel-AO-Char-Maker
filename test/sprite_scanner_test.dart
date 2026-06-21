import 'package:flutter_test/flutter_test.dart';
import 'package:pinsel/src/discovery/character_builder.dart';
import 'package:pinsel/src/discovery/sprite_scanner.dart';
import 'package:pinsel/src/core/ao_constants.dart';

void main() {
  const SpriteScanner scanner = SpriteScanner();

  test('classifies (a)/(b) pairs, statics, subfolders, preanims, ignores', () {
    final ScanResult r = scanner.fromPaths(<String>[
      '(a)happy.png',
      '(b)happy.png',
      'normal.png',
      '(a)/def/think.webp',
      '(b)/def/think.webp',
      'anim/wave.gif',
      'char_icon.png',
      'emotions/button1_off.png',
    ]);

    final Map<String, SpriteGroup> byBase = <String, SpriteGroup>{
      for (final SpriteGroup g in r.groups) g.base: g,
    };

    expect(byBase.containsKey('happy'), isTrue);
    expect(byBase['happy']!.idle, isNotNull);
    expect(byBase['happy']!.talk, isNotNull);

    expect(byBase.containsKey('normal'), isTrue);
    expect(byBase['normal']!.hasStatic, isTrue);

    expect(byBase.containsKey('/def/think'), isTrue);
    expect(byBase['/def/think']!.idle, isNotNull);

    expect(r.preanimCandidates.any((SpriteFile f) => f.relPath == 'anim/wave.gif'),
        isTrue);
    expect(r.ignored.contains('char_icon.png'), isTrue);
    expect(r.ignored.any((String p) => p.startsWith('emotions/')), isTrue);
  });

  test('extension priority prefers webp over png for same sprite/state', () {
    final ScanResult r = scanner.fromPaths(<String>['(a)x.png', '(a)x.webp']);
    final SpriteGroup g = r.groups.single;
    expect(g.idle!.ext, 'webp');
  });

  test('SpriteGroupIndex resolves exact first, then case/slash-folded', () {
    // Files on disk are lower-case; an imported char.ini may reference them with
    // different casing (and the subfolder leading `/` present or omitted).
    final ScanResult r = scanner.fromPaths(<String>[
      '(a)normal.png', '(b)normal.png',
      '(a)happy.png',
      '(a)/def/think.webp',
    ]);
    final SpriteGroupIndex index = SpriteGroupIndex(r.groups);

    // Exact still works.
    expect(index.resolve('normal')?.base, 'normal');
    expect(index.resolve('/def/think')?.base, '/def/think');

    // Case-insensitive fallback (the imported-ini bug): 'Normal' -> normal.
    expect(index.resolve('Normal')?.base, 'normal');
    expect(index.resolve('HAPPY')?.base, 'happy');

    // Subfolder leading-`/` and casing both tolerated.
    expect(index.resolve('Def/Think')?.base, '/def/think');
    expect(index.resolve('/DEF/think')?.base, '/def/think');

    // A genuinely absent sprite still returns null.
    expect(index.resolve('missing'), isNull);
  });

  test('auto-builder produces emotes with sensible defaults', () {
    final ScanResult r = scanner.fromPaths(<String>[
      '(a)normal.png', '(b)normal.png',
      '(a)point.png', '(b)point.png', 'point.png', // bare => preanim
      'document.png',
    ]);
    final c = const CharacterBuilder().build(r, config: const BuildConfig(name: 'bob'));
    expect(c.options.name, 'bob');
    expect(c.emotes.length, 3);
    // "normal" floats to the front via preferredFirstNames.
    expect(c.emotes.first.sprite, 'normal');
    final point = c.emotes.firstWhere((e) => e.sprite == 'point');
    expect(point.modifier, EmoteModifier.preanim);
    expect(point.preanim, 'point');
  });
}
