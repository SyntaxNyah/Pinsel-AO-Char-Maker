import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

/// Native: ask for a destination directory, then write every file under it so
/// the character folder simply *appears* on disk (DRO/KFO-style — no zip to
/// extract). The relative keys use `/`; we split + re-join with the platform
/// separator so Windows paths come out right.
///
/// Because we write *over* the destination, a stale `<charName>/` folder from an
/// older build would leave behind buttons + renamed-away sprites that mix with
/// the new files. So when a character folder this build writes already exists,
/// [confirmReplace] is asked; on yes we delete that one folder first for a clean
/// replace, on no we abort. With no [confirmReplace] the legacy overwrite-only
/// behaviour is kept (nothing is deleted).
Future<String?> exportToFolder(
  Map<String, Uint8List> files, {
  Future<bool> Function(String charName)? confirmReplace,
}) async {
  final String? dir = await FilePicker.platform.getDirectoryPath(
    dialogTitle: 'Choose where to save the character folder',
  );
  if (dir == null) return null;

  // Clean any existing target character folder first (with confirmation) so
  // stale files can't survive. Normally there's exactly one top-level folder
  // ("Amy/…"); loose root-level files (no '/') aren't treated as a char folder.
  if (confirmReplace != null) {
    final Set<String> topDirs = <String>{
      for (final String key in files.keys)
        if (key.split('/').where((String s) => s.isNotEmpty).length > 1)
          key.split('/').firstWhere((String s) => s.isNotEmpty),
    };
    for (final String top in topDirs) {
      final Directory existing = Directory(p.join(dir, top));
      if (!await existing.exists()) continue;
      final bool replace = await confirmReplace(top);
      // Declined → abort rather than write a half-stale, mixed folder.
      if (!replace) return null;
      await existing.delete(recursive: true);
    }
  }

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
