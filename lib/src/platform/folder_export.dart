import 'dart:typed_data';

import 'folder_export_io.dart'
    if (dart.library.html) 'folder_export_web.dart' as impl;

/// Write a built character (relative path → bytes, e.g. `name/char.ini`,
/// `name/char_icon.png`, `name/emotions/…`) into a **plain folder** the user
/// picks — no zip, so it can be dropped straight into AO's `characters/`.
///
/// Returns the chosen directory (native) or null if the user cancelled or the
/// platform can't write a folder (web has no filesystem — the caller falls back
/// to the `.zip`). Best-effort; surfaces nothing destructive.
Future<String?> exportToFolder(Map<String, Uint8List> files) =>
    impl.exportToFolder(files);
