import 'package:flutter/material.dart';

abstract final class MoyeColors {
  static const ink = Color(0xFF17221D);
  static const pine = Color(0xFF335D4D);
  static const pineSoft = Color(0xFFDCE8E1);
  static const paper = Color(0xFFF5F7F3);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFD9E0DA);
  static const muted = Color(0xFF617068);
  static const amber = Color(0xFFD7A94B);
  static const rose = Color(0xFFC96A5E);
  static const sky = Color(0xFF6F9BB8);
  static const darkSurface = Color(0xFF17201C);
  static const darkPaper = Color(0xFF0F1512);
}

ThemeData moyeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: MoyeColors.pine,
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFF9AC7B4) : MoyeColors.pine,
    onPrimary: dark ? MoyeColors.ink : Colors.white,
    secondary: dark ? const Color(0xFFE3C47F) : const Color(0xFF9A742A),
    surface: dark ? MoyeColors.darkSurface : MoyeColors.surface,
    onSurface: dark ? const Color(0xFFE6EDE8) : MoyeColors.ink,
    outline: dark ? const Color(0xFF3B4841) : MoyeColors.line,
    outlineVariant: dark ? const Color(0xFF2C3731) : const Color(0xFFE8EDE8),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? MoyeColors.darkPaper : MoyeColors.paper,
    fontFamilyFallback: const [
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'Noto Sans CJK SC',
      'PingFang SC',
      'sans-serif',
    ],
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.65),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.55),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: dark ? MoyeColors.darkPaper : MoyeColors.paper,
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1D2822) : const Color(0xFFF0F4EF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: base.textTheme.labelMedium,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: dark ? MoyeColors.darkSurface : MoyeColors.surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: scheme.onSurface.withValues(alpha: 0.6),
        fontSize: 12,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? MoyeColors.darkSurface : MoyeColors.surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.7)),
      ),
    ),
  );
}
