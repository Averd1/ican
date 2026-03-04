import 'package:flutter/material.dart';

/// iCan App — Accessibility-focused theme.
///
/// High contrast, large text, designed for visually impaired users.
/// Every interactive element has semantic labels for screen readers.
class ICanTheme {
  ICanTheme._();

  // Brand colors
  static const Color primaryBlue = Color(0xFF1565C0);
  static const Color accentOrange = Color(0xFFFF8F00);
  static const Color surfaceDark = Color(0xFF121212);
  static const Color surfaceCard = Color(0xFF1E1E1E);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0BEC5);
  static const Color success = Color(0xFF66BB6A);
  static const Color error = Color(0xFFEF5350);

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: surfaceDark,
    colorScheme: const ColorScheme.dark(
      primary: primaryBlue,
      secondary: accentOrange,
      surface: surfaceCard,
      error: error,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      bodyLarge: TextStyle(fontSize: 20, color: textPrimary),
      bodyMedium: TextStyle(fontSize: 18, color: textSecondary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: textPrimary,
        minimumSize: const Size(double.infinity, 64),
        textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceDark,
      foregroundColor: textPrimary,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
    ),
  );
}
