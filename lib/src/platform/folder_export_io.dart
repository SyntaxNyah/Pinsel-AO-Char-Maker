import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

/// Native: ask for a destination directory, then write every file under it so
/// the character folder simply *appears* on disk (DRO/KFO-style — no zip to
/// extract). The relative keys use `/`; we split + re-join with the platform
/// separator so Windows paths come out right.
Future<String?> exportToFolder(Map<String, Uint8List> files) async {
  final String? dir = await FilePicker.platform.getDirectoryPath(
    dialogTitle: 'Choose where to save the character folder',
  );
  if (dir == null) return null;
  for (final MapEntry<String, Uint8List> e in files.entries) {
    final List<String> parts =
        e.key.split('/').where((String s) => s.isNotEmpty).toList();
    if (parts.isEmpty) continue;
    final File f = File(p.joinAll(<String>[dir, ...parts]));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(e.value, flush: true);
  }
  return dir;
}
