import 'settings_store_io.dart'
    if (dart.library.html) 'settings_store_web.dart' as impl;

/// Tiny key→value persistence for UI preferences that should outlive a session
/// (rebindable keys, etc.). Deliberately dependency-free and behind a platform
/// seam — native writes a small `pinsel_settings.json` next to the executable
/// (same place as the crash log), web uses `localStorage`. Both are best-effort
/// and **never throw**, so a read-only install or a private-mode browser can't
/// break startup.
///
/// Values must be JSON-encodable. Load returns an empty map when nothing's
/// saved yet (or on any error).
Future<Map<String, dynamic>> loadSettings() => impl.loadSettings();

/// Persist the whole [settings] map as JSON. Callers debounce; this just writes.
Future<void> saveSettings(Map<String, dynamic> settings) =>
    impl.saveSettings(settings);
