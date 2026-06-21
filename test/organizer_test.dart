import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pinsel/src/core/ao_constants.dart';
import 'package:pinsel/src/core/character.dart';
import 'package:pinsel/src/discovery/character_builder.dart';
import 'package:pinsel/src/discovery/organizer.dart';
import 'package:pinsel/src/discovery/sprite_scanner.dart';
import 'package:pinsel/src/imaging/codecs.dart';
import 'package:pinsel/src/platform/workspace.dart';

void main() {
  test('organizer generates char_icon + buttons with the chosen size/framing',
      () async {
    final MemoryWorkspace src = MemoryWorkspace();
    final Uint8List png =
        Codecs.encodePng(img.Image(width: 8, height: 8, numChannels: 4));
    src.put('(a)happy.png', png);
    src.put('(b)happy.png', png);

    final ScanResult scan = const SpriteScanner().fromPaths(<String>[
      '(a)happy.png',
      '(b)happy.png',
    ]);
    final Character character =
        const CharacterBuilder().build(scan, config: const BuildConfig(name: 'Bob'));

    final List<String> calls = <String>[];
    final Organizer org = Organizer(
      buttonRenderer: (Uint8List b, String e, int s, CropFraming f, double z,
          String? sb) async {
        calls.add('btn:$s:${f.id}:$sb');
        return b;
      },
      iconRenderer: (Uint8List b, String e, int s, CropFraming f, double z,
          String? sb) async {
        calls.add('icon:$s:${f.id}:$sb');
        return b;
      },
    );

    final MemoryWorkspace target = MemoryWorkspace();
    await org.organize(
      character: character,
      scan: scan,
      source: src,
      target: target,
      config: const OrganizeConfig(
        targetCharDir: 'Bob',
        buttonSize: 128,
        buttonFraming: CropFraming.head,
        iconSize: 40,
        iconFraming: CropFraming.full,
      ),
    );

    expect(await target.exists('Bob/char_icon.png'), isTrue);
    expect(await target.exists('Bob/emotions/button1_off.png'), isTrue);
    // Buttons used the button size + framing + the emote's sprite base (for
    // per-sprite manual crops); the icon used its own size/framing and no base.
    expect(calls.any((String c) => c == 'btn:128:head:happy'), isTrue);
    expect(calls.any((String c) => c == 'icon:40:full:null'), isTrue);
  });

  test('generateCharIcon=false skips the icon', () async {
    final MemoryWorkspace src = MemoryWorkspace();
    src.put('(a)x.png',
        Codecs.encodePng(img.Image(width: 4, height: 4, numChannels: 4)));
    final ScanResult scan = const SpriteScanner().fromPaths(<String>['(a)x.png']);
    final Character character =
        const CharacterBuilder().build(scan, config: const BuildConfig(name: 'C'));

    final MemoryWorkspace target = MemoryWorkspace();
    await Organizer(
      buttonRenderer: (Uint8List b, String e, int s, CropFraming f, double z,
              String? sb) async =>
          b,
    ).organize(
      character: character,
      scan: scan,
      source: src,
      target: target,
      config: const OrganizeConfig(targetCharDir: 'C', generateCharIcon: false),
    );

    expect(await target.exists('C/char_icon.png'), isFalse);
  });

  test('renders a button for EVERY emote (multi-emote)', () async {
    final MemoryWorkspace src = MemoryWorkspace();
    final Uint8List png =
        Codecs.encodePng(img.Image(width: 8, height: 8, numChannels: 4));
    for (final String base in <String>['normal', 'happy', 'sad']) {
      src.put('(a)$base.png', png);
      src.put('(b)$base.png', png);
    }
    final ScanResult scan =
        const SpriteScanner().fromPaths(await src.listFiles());
    final Character character = const CharacterBuilder()
        .build(scan, config: const BuildConfig(name: 'Bob'));
    expect(character.emotes.length, 3);

    final MemoryWorkspace target = MemoryWorkspace();
    await Organizer(
      buttonRenderer: (Uint8List b, String e, int s, CropFraming f, double z,
              String? sb) async =>
          b,
    ).organize(
      character: character,
      scan: scan,
      source: src,
      target: target,
      config: const OrganizeConfig(targetCharDir: 'Bob'),
    );

    // One button per emote — not just the first (the regression this guards).
    expect(await target.exists('Bob/emotions/button1_off.png'), isTrue);
    expect(await target.exists('Bob/emotions/button2_off.png'), isTrue);
    expect(await target.exists('Bob/emotions/button3_off.png'), isTrue);
  });

  test('imported char.ini with mismatched casing still exports every button',
      () async {
    final MemoryWorkspace src = MemoryWorkspace();
    final Uint8List png =
        Codecs.encodePng(img.Image(width: 8, height: 8, numChannels: 4));
    // Sprite files are lower-case on disk...
    src.put('(a)normal.png', png);
    src.put('(b)normal.png', png);
    src.put('(a)happy.png', png);
    // ...but the imported ini references them with different casing. AO resolves
    // sprite files case-insensitively, so the organizer must too — otherwise
    // only an exactly-matching emote gets a button (the "only one emotion
    // exports / char data deleted" bug report).
    const String ini = '[Options]\n'
        'name = Bob\n\n'
        '[Emotions]\n'
        'number = 2\n'
        '1 = Normal#-#Normal#0#1\n'
        '2 = Happy#-#Happy#0#1\n';
    final Character character = Character.parse(ini);
    final ScanResult scan =
        const SpriteScanner().fromPaths(await src.listFiles());

    final MemoryWorkspace target = MemoryWorkspace();
    await Organizer(
      buttonRenderer: (Uint8List b, String e, int s, CropFraming f, double z,
              String? sb) async =>
          b,
    ).organize(
      character: character,
      scan: scan,
      source: src,
      target: target,
      config: const OrganizeConfig(targetCharDir: 'Bob'),
    );

    expect(await target.exists('Bob/emotions/button1_off.png'), isTrue);
    expect(await target.exists('Bob/emotions/button2_off.png'), isTrue);
  });
}
