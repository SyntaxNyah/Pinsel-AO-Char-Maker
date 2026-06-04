import 'dart:typed_data';

import 'folder_picker_io.dart'
    if (dart.library.html) 'folder_picker_web.dart' as impl;

/// A file picked as part of a folder selection: [name] is the path relative to
/// the chosen folder (using `/`), so sub-folder structure is preserved.
typedef PickedFolderFile = ({String name, Uint8List bytes});

/// The result of a folder pick: the chosen folder's [folderName] (used to
/// auto-name the character instead of the generic "newchar") and its [files].
/// [folderName] is null when it can't be determined.
typedef PickedFolder = ({String? folderName, List<PickedFolderFile> files});

/// Let the user pick a whole **folder** of sprites (recursively), on every
/// platform:
///  * desktop/mobile — native directory picker;
///  * web — a `<input webkitdirectory>` folder upload.
/// Returns null if cancelled.
Future<PickedFolder?> pickFolderFiles() => impl.pickFolderFiles();
