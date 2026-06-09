import 'package:flutter/material.dart';

/// Confirm dialog shown before a folder export overwrites an existing character
/// folder on disk. Returns true to **replace** (the export deletes the old
/// `<charName>/` folder first, then writes the fresh build), or false to abort.
///
/// Folders are written *over* whatever is already there — unlike a fresh zip —
/// so without this, stale buttons + renamed-away sprite files survive and mix
/// with the new ones. Replacing the one character folder we're exporting keeps
/// the result clean. Other folders next to it are left untouched.
///
/// Guards against an unmounted context: the native folder picker runs first, so
/// there's an async gap before this dialog. If the context is gone we abort
/// (return false) rather than risk a delete with no confirmation.
Future<bool> confirmReplaceFolder(BuildContext context, String charName) async {
  if (!context.mounted) return false;
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('Folder already exists'),
      content: Text(
        'A folder named "$charName" is already here.\n\n'
        'Replace it with the new build? This deletes the old "$charName" folder '
        '(its buttons and sprites) so stale files can’t mix with the new '
        'ones. Other folders are left alone.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Replace'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
