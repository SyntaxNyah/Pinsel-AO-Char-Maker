import 'dart:typed_data';

import 'folder_export_io.dart'
    if (dart.library.html) 'folder_export_web.dart' as impl;

/// Write a built character (relative path → bytes, e.g. `name/char.ini`,
/// `name/char_icon.png`, `name/emotions/…`) into a **plain folder** the user
/// picks — no zip, so it can be dropped straight into AO's `characters/`.
///
/// A folder is written *over* whatever is already on disk, so stale buttons +
/// renamed-away sprites from an older build would otherwise survive and mix
/// with the new files (a zip doesn't have this problem — it's a fresh
/// container). When the target already contains a `<charName>/` folder this
/// build would write, [confirmReplace] is asked; returning true deletes that
/// one folder first (a clean replace), false aborts the export. When
/// [confirmReplace] is null the old overwrite-by-name behaviour is kept (no
/// deletes).
///
/// Returns the chosen directory (native) or null if the user cancelled (the
/// picker or the replace prompt), or the platform can't write a folder (web has
/// no filesystem — the caller falls back to the `.zip`).
Future<String?> exportToFolder(
  Map<String, Uint8List> files, {
  Future<bool> Function(String charName)? confirmReplace,
}) =>
    impl.exportToFolder(files, confirmReplace: confirmReplace);
