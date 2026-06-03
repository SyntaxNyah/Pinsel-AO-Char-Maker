import 'package:flutter_test/flutter_test.dart';
import 'package:pinsel/src/discovery/bulk_folders.dart';

FolderCharacter _named(List<FolderCharacter> chars, String name) =>
    chars.firstWhere((FolderCharacter c) => c.name == name);

void main() {
  test('groups native-style paths (no wrapper) by sub-folder', () {
    final List<FolderCharacter> chars = BulkFolders.split(<String>[
      'Bob/(a)happy.png',
      'Bob/(b)happy.png',
      'Alice/idle.png',
    ]);
    expect(chars.map((FolderCharacter c) => c.name).toSet(),
        <String>{'Bob', 'Alice'});
    final FolderCharacter bob = _named(chars, 'Bob');
    expect(bob.files.keys.toSet(), <String>{'(a)happy.png', '(b)happy.png'});
    // The original source key is preserved for byte lookup.
    expect(bob.files['(a)happy.png'], 'Bob/(a)happy.png');
  });

  test('strips a single web-style wrapper folder before grouping', () {
    final List<FolderCharacter> chars = BulkFolders.split(<String>[
      'Cast/Bob/(a)happy.png',
      'Cast/Alice/idle.png',
    ]);
    expect(chars.map((FolderCharacter c) => c.name).toSet(),
        <String>{'Bob', 'Alice'});
    expect(_named(chars, 'Bob').files.keys, contains('(a)happy.png'));
    expect(_named(chars, 'Bob').files['(a)happy.png'], 'Cast/Bob/(a)happy.png');
  });

  test('keeps nested sub-paths (anim/) inside one character', () {
    final List<FolderCharacter> chars = BulkFolders.split(<String>[
      'Bob/(a)x.png',
      'Bob/anim/blink.png',
    ]);
    expect(chars, hasLength(1));
    expect(chars.first.name, 'Bob');
    expect(chars.first.files.keys.toSet(),
        <String>{'(a)x.png', 'anim/blink.png'});
  });

  test('nested anim inside a wrapped multi-character pick stays put', () {
    final List<FolderCharacter> chars = BulkFolders.split(<String>[
      'Cast/Bob/(a)x.png',
      'Cast/Bob/anim/blink.png',
      'Cast/Alice/idle.png',
    ]);
    expect(chars.map((FolderCharacter c) => c.name).toSet(),
        <String>{'Bob', 'Alice'});
    expect(_named(chars, 'Bob').files.keys.toSet(),
        <String>{'(a)x.png', 'anim/blink.png'});
  });

  test('a loose folder with no sub-folders collapses to one character', () {
    final List<FolderCharacter> chars =
        BulkFolders.split(<String>['(a)x.png', '(b)x.png']);
    expect(chars, hasLength(1));
    expect(chars.first.name, 'character');
    expect(chars.first.files.keys.toSet(), <String>{'(a)x.png', '(b)x.png'});
  });

  test('a wrapped single loose folder is one character named after it', () {
    final List<FolderCharacter> chars =
        BulkFolders.split(<String>['MyChar/(a)x.png', 'MyChar/(b)x.png']);
    expect(chars, hasLength(1));
    expect(chars.first.name, 'MyChar');
  });

  test('handles 10 sibling character folders', () {
    final List<String> paths = <String>[
      for (int i = 1; i <= 10; i++) ...<String>['char$i/(a)x.png', 'char$i/(b)x.png'],
    ];
    final List<FolderCharacter> chars = BulkFolders.split(paths);
    expect(chars, hasLength(10));
    expect(chars.every((FolderCharacter c) => c.files.length == 2), isTrue);
  });

  test('normalises backslashes and leading slashes', () {
    final List<FolderCharacter> chars = BulkFolders.split(<String>[
      r'Bob\(a)x.png',
      '/Alice/idle.png',
    ]);
    expect(chars.map((FolderCharacter c) => c.name).toSet(),
        <String>{'Bob', 'Alice'});
  });

  test('empty input yields no characters', () {
    expect(BulkFolders.split(<String>[]), isEmpty);
  });
}
