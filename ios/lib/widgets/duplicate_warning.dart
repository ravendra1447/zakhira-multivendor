import 'package:flutter/material.dart';
import 'package:whatsappchat/theme/app_colors.dart';
import 'package:whatsappchat/theme/app_typography.dart';
import 'package:whatsappchat/theme/app_spacing.dart';

/// High-contrast warning message for duplicate detection
class DuplicateWarning extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  final bool isDismissible;

  const DuplicateWarning({
    super.key,
    required this.message,
    this.onDismiss,
    this.isDismissible = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: AppSpacing.marginHorizontalLG,
      padding: AppSpacing.paddingMD,
      decoration: BoxDecoration(
        color: AppColors.warning(context).withOpacity(0.15),
        border: Border.all(
          color: AppColors.warning(context),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_rounded,
            color: AppColors.warning(context),
            size: 24,
          ),
          AppSpacing.horizontalSpaceMD,
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium(context).copyWith(
                color: AppColors.warning(context),
                fontWeight: AppTypography.semibold,
              ),
            ),
          ),
          if (isDismissible && onDismiss != null) ...[
            AppSpacing.horizontalSpaceSM,
            GestureDetector(
              onTap: onDismiss,
              child: Icon(
                Icons.close,
                color: AppColors.warning(context),
                size: 20,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
