import 'package:flutter/material.dart';

ThemeData smartLightTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff24786a),
    brightness: brightness,
    surface: dark ? const Color(0xff101916) : const Color(0xfff5f7f3),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: .35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      ),
    ),
    textTheme: TextTheme(
      headlineLarge: const TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
      headlineMedium: const TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: -.7,
      ),
      titleLarge: const TextStyle(fontWeight: FontWeight.w600),
      labelLarge: const TextStyle(fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(height: 1.45, color: scheme.onSurfaceVariant),
    ),
  );
}
