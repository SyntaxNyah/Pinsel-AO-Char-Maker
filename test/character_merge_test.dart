import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinsel/src/core/character.dart';
import 'package:pinsel/src/discovery/character_merge.dart';

MergeSource _src(String label, String ini, Map<String, List<int>> files) =>
    MergeSource(label, Character.parse(ini), <String, Uint8List>{
      for (final MapEntry<String, List<int>> e in files.entries)
        e.key: Uint8List.fromList(e.value),
    });

void main() {
  // Bob: one emote (Normal → sprite `normal`), idle+talk, a button and an icon.
  const String bobIni = '[Options]\n'
      'name = bob\n'
      '\n'
      '[Emotions]\n'
      'number = 1\n'
      '1 = Normal#-#normal#0#\n';

  // Alice: two emotes. `happy` is unique; `normal` collides with Bob's (different
  // bytes), so it must be renamed.
  const String aliceIni = '[Options]\n'
      'name = alice\n'
      '\n'
      '[Emotions]\n'
      'number = 2\n'
      '1 = Smile#-#happy#0#\n'
      '2 = Glare#-#normal#0#\n';

  test('merges emote lists, renumbers buttons, renames the colliding sprite', () {
    final MergeSource bob = _src('bob', bobIni, <String, List<int>>{
      '(a)normal.png': <int>[10],
      '(b)normal.png': <int>[11],
      'emotions/button1_off.png': <int>[40],
      'char_icon.png': <int>[50],
    });
    final MergeSource alice = _src('alice', aliceIni, <String, List<int>>{
      '(a)happy.png': <int>[20],
      '(a)normal.png': <int>[30], // different bytes from Bob's → collision
      '(b)normal.png': <int>[31],
      'emotions/button1_off.png': <int>[41],
      'emotions/button2_off.png': <int>[42],
      'char_icon.png': <int>[51],
    });

    final MergeResult r = CharacterMerge.merge(<MergeSource>[bob, alice]);

    // Three emotes, in order, with the colliding ref rewritten.
    final Character merged = Character.parse(
        String.fromCharCodes(r.files['char.ini']!));
    expect(merged.emotes.map((e) => e.sprite).toList(),
        <String>['normal', 'happy', 'normal_2']);
    expect(merged.emotes.map((e) => e.comment).toList(),
        <String>['Normal', 'Smile', 'Glare']);
    expect(r.report.emotes, 3);
    expect(r.report.primary, 'bob');
    expect(r.report.renamedSprites, 1);

    // The primary's sprite bytes are untouched at their original path.
    expect(r.files['(a)normal.png'], Uint8List.fromList(<int>[10]));
    expect(r.files['(b)normal.png'], Uint8List.fromList(<int>[11]));

    // The secondary's colliding sprite moved to the renamed path (all files of
    // the base in lockstep), carrying its own bytes.
    expect(r.files['(a)normal_2.png'], Uint8List.fromList(<int>[30]));
    expect(r.files['(b)normal_2.png'], Uint8List.fromList(<int>[31]));
    // The non-colliding secondary sprite kept its name.
    expect(r.files['(a)happy.png'], Uint8List.fromList(<int>[20]));

    // Buttons renumbered positionally: bob#1→1, alice#1→2, alice#2→3.
    expect(r.files['emotions/button1_off.png'], Uint8List.fromList(<int>[40]));
    expect(r.files['emotions/button2_off.png'], Uint8List.fromList(<int>[41]));
    expect(r.files['emotions/button3_off.png'], Uint8List.fromList(<int>[42]));
    // The primary's button kept its number, so only the two shifted ones count.
    expect(r.report.renumberedButtons, 2);

    // One char_icon survives — the primary's; the secondary's is reported, kept.
    expect(r.files['char_icon.png'], Uint8List.fromList(<int>[50]));
    expect(r.report.conflictsKeptPrimary, 1);

    // Merged identity is the primary's.
    expect(merged.options.name, 'bob');
  });

  test('byte-identical sprites de-dupe: one file, no rename, both refs kept', () {
    const String aIni = '[Options]\nname = a\n\n[Emotions]\nnumber = 1\n'
        '1 = One#-#shared#0#\n';
    const String bIni = '[Options]\nname = b\n\n[Emotions]\nnumber = 1\n'
        '1 = Two#-#shared#0#\n';
    final MergeSource a = _src('a', aIni, <String, List<int>>{
      '(a)shared.png': <int>[7, 7, 7],
    });
    final MergeSource b = _src('b', bIni, <String, List<int>>{
      '(a)shared.png': <int>[7, 7, 7], // identical bytes
    });

    final MergeResult r = CharacterMerge.merge(<MergeSource>[a, b]);

    expect(r.report.renamedSprites, 0);
    expect(r.files.containsKey('(a)shared_2.png'), isFalse);
    expect(r.files['(a)shared.png'], Uint8List.fromList(<int>[7, 7, 7]));
    final Character merged =
        Character.parse(String.fromCharCodes(r.files['char.ini']!));
    expect(merged.emotes.map((e) => e.sprite).toList(),
        <String>['shared', 'shared']);
  });

  test('a preanim collision renames the file and follows the preanim ref', () {
    const String aIni = '[Options]\nname = a\n\n[Emotions]\nnumber = 1\n'
        '1 = Object#think#point#1#\n';
    const String bIni = '[Options]\nname = b\n\n[Emotions]\nnumber = 1\n'
        '1 = Object#think#shout#1#\n';
    final MergeSource a = _src('a', aIni, <String, List<int>>{
      'point.png': <int>[1],
      'anim/think.gif': <int>[2],
    });
    final MergeSource b = _src('b', bIni, <String, List<int>>{
      'shout.png': <int>[3],
      'anim/think.gif': <int>[4], // collides with a's think, different bytes
    });

    final MergeResult r = CharacterMerge.merge(<MergeSource>[a, b]);

    expect(r.report.renamedPreanims, 1);
    expect(r.files['anim/think.gif'], Uint8List.fromList(<int>[2]));
    expect(r.files['anim/think_2.gif'], Uint8List.fromList(<int>[4]));
    final Character merged =
        Character.parse(String.fromCharCodes(r.files['char.ini']!));
    // The first emote keeps `think`; the second now points at `think_2`.
    expect(merged.emotes[0].preanim, 'think');
    expect(merged.emotes[1].preanim, 'think_2');
  });

  test('secondary single-instance sections are reported as losses, not dropped silently',
      () {
    const String primaryIni = '[Options]\nname = main\n\n'
        '[Emotions]\nnumber = 1\n1 = A#-#a#0#\n';
    const String otherIni = '[Options]\nname = other\n\n'
        '[Emotions]\nnumber = 1\n1 = B#-#b#0#\n\n'
        '[Options2]\nname = altname\n\n'
        '[Shouts]\nobjection = my_objection\n';
    final MergeSource p = _src('main', primaryIni, <String, List<int>>{
      '(a)a.png': <int>[1],
    });
    final MergeSource o = _src('other', otherIni, <String, List<int>>{
      '(a)b.png': <int>[2],
    });

    final MergeResult r = CharacterMerge.merge(<MergeSource>[p, o]);

    expect(r.report.hasLosses, isTrue);
    expect(r.report.losses.any((s) => s.contains('Shouts')), isTrue);
    expect(r.report.losses.any((s) => s.contains('Options')), isTrue);
    // The merged character keeps the primary's identity only.
    final Character merged =
        Character.parse(String.fromCharCodes(r.files['char.ini']!));
    expect(merged.options.name, 'main');
    expect(merged.alternateOptions.isEmpty, isTrue);
    expect(merged.shouts.isEmpty, isTrue);
  });
}
