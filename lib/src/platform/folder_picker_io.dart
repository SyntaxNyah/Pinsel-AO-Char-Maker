import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

/// Skip any single file larger than this when scanning a folder. AO assets
/// (sprites, audio, char.ini) are small; a file this big is a video/PSD/archive
/// that doesn't belong in a character and would only risk an out-of-memory
/// crash when "scanning" a folder. NOT an extension filter — char.ini, audio
/// and every small file are still read (an extension allow-list would silently
/// drop char.ini + SFX and break "import an existing character").
const int _maxFileBytes = 64 * 1024 * 1024; // 64 MB

Future<
    ({
      String? folderName,
      List<({String name, Uint8List bytes})> files
    })?> pickFolderFiles() async {
  final String? dir = await FilePicker.platform.getDirectoryPath();
  if (dir == null) return null;
  final List<({String name, Uint8List bytes})> out =
      <({String name, Uint8List bytes})>[];
  // followLinks: false — a symlink/junction cycle (common on Windows) under a
  // recursive scan can otherwise loop forever and hang/OOM the app.
  await for (final FileSystemEntity ent
      in Directory(dir).list(recursive: true, followLinks: false)) {
    if (ent is! File) continue;
    try {
      // Don't pull a giant non-AO file into memory.
      if (await ent.length() > _maxFileBytes) continue;
      final Uint8List bytes = await ent.readAsBytes();
      final String rel = p.relative(ent.path, from: dir).replaceAll(r'\', '/');
      out.add((name: rel, bytes: bytes));
    } catch (_) {
      // Skip files we can't read (locked, permission denied, vanished) instead
      // of failing the whole import.
    }
  }
  final String base = p.basename(dir);
  return (folderName: base.isEmpty ? null : base, files: out);
}
