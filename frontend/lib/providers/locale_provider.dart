import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../localization/app_localizations.dart";

class LocaleProvider extends ChangeNotifier {
  static const _storageKey = "app_locale";

  Locale _locale = const Locale("en");
  bool _isLoaded = false;

  Locale get locale => _locale;
  bool get isLoaded => _isLoaded;
  List<Locale> get supportedLocales => AppLocalizations.supportedLocales;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final storedCode = preferences.getString(_storageKey);
    if (storedCode != null && _isSupported(storedCode)) {
      _locale = Locale(storedCode);
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (!_isSupported(locale.languageCode) || locale == _locale) return;

    _locale = Locale(locale.languageCode);
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, _locale.languageCode);
  }

  bool _isSupported(String languageCode) => supportedLocales.any(
        (supported) => supported.languageCode == languageCode,
      );
}
