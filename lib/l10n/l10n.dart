import 'package:flutter/material.dart';

abstract final class L10n {
  static const supportedLocales = [Locale('ar'), Locale('en')];
}

Locale? localeResolution(Locale? locale, Iterable<Locale> supported) {
  if (locale == null) {
    return const Locale('en');
  }

  for (final candidate in supported) {
    if (candidate.languageCode == locale.languageCode) {
      return candidate;
    }
  }
  return const Locale('en');
}
