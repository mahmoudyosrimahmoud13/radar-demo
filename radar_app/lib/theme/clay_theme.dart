import 'package:flutter/material.dart';

/// Claymorphism palette and ThemeData for the whole app: soft pastel
/// background, puffy rounded surfaces, dual soft shadows (light from the
/// top-left, dark from the bottom-right) rather than flat material cards.
class ClayColors {
  static const background = Color(0xFFE6E7EE);
  static const surface = Color(0xFFE6E7EE); // same as bg -- clay "pops" via shadow, not color contrast
  static const primary = Color(0xFF6C63FF);
  static const danger = Color(0xFFFF6B6B);
  static const success = Color(0xFF4ECCA3);
  static const warning = Color(0xFFFFB84C);
  static const textPrimary = Color(0xFF3A3A4A);
  static const textSecondary = Color(0xFF8A8AA3);

  static const shadowLight = Color(0xFFFFFFFF);
  static const shadowDark = Color(0xFFA3A6B5);
}

ThemeData buildClayTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: ClayColors.background,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: ClayColors.primary,
      surface: ClayColors.surface,
      brightness: Brightness.light,
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        color: ClayColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      bodyMedium: TextStyle(color: ClayColors.textPrimary),
      bodySmall: TextStyle(color: ClayColors.textSecondary),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ClayColors.background,
      foregroundColor: ClayColors.textPrimary,
      elevation: 0,
      centerTitle: true,
    ),
  );
}
