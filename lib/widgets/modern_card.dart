import 'package:flutter/material.dart';
import 'package:whatsappchat/theme/app_colors.dart';
import 'package:whatsappchat/theme/app_spacing.dart';

/// Reusable card component with consistent styling
class ModernCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double? elevation;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final Border? border;

  const ModernCard({
    super.key,
    required this.child,
    this.padding,
    this.elevation,
    this.backgroundColor,
    this.borderRadius,
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultElevation = isDark ? 4.0 : 2.0;
    final defaultBorderRadius = BorderRadius.circular(12);

    final cardWidget = Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.card(context),
        borderRadius: borderRadius ?? defaultBorderRadius,
        border: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
            blurRadius: elevation ?? defaultElevation,
            offset: Offset(0, (elevation ?? defaultElevation) / 2),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? AppSpacing.paddingLG,
        child: child,
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? defaultBorderRadius,
        child: cardWidget,
      );
    }

    return cardWidget;
  }
}
