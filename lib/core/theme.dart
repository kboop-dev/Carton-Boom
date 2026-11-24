import 'package:flutter/material.dart';

class AppTheme {
  static const brand = Color(0xFFB07030); // cartón
  static const brandDark = Color(0xFF6B4423);

  static ThemeData light() => _base(ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.light));
  static ThemeData dark() => _base(ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.dark));

  static ThemeData _base(ColorScheme cs) => ThemeData(
        useMaterial3: true,
        colorScheme: cs,
        scaffoldBackgroundColor: cs.brightness == Brightness.light ? const Color(0xFFF6F3EE) : null,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      );
}
