import 'dart:async';

import 'package:flutter/foundation.dart'; // FlutterExceptionHandler (not re-exported by material)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/app.dart';
import 'src/platform/error_log.dart';
import 'src/ui/app_state.dart';

void main() {
  // Catch *everything* and log it: framework errors (FlutterError.onError) and
  // uncaught async errors (the runZonedGuarded handler). Turns an
  // unreproducible "it crashes a lot" in a built app into a stack trace the user
  // can send back (written to pinsel_crash.log next to the exe). This can't
  // catch a hard OOM or a native segfault — but it catches every Dart exception.
  runZonedGuarded<void>(() {
    WidgetsFlutterBinding.ensureInitialized();
    // Startup breadcrumb (fire-and-forget): guarantees the log file exists and is
    // writable, so the in-app viewer always shows *something* (proving the
    // plumbing works), and a crash on any screen leaves at least this marker.
    logCrash('session start ${DateTime.now().toIso8601String()}');
    final FlutterExceptionHandler? original = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      original?.call(details); // keep the default (console / red box in debug)
      logCrash('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
    };
    runApp(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(),
        child: const PinselApp(),
      ),
    );
  }, (Object error, StackTrace stack) {
    logCrash('Uncaught: $error\n$stack');
  });
}
