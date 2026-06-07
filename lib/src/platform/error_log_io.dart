import 'dart:io';

import 'package:path_provider/path_provider.dart';

String? _path;
String? get crashLogPath => _path;

/// Append [message] to `pinsel_crash.log`.
///
/// The location is chosen to be the **most discoverable** the platform allows:
///  * **Android** — the app's external files dir (`Android/data/<package>/files`),
///    which any user can open in a file manager with **no permission**. (Falls
///    back to the app documents dir, then temp.)
///  * **iOS** — the app Documents dir (visible in the Files app).
///  * **Desktop** — next to the executable, then the system temp dir, then cwd.
///
/// Best-effort and swallows all errors (logging a crash must never cause a
/// second one). Once a writable file is found it's reused on later calls.
Future<void> logCrash(String message) async {
  final String line = '[${DateTime.now().toIso8601String()}] $message\n\n';
  // Fast path: reuse the file we already resolved (avoids repeat path lookups).
  final String? known = _path;
  if (known != null) {
    try {
      await File(known)
          .writeAsString(line, mode: FileMode.append, flush: true);
      return;
    } catch (_) {
      _path = null; // location went away — re-resolve below.
    }
  }
  for (final String dir in await _candidateDirs()) {
    try {
      final File f = File('$dir${Platform.pathSeparator}pinsel_crash.log');
      await f.writeAsString(line, mode: FileMode.append, flush: true);
      _path = f.path;
      return;
    } catch (_) {
      // Try the next candidate directory.
    }
  }
}

/// The directory the crash log is (or would be) written to, resolved without
/// writing — so the app can show users *where to look* before any crash. Null if
/// it can't be determined.
Future<String?> crashLogDir() async {
  final List<String> dirs = await _candidateDirs();
  return dirs.isEmpty ? null : dirs.first;
}

/// The `File` the log is (or would be) at. Prefers the already-written path; on a
/// fresh launch that's null, so it falls back to the primary candidate dir (the
/// same one [logCrash] writes to first).
Future<File?> _logFile() async {
  String? p = _path;
  if (p == null) {
    final List<String> dirs = await _candidateDirs();
    if (dirs.isNotEmpty) {
      p = '${dirs.first}${Platform.pathSeparator}pinsel_crash.log';
    }
  }
  return p == null ? null : File(p);
}

/// Read the crash log's contents so the app can **show it in-app** (the only way
/// to reach it on Android 11+, where file managers can't browse `Android/data`).
/// Null if there's nothing to read.
Future<String?> readCrashLog() async {
  try {
    final File? f = await _logFile();
    if (f == null || !await f.exists()) return null;
    final String s = await f.readAsString();
    return s.trim().isEmpty ? null : s;
  } catch (_) {
    return null;
  }
}

/// Empty the crash log (the in-app "Clear" action).
Future<void> clearCrashLog() async {
  try {
    final File? f = await _logFile();
    if (f != null && await f.exists()) await f.writeAsString('');
  } catch (_) {}
}

Future<List<String>> _candidateDirs() async {
  final List<String> dirs = <String>[];
  // Mobile first: a place the USER can actually open in a file manager.
  try {
    if (Platform.isAndroid) {
      final Directory? ext = await getExternalStorageDirectory();
      if (ext != null) dirs.add(ext.path);
    }
    if (Platform.isAndroid || Platform.isIOS) {
      dirs.add((await getApplicationDocumentsDirectory()).path);
    }
  } catch (_) {
    // path_provider unavailable (e.g. binding not ready) — fall through.
  }
  // Desktop: next to the executable (most discoverable), then temp, then cwd.
  try {
    dirs.add(File(Platform.resolvedExecutable).parent.path);
  } catch (_) {}
  try {
    dirs.add(Directory.systemTemp.path);
  } catch (_) {}
  dirs.add('.');
  return dirs;
}
