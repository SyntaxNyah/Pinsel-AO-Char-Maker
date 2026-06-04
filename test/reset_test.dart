import 'package:flutter_test/flutter_test.dart';
import 'package:pinsel/src/core/character.dart';
import 'package:pinsel/src/core/history.dart';
import 'package:pinsel/src/platform/workspace.dart';

void main() {
  test('MemoryWorkspace.clear drops every file', () async {
    final MemoryWorkspace ws = MemoryWorkspace();
    ws.put('a.png', <int>[1, 2, 3]);
    ws.put('sub/b.png', <int>[4]);
    expect((await ws.listFiles()).length, 2);
    ws.clear();
    expect(await ws.listFiles(), isEmpty);
    expect(await ws.exists('a.png'), isFalse);
  });

  test('EditHistory.clear forgets undo/redo and current', () {
    final EditHistory h = EditHistory();
    h.seed(Character()..options.name = 'a');
    h.push(Character()..options.name = 'b');
    expect(h.canUndo, isTrue);
    h.clear();
    expect(h.canUndo, isFalse);
    expect(h.canRedo, isFalse);
    expect(h.undo(), isNull);
  });
}
