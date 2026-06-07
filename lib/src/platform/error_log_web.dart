import 'dart:developer' as developer;

/// Web has no writable file next to an "executable"; surface to the dev console
/// (visible in the browser's devtools) instead.
String? get crashLogPath => null;

/// No on-disk location on web (logs go to the browser console).
Future<String?> crashLogDir() async => null;

Future<void> logCrash(String message) async {
  developer.log(message, name: 'pinsel.crash', level: 1000);
}
