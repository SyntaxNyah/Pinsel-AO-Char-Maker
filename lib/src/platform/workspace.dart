import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// A platform-neutral file store rooted at one folder.
///
/// All paths are **relative to [root]** and use `/` separators regardless of
/// platform. Desktop/mobile back this with the real filesystem ([IoWorkspace]);
/// the web build backs it with an in-memory store ([MemoryWorkspace]) so the
/// exact same engine code (scanning, organising, button generation, exporting)
/// runs in a browser with no changes.
abstract class Workspace {
  /// A display label for the root (an absolute path, or a virtual name on web).
  String get root;

  Future<List<String>> listFiles({bool recursive = true});

  Future<bool> exists(String rel);

  Future<Uint8List> readBytes(String rel);

  Future<String> readString(String rel) async =>
      String.fromCharCodes(await readBytes(rel));

  Future<void> writeBytes(String rel, List<int> data);

  Future<void> writeString(String rel, String data) =>
      writeBytes(rel, data.codeUnits);

  Future<void> makeDir(String rel);

  Future<void> copy(String fromRel, String toRel);

  Future<void> move(String fromRel, String toRel);

  Future<void> delete(String rel);

  /// Normalise a relative path to `/`-separated, no leading slash.
  static String norm(String rel) {
    final String r = rel.replaceAll(r'\', '/');
    return r.startsWith('/') ? r.substring(1) : r;
  }
}

/// In-memory workspace — used on web and in unit tests. Supports the full
/// [Workspace] contract without touching any real filesystem.
class MemoryWorkspace implements Workspace {
  MemoryWorkspace({this.root = 'memory://workspace'});

  @override
  final String root;

  final Map<String, Uint8List> _files = <String, Uint8List>{};

  /// Seed the workspace (handy for tests and for hydrating from an imported
  /// zip).
  void put(String rel, List<int> data) =>
      _files[Workspace.norm(rel)] = Uint8List.fromList(data);

  Map<String, Uint8List> get snapshot => Map<String, Uint8List>.unmodifiable(_files);

  /// Drop every file (used to start a project fresh / reset).
  void clear() => _files.clear();

  @override
  Future<List<String>> listFiles({bool recursive = true}) async {
    final List<String> keys = _files.keys.toList();
    if (recursive) return keys..sort();
    return keys.where((String k) => !k.contains('/')).toList()..sort();
  }

  @override
  Future<bool> exists(String rel) async => _files.containsKey(Workspace.norm(rel));

  @override
  Future<Uint8List> readBytes(String rel) async {
    final Uint8List? d = _files[Workspace.norm(rel)];
    if (d == null) {
      throw StateError('File not found in workspace: $rel');
    }
    return d;
  }

  @override
  Future<void> writeBytes(String rel, List<int> data) async =>
      _files[Workspace.norm(rel)] = Uint8List.fromList(data);

  @override
  Future<void> writeString(String rel, String data) =>
      writeBytes(rel, data.codeUnits);

  @override
  Future<String> readString(String rel) async =>
      String.fromCharCodes(await readBytes(rel));

  @override
  Future<void> makeDir(String rel) async {
    // Directories are implicit in the flat map; nothing to do.
  }

  @override
  Future<void> copy(String fromRel, String toRel) async =>
      _files[Workspace.norm(toRel)] =
          Uint8List.fromList(await readBytes(fromRel));

  @override
  Future<void> move(String fromRel, String toRel) async {
    await copy(fromRel, toRel);
    await delete(fromRel);
  }

  @override
  Future<void> delete(String rel) async => _files.remove(Workspace.norm(rel));
}

/// Join a workspace-relative directory and file name into a normalised path.
String joinRel(String dir, String name) =>
    Workspace.norm(p.join(dir, name).replaceAll(r'\', '/'));
