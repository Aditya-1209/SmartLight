import 'package:flutter/material.dart';

ThemeData smartLightTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff357e69),
        brightness: brightness,
        surface: dark ? const Color(0xff11191b) : const Color(0xfff5f6f2),
      ).copyWith(
        surfaceContainerLow: dark ? const Color(0xff192326) : Colors.white,
        surfaceContainerHighest: dark
            ? const Color(0xff2a3639)
            : const Color(0xffe9eeea),
        primary: dark ? const Color(0xff91d9bb) : const Color(0xff246851),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primary.withValues(alpha: .16),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .4),
      thickness: 1,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .3)),
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
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      bodyMedium: TextStyle(height: 1.5, color: scheme.onSurfaceVariant),
      bodySmall: TextStyle(height: 1.4, color: scheme.onSurfaceVariant),
    ),
  );
}
