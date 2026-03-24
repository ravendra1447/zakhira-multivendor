import 'package:flutter/material.dart';
import 'package:whatsappchat/theme/app_colors.dart';

/// Centralized font and text style management
class AppTypography {
  // Private constructor to prevent instantiation
  AppTypography._();

  // ============ Font Weights ============
  static const FontWeight light = FontWeight.w300;
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  // ============ Heading Styles ============
  
  /// Heading 1: 24px, semibold
  static TextStyle heading1(BuildContext context) {
    return TextStyle(
      fontSize: 24,
      fontWeight: semibold,
      color: AppColors.textPrimary(context),
      height: 1.3,
    );
  }

  /// Heading 2: 20px, semibold
  static TextStyle heading2(BuildContext context) {
    return TextStyle(
      fontSize: 20,
      fontWeight: semibold,
      color: AppColors.textPrimary(context),
      height: 1.3,
    );
  }

  /// Heading 3: 18px, medium
  static TextStyle heading3(BuildContext context) {
    return TextStyle(
      fontSize: 18,
      fontWeight: medium,
      color: AppColors.textPrimary(context),
      height: 1.4,
    );
  }

  // ============ Body Text Styles ============
  
  /// Body Large: 16px, regular
  static TextStyle bodyLarge(BuildContext context) {
    return TextStyle(
      fontSize: 16,
      fontWeight: regular,
      color: AppColors.textPrimary(context),
      height: 1.5,
    );
  }

  /// Body Medium: 14px, regular
  static TextStyle bodyMedium(BuildContext context) {
    return TextStyle(
      fontSize: 14,
      fontWeight: regular,
      color: AppColors.textPrimary(context),
      height: 1.5,
    );
  }

  /// Body Small: 12px, regular
  static TextStyle bodySmall(BuildContext context) {
    return TextStyle(
      fontSize: 12,
      fontWeight: regular,
      color: AppColors.textSecondary(context),
      height: 1.5,
    );
  }

  // ============ Special Styles ============
  
  /// Caption: 11px, regular
  static TextStyle caption(BuildContext context) {
    return TextStyle(
      fontSize: 11,
      fontWeight: regular,
      color: AppColors.textSecondary(context),
      height: 1.4,
    );
  }

  /// Button: 14px, medium
  static TextStyle button(BuildContext context) {
    return const TextStyle(
      fontSize: 14,
      fontWeight: medium,
      color: Colors.white,
      height: 1.2,
      letterSpacing: 0.5,
    );
  }

  /// Label: 13px, medium
  static TextStyle label(BuildContext context) {
    return TextStyle(
      fontSize: 13,
      fontWeight: medium,
      color: AppColors.textSecondary(context),
      height: 1.4,
    );
  }

  // ============ Custom Variants ============
  
  /// Price text style: bold and prominent
  static TextStyle price(BuildContext context) {
    return TextStyle(
      fontSize: 20,
      fontWeight: bold,
      color: AppColors.primary(context),
      height: 1.2,
    );
  }

  /// Discount text style: smaller, strikethrough
  static TextStyle discount(BuildContext context) {
    return TextStyle(
      fontSize: 14,
      fontWeight: regular,
      color: AppColors.textSecondary(context),
      decoration: TextDecoration.lineThrough,
      height: 1.2,
    );
  }

  /// Error text style
  static TextStyle error(BuildContext context) {
    return TextStyle(
      fontSize: 12,
      fontWeight: regular,
      color: AppColors.error(context),
      height: 1.4,
    );
  }

  /// Success text style
  static TextStyle success(BuildContext context) {
    return TextStyle(
      fontSize: 12,
      fontWeight: regular,
      color: AppColors.success(context),
      height: 1.4,
    );
  }
}
