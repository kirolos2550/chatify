import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController._();

  static final AppThemeController instance = AppThemeController._();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _themeModeKey = 'app_theme_mode';

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    final storedMode = await _storage.read(key: _themeModeKey);
    _themeMode = switch (storedMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    if (mode == ThemeMode.system) {
      await _storage.delete(key: _themeModeKey);
    } else {
      await _storage.write(key: _themeModeKey, value: mode.name);
    }
    notifyListeners();
  }
}
