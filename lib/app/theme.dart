import 'package:flutter/material.dart';

abstract final class LightPalette {
  static const background = Color(0xff101716);
  static const surface = Color(0xff192320);
  static const raised = Color(0xff232f2b);
  static const line = Color(0xff35433d);
  static const text = Color(0xfff3f5ef);
  static const muted = Color(0xffabb8ae);
  static const mint = Color(0xffbde6ce);
  static const ink = Color(0xff14261c);
  static const warm = Color(0xffedca93);
  static const purple = Color(0xffcdbcef);
  static const blue = Color(0xffaacbee);
}

ThemeData smartLightTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: LightPalette.mint,
        brightness: brightness,
      ).copyWith(
        surface: dark ? LightPalette.background : const Color(0xfff3f5ef),
        surfaceContainerLow: dark ? LightPalette.surface : Colors.white,
        surfaceContainerHighest: dark
            ? LightPalette.raised
            : const Color(0xffe7ece4),
        primary: dark ? LightPalette.mint : const Color(0xff356448),
        onPrimary: dark ? LightPalette.ink : Colors.white,
        onSurface: dark ? LightPalette.text : LightPalette.ink,
        onSurfaceVariant: dark ? LightPalette.muted : const Color(0xff526359),
        outlineVariant: dark ? LightPalette.line : const Color(0xffd0dacf),
      );
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 88,
      elevation: 0,
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.surfaceContainerHighest,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          color: scheme.onSurfaceVariant,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide.none,
      selectedColor: scheme.surfaceContainerHighest,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 6,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.outlineVariant,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      padding: const EdgeInsets.symmetric(horizontal: 10),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.outlineVariant,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.onSurfaceVariant,
      ),
    ),
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -.8,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -.6,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
    ),
  );
}
