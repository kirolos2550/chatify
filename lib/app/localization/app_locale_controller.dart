import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppLocaleController extends ChangeNotifier {
  AppLocaleController._();

  static final AppLocaleController instance = AppLocaleController._();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _localeKey = 'app_locale_code';

  Locale? _locale;

  Locale? get locale => _locale;
  String get localeCode => _locale?.languageCode ?? 'system';

  Future<void> load() async {
    final code = await _storage.read(key: _localeKey);
    if (code != null && (code == 'ar' || code == 'en')) {
      _locale = Locale(code);
    } else {
      _locale = null;
    }
    notifyListeners();
  }

  Future<void> setSystemLocale() async {
    _locale = null;
    await _storage.delete(key: _localeKey);
    notifyListeners();
  }

  Future<void> setLocaleCode(String code) async {
    if (code != 'ar' && code != 'en') {
      await setSystemLocale();
      return;
    }
    _locale = Locale(code);
    await _storage.write(key: _localeKey, value: code);
    notifyListeners();
  }
}
