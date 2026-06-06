import 'dart:convert';
import 'dart:html' as html;

const String _key = 'pinsel_settings';

/// Read the settings map from `localStorage`. Returns `{}` if absent or if the
/// browser blocks storage (private mode), so startup is never blocked.
Future<Map<String, dynamic>> loadSettings() async {
  try {
    final String? raw = html.window.localStorage[_key];
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (_) {
    // Storage disabled / corrupt — fall through to empty.
  }
  return <String, dynamic>{};
}

/// Persist [settings] to `localStorage`. Swallows quota/security errors.
Future<void> saveSettings(Map<String, dynamic> settings) async {
  try {
    html.window.localStorage[_key] = jsonEncode(settings);
  } catch (_) {
    // Best-effort: private mode / quota exceeded.
  }
}
