import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData light() {
    const primary = Color(0xFF233B8B);
    const secondary = Color(0xFF0C8F9C);
    const accent = Color(0xFFE9734A);
    const background = Color(0xFFF3F5F8);

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      tertiary: accent,
      brightness: Brightness.light,
      surface: Colors.white,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      useMaterial3: true,
    );
  }

  static ThemeData dark() {
    const primary = Color(0xFF7FA8FF);
    const secondary = Color(0xFF48C5D6);
    const accent = Color(0xFFFF9A6C);
    const background = Color(0xFF0E1626);
    const surface = Color(0xFF162033);

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      tertiary: accent,
      brightness: Brightness.dark,
      surface: surface,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: surface,
      ),
      cardTheme: const CardThemeData(color: surface),
      dividerColor: Colors.white12,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      useMaterial3: true,
    );
  }
}
