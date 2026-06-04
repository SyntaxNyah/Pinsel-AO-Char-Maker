// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web core count from `navigator.hardwareConcurrency`, defaulting to 4 when the
/// browser doesn't report it.
int get cpuCount {
  final int? n = html.window.navigator.hardwareConcurrency;
  return (n == null || n < 1) ? 4 : n;
}
