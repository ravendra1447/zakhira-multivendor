import 'package:flutter/material.dart';

/// Consistent spacing values across the application
class AppSpacing {
  // Private constructor to prevent instantiation
  AppSpacing._();

  // ============ Spacing Constants ============
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;

  // ============ Padding Helpers ============
  
  static EdgeInsets paddingAll(double value) {
    return EdgeInsets.all(value);
  }

  static EdgeInsets paddingHorizontal(double value) {
    return EdgeInsets.symmetric(horizontal: value);
  }

  static EdgeInsets paddingVertical(double value) {
    return EdgeInsets.symmetric(vertical: value);
  }

  // ============ Margin Helpers ============
  
  static EdgeInsets marginAll(double value) {
    return EdgeInsets.all(value);
  }

  static EdgeInsets marginHorizontal(double value) {
    return EdgeInsets.symmetric(horizontal: value);
  }

  static EdgeInsets marginVertical(double value) {
    return EdgeInsets.symmetric(vertical: value);
  }

  // ============ Common Padding Presets ============
  
  static const EdgeInsets paddingXS = EdgeInsets.all(xs);
  static const EdgeInsets paddingSM = EdgeInsets.all(sm);
  static const EdgeInsets paddingMD = EdgeInsets.all(md);
  static const EdgeInsets paddingLG = EdgeInsets.all(lg);
  static const EdgeInsets paddingXL = EdgeInsets.all(xl);
  static const EdgeInsets paddingXXL = EdgeInsets.all(xxl);

  // ============ Common Margin Presets ============
  
  static const EdgeInsets marginXS = EdgeInsets.all(xs);
  static const EdgeInsets marginSM = EdgeInsets.all(sm);
  static const EdgeInsets marginMD = EdgeInsets.all(md);
  static const EdgeInsets marginLG = EdgeInsets.all(lg);
  static const EdgeInsets marginXL = EdgeInsets.all(xl);
  static const EdgeInsets marginXXL = EdgeInsets.all(xxl);

  // ============ Horizontal Padding Presets ============
  
  static const EdgeInsets paddingHorizontalXS = EdgeInsets.symmetric(horizontal: xs);
  static const EdgeInsets paddingHorizontalSM = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets paddingHorizontalMD = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets paddingHorizontalLG = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets paddingHorizontalXL = EdgeInsets.symmetric(horizontal: xl);
  static const EdgeInsets paddingHorizontalXXL = EdgeInsets.symmetric(horizontal: xxl);

  // ============ Vertical Padding Presets ============
  
  static const EdgeInsets paddingVerticalXS = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets paddingVerticalSM = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets paddingVerticalMD = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets paddingVerticalLG = EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets paddingVerticalXL = EdgeInsets.symmetric(vertical: xl);
  static const EdgeInsets paddingVerticalXXL = EdgeInsets.symmetric(vertical: xxl);

  // ============ Horizontal Margin Presets ============
  
  static const EdgeInsets marginHorizontalXS = EdgeInsets.symmetric(horizontal: xs);
  static const EdgeInsets marginHorizontalSM = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets marginHorizontalMD = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets marginHorizontalLG = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets marginHorizontalXL = EdgeInsets.symmetric(horizontal: xl);
  static const EdgeInsets marginHorizontalXXL = EdgeInsets.symmetric(horizontal: xxl);

  // ============ Vertical Margin Presets ============
  
  static const EdgeInsets marginVerticalXS = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets marginVerticalSM = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets marginVerticalMD = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets marginVerticalLG = EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets marginVerticalXL = EdgeInsets.symmetric(vertical: xl);
  static const EdgeInsets marginVerticalXXL = EdgeInsets.symmetric(vertical: xxl);

  // ============ SizedBox Helpers ============
  
  static const SizedBox verticalSpaceXS = SizedBox(height: xs);
  static const SizedBox verticalSpaceSM = SizedBox(height: sm);
  static const SizedBox verticalSpaceMD = SizedBox(height: md);
  static const SizedBox verticalSpaceLG = SizedBox(height: lg);
  static const SizedBox verticalSpaceXL = SizedBox(height: xl);
  static const SizedBox verticalSpaceXXL = SizedBox(height: xxl);

  static const SizedBox horizontalSpaceXS = SizedBox(width: xs);
  static const SizedBox horizontalSpaceSM = SizedBox(width: sm);
  static const SizedBox horizontalSpaceMD = SizedBox(width: md);
  static const SizedBox horizontalSpaceLG = SizedBox(width: lg);
  static const SizedBox horizontalSpaceXL = SizedBox(width: xl);
  static const SizedBox horizontalSpaceXXL = SizedBox(width: xxl);
}
