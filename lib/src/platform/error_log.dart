import 'error_log_io.dart' if (dart.library.html) 'error_log_web.dart' as impl;

/// Append a crash/error [message] to a persistent log, so an unreproducible
/// crash in a *built* app becomes a stack trace the user can send back instead
/// of "it crashes a lot". Native writes a file next to the executable (falling
/// back to the temp dir); web logs to the dev console.
///
/// Best-effort and **never throws** — logging a crash must not cause a second
/// one. It can't catch a hard OOM or a native (FFI) segfault, but it captures
/// every Dart-level exception (wired up in `main.dart` via `FlutterError.onError`
/// + `runZonedGuarded`).
Future<void> logCrash(String message) => impl.logCrash(message);

/// Absolute path of the crash log once something has been written (native), or
/// null (web, or nothing logged yet). Shown in-app so users can find it.
String? get crashLogPath => impl.crashLogPath;
