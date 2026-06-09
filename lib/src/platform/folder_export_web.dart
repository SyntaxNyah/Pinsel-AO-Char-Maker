import 'dart:typed_data';

/// Web has no writable filesystem, so a "save as a folder" can't work — the
/// caller falls back to the `.zip` download. Returning null signals that.
/// [confirmReplace] is accepted to match the native signature but unused.
Future<String?> exportToFolder(
  Map<String, Uint8List> files, {
  Future<bool> Function(String charName)? confirmReplace,
}) async =>
    null;
