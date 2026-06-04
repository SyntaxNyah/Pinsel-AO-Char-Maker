import 'dart:io';

String? _path;
String? get crashLogPath => _path;

/// Append [message] to `pinsel_crash.log`, trying the executable's folder first
/// (most discoverable) then the system temp dir then the cwd, so a read-only
/// install location can't stop it. Swallows all errors.
Future<void> logCrash(String message) async {
  final String line = '[${DateTime.now().toIso8601String()}] $message\n\n';
  for (final String dir in _candidateDirs()) {
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
