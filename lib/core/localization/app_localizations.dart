import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'en_dict.dart';
import 'hi_dict.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': enDict,
    'hi': hiDict,
  };

  String translate(String key) {
    final lang = locale.languageCode;
    return _localizedValues[lang]?[key] ?? _localizedValues['en']?[key] ?? key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'hi'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension LocalizationExtension on BuildContext {
  String tr(String key) {
    return AppLocalizations.of(this)?.translate(key) ?? key;
  }
}

class LanguageManager {
  static final ValueNotifier<Locale> localeNotifier = ValueNotifier<Locale>(
    _getInitialLocale(),
  );

  static Locale _getInitialLocale() {
    try {
      final deviceLocale = ui.PlatformDispatcher.instance.locale;
      if (deviceLocale.languageCode == 'hi') {
        return const Locale('hi');
      }
    } catch (_) {
      // safe fallback
    }
    return const Locale('en');
  }

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedLang = prefs.getString('selected_language');
      if (cachedLang != null && cachedLang.isNotEmpty) {
        localeNotifier.value = Locale(cachedLang);
      }
    } catch (_) {
      // ignore
    }
  }

  static Future<void> setLocale(Locale locale) async {
    localeNotifier.value = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_language', locale.languageCode);
    } catch (_) {
      // ignore
    }
  }
}
