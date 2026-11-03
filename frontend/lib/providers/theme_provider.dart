import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Device preference, deliberately independent of sign-in/sign-out.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({Future<SharedPreferences> Function()? loadPreferences})
      : _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _loadPreferences;
  static const preferenceKey = "theme_mode";
  ThemeMode _mode = ThemeMode.dark;
  bool _disposed = false;
  int _revision = 0;
  Future<void> _pendingWrite = Future<void>.value();

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final revision = _revision;
    try {
      final preferences = await _loadPreferences();
      final stored = preferences.getString(preferenceKey);
      if (_disposed || revision != _revision) return;
      _mode = stored == "light" ? ThemeMode.light : ThemeMode.dark;
      notifyListeners();
    } catch (_) {
      // Unavailable or corrupt storage must not prevent app startup.
    }
  }

  Future<void> toggle() => setMode(isDark ? ThemeMode.light : ThemeMode.dark);

  Future<void> setMode(ThemeMode mode) {
    // This is an explicit two-mode preference, not a system-following mode.
    final next = mode == ThemeMode.light ? ThemeMode.light : ThemeMode.dark;
    if (_disposed || next == _mode) return _pendingWrite;
    _revision++;
    _mode = next;
    notifyListeners();
    // Serialize rapid toggles so the final selection is the last disk write.
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        final preferences = await _loadPreferences();
        await preferences.setString(preferenceKey, next.name);
      } catch (_) {
        // Retain the usable in-memory preference when storage is unavailable.
      }
    });
    return _pendingWrite;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
