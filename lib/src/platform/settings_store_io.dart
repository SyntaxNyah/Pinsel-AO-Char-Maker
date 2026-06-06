import 'dart:convert';
import 'dart:io';

const String _fileName = 'pinsel_settings.json';

/// Read `pinsel_settings.json` from the first candidate dir that has it. Tries
/// the same locations [saveSettings] writes to, in the same order, so a restart
/// finds what the previous session saved. Returns `{}` on any miss/parse error.
Future<Map<String, dynamic>> loadSettings() async {
  for (final String dir in _candidateDirs()) {
    try {
      final File f = File('$dir${Platform.pathSeparator}$_fileName');
      if (!await f.exists()) continue;
      final Object? decoded = jsonDecode(await f.readAsString());
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // Try the next candidate (corrupt file, permissions, …).
    }
  }
  return <String, dynamic>{};
}

/// Write [settings] to the first writable candidate dir. Swallows all errors —
/// failing to persist a preference must never crash the app.
Future<void> saveSettings(Map<String, dynamic> settings) async {
  final String text = jsonEncode(settings);
  for (final String dir in _candidateDirs()) {
    try {
      final File f = File('$dir${Platform.pathSeparator}$_fileName');
      await f.writeAsString(text, flush: true);
      return;
    } catch (_) {
      // Try the next candidate directory.
    }
  }
}

/// Executable folder first (most stable across restarts of an install), then the
/// system temp dir, then the cwd — mirrors `error_log_io.dart` so read and write
/// agree on where the file lives.
List<String> _candidateDirs() {
  final List<String> dirs = <String>[];
  try {
    dirs.add(File(Platform.resolvedExecutable).parent.path);
  } catch (_) {}
  try {
    dirs.add(Directory.systemTemp.path);
  } catch (_) {}
  dirs.add('.');
  return dirs;
}
