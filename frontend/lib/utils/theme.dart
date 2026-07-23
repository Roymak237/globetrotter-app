import "package:flutter/material.dart";

class AppTheme {
  static const Color primary = Color(0xFF2E7D32);
  static const Color secondary = Color(0xFF81C784);
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Colors.white;
  static const Color error = Color(0xFFD32F2F);

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: error,
      ),
      scaffoldBackgroundColor: background,
    );
  }
}
