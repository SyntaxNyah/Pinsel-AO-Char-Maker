import 'package:flutter_test/flutter_test.dart';
import 'package:pinsel/src/imaging/sprite_sheet.dart';

void main() {
  group('SpriteSheet.uniqueNames (ripper add-a-second-sheet bug)', () {
    test('first sheet: auto names start at 1', () {
      expect(
        SpriteSheet.uniqueNames(
            <String>{}, <String>['sprite1', 'sprite2', 'sprite3'], 'sprite'),
        <String>['sprite1', 'sprite2', 'sprite3'],
      );
    });

    test('second sheet continues past existing sprites — no overwrite', () {
      final Set<String> existing = <String>{
        'sprite1',
        'sprite2',
        'sprite3',
        'sprite4'
      };
      final List<String> names = SpriteSheet.uniqueNames(
          existing, <String>['sprite1', 'sprite2', 'sprite3'], 'sprite');
      // The bug was these came back as sprite1..3 and clobbered the first sheet.
      expect(names, <String>['sprite5', 'sprite6', 'sprite7']);
      for (final String n in names) {
        expect(existing.contains(n), isFalse);
      }
    });

    test('hand-typed names are preserved (and deduped against existing)', () {
      final List<String> names = SpriteSheet.uniqueNames(
          <String>{'happy'}, <String>['happy', 'angry'], 'sprite');
      expect(names[0], 'happy_2'); // collided with existing → suffixed
      expect(names[1], 'angry');
    });

    test('dedup is case-insensitive (Windows paths)', () {
      expect(
        SpriteSheet.uniqueNames(<String>{'Sprite1'}, <String>['sprite1'], 'sprite'),
        <String>['sprite2'],
      );
    });

    test('illegal filename characters are sanitised', () {
      final String n =
          SpriteSheet.uniqueNames(<String>{}, <String>['a/b:c*?'], 'sprite').first;
      expect(n, isNot(contains('/')));
      expect(n, isNot(contains(':')));
      expect(n, isNot(contains('*')));
    });

    test('duplicate auto names within one batch never collide', () {
      final List<String> names = SpriteSheet.uniqueNames(
          <String>{}, <String>['sprite1', 'sprite1', 'sprite1'], 'sprite');
      expect(names.toSet().length, 3);
    });

    test('honours a custom prefix', () {
      expect(
        SpriteSheet.uniqueNames(<String>{'face1'}, <String>['face1', 'face2'], 'face'),
        <String>['face2', 'face3'],
      );
    });
  });
}
