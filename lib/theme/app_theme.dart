import 'package:flutter/material.dart';

/// Centralized theme configuration and management
class AppTheme {
  // Private constructor to prevent instantiation
  AppTheme._();

  /// Theme data for light mode
  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Roboto',
      primaryColor: const Color(0xFF25D366),
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      colorScheme: ColorScheme.light(
        primary: const Color(0xFF25D366),
        secondary: const Color(0xFF075E54),
        surface: Colors.white,
        background: const Color(0xFFF5F5F5),
        error: const Color(0xFFF44336),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: const Color(0xDE000000), // black87 = 87% opacity
        onBackground: const Color(0xDE000000), // black87 = 87% opacity
        onError: Colors.white,
      ),
      cardColor: Colors.white,
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF075E54),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        displayMedium: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        displaySmall: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        headlineLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        headlineMedium: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        headlineSmall: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        titleLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500),
        titleMedium: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500),
        titleSmall: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        bodySmall: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        labelLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500),
        labelMedium: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500),
        labelSmall: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF25D366), width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
    );
  }

  /// Theme data for dark mode
  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Roboto',
      primaryColor: const Color(0xFF25D366),
      scaffoldBackgroundColor: const Color(0xFF121212),
      colorScheme: ColorScheme.dark(
        primary: const Color(0xFF25D366),
        secondary: const Color(0xFF075E54),
        surface: const Color(0xFF1E1E1E),
        background: const Color(0xFF121212),
        error: const Color(0xFFEF5350),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: const Color(0xDEFFFFFF), // white87 = 87% opacity
        onBackground: const Color(0xDEFFFFFF), // white87 = 87% opacity
        onError: Colors.white,
      ),
      cardColor: const Color(0xFF2C2C2C),
      cardTheme: const CardThemeData(
        color: Color(0xFF2C2C2C),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF075E54),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        displayMedium: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        displaySmall: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        headlineLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        headlineMedium: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        headlineSmall: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        titleLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500),
        titleMedium: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500),
        titleSmall: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        bodySmall: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w400),
        labelLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500),
        labelMedium: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500),
        labelSmall: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2C2C2C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF424242)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF424242)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF25D366), width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
    );
  }

  /// Get current theme based on system preference
  static ThemeData getCurrentTheme(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    return brightness == Brightness.dark ? darkTheme() : lightTheme();
  }

  /// Check if current theme is dark
  static bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }
}
