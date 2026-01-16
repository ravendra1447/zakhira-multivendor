import 'package:flutter/material.dart';

/// Centralized color definitions and management
class AppColors {
  // Private constructor to prevent instantiation
  AppColors._();

  // ============ Primary Colors ============
  static const Color _primaryLight = Color(0xFF25D366);
  static const Color _primaryDark = Color(0xFF25D366);
  
  static const Color _primaryDarkShade = Color(0xFF128C7E);
  static const Color _secondaryColor = Color(0xFF075E54);

  // ============ Background Colors ============
  static const Color _backgroundLight = Color(0xFFF5F5F5);
  static const Color _backgroundDark = Color(0xFF121212);
  
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _surfaceDark = Color(0xFF1E1E1E);
  
  static const Color _cardLight = Color(0xFFFFFFFF);
  static const Color _cardDark = Color(0xFF2C2C2C);

  // ============ Text Colors ============
  static const Color _textPrimaryLight = Color(0xDE000000); // 87% opacity
  static const Color _textPrimaryDark = Color(0xDEFFFFFF); // 87% opacity
  
  static const Color _textSecondaryLight = Color(0x99000000); // 60% opacity
  static const Color _textSecondaryDark = Color(0x99FFFFFF); // 60% opacity
  
  static const Color _textHintLight = Color(0x61000000); // 38% opacity
  static const Color _textHintDark = Color(0x61FFFFFF); // 38% opacity

  // ============ Border Colors ============
  static const Color _borderLight = Color(0xFFE0E0E0);
  static const Color _borderDark = Color(0xFF424242);
  
  static const Color _dividerLight = Color(0xFFE0E0E0);
  static const Color _dividerDark = Color(0xFF424242);

  // ============ Semantic Colors ============
  static const Color _successLight = Color(0xFF4CAF50);
  static const Color _successDark = Color(0xFF66BB6A);
  
  static const Color _errorLight = Color(0xFFF44336);
  static const Color _errorDark = Color(0xFFEF5350);
  
  static const Color _warningLight = Color(0xFFFF9800);
  static const Color _warningDark = Color(0xFFFFA726);
  
  static const Color _infoLight = Color(0xFF2196F3);
  static const Color _infoDark = Color(0xFF42A5F5);

  // ============ Custom Colors ============
  static const Color _pinkLight = Color(0xFFE91E63);
  static const Color _pinkDark = Color(0xFFF06292);
  
  static const Color _orangeLight = Color(0xFFFF6F00);
  static const Color _orangeDark = Color(0xFFFF8F00);

  // ============ Helper Methods ============
  static bool _isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  // ============ Primary Colors ============
  static Color primary(BuildContext context) {
    return _isDarkMode(context) ? _primaryDark : _primaryLight;
  }

  static Color primaryDark(BuildContext context) {
    return _primaryDarkShade;
  }

  static Color primaryLight(BuildContext context) {
    return _primaryLight.withOpacity(0.7);
  }

  // ============ Secondary Colors ============
  static Color secondary(BuildContext context) {
    return _secondaryColor;
  }

  static Color accent(BuildContext context) {
    return primary(context);
  }

  // ============ Semantic Colors ============
  static Color success(BuildContext context) {
    return _isDarkMode(context) ? _successDark : _successLight;
  }

  static Color error(BuildContext context) {
    return _isDarkMode(context) ? _errorDark : _errorLight;
  }

  static Color warning(BuildContext context) {
    return _isDarkMode(context) ? _warningDark : _warningLight;
  }

  static Color info(BuildContext context) {
    return _isDarkMode(context) ? _infoDark : _infoLight;
  }

  // ============ Background Colors ============
  static Color background(BuildContext context) {
    return _isDarkMode(context) ? _backgroundDark : _backgroundLight;
  }

  static Color surface(BuildContext context) {
    return _isDarkMode(context) ? _surfaceDark : _surfaceLight;
  }

  static Color card(BuildContext context) {
    return _isDarkMode(context) ? _cardDark : _cardLight;
  }

  // ============ Text Colors ============
  static Color textPrimary(BuildContext context) {
    return _isDarkMode(context) ? _textPrimaryDark : _textPrimaryLight;
  }

  static Color textSecondary(BuildContext context) {
    return _isDarkMode(context) ? _textSecondaryDark : _textSecondaryLight;
  }

  static Color textHint(BuildContext context) {
    return _isDarkMode(context) ? _textHintDark : _textHintLight;
  }

  // ============ Border Colors ============
  static Color border(BuildContext context) {
    return _isDarkMode(context) ? _borderDark : _borderLight;
  }

  static Color divider(BuildContext context) {
    return _isDarkMode(context) ? _dividerDark : _dividerLight;
  }

  // ============ Custom Colors ============
  static Color pink(BuildContext context) {
    return _isDarkMode(context) ? _pinkDark : _pinkLight;
  }

  static Color orange(BuildContext context) {
    return _isDarkMode(context) ? _orangeDark : _orangeLight;
  }
}
