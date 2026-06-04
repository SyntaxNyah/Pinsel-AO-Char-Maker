import 'character.dart';

/// Snapshot-based undo/redo for the character editor.
///
/// Each snapshot is just the serialized `char.ini` text, which makes undo/redo
/// completely reliable (no risk of a half-applied command) and cheap for the
/// modest size of a char.ini. Call [push] after every meaningful edit.
class EditHistory {
  EditHistory({this.limit = 100});

  final int limit;
  final List<String> _undo = <String>[];
  final List<String> _redo = <String>[];
  String? _current;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get depth => _undo.length;

  /// Seed the history with the initial state (no undo entry created).
  void seed(Character c) {
    _current = c.serialize();
    _undo.clear();
    _redo.clear();
  }

  /// Forget all history (used when the project is reset).
  void clear() {
    _current = null;
    _undo.clear();
    _redo.clear();
  }

  /// Record a new state after an edit.
  void push(Character c) {
    final String snap = c.serialize();
    if (snap == _current) return; // no-op edit
    if (_current != null) {
      _undo.add(_current!);
      if (_undo.length > limit) _undo.removeAt(0);
    }
    _current = snap;
    _redo.clear();
  }

  /// Undo, returning the restored character (or null if nothing to undo).
  Character? undo() {
    if (_undo.isEmpty) return null;
    _redo.add(_current!);
    _current = _undo.removeLast();
    return Character.parse(_current!);
  }

  /// Redo, returning the restored character (or null if nothing to redo).
  Character? redo() {
    if (_redo.isEmpty) return null;
    _undo.add(_current!);
    _current = _redo.removeLast();
    return Character.parse(_current!);
  }
}
