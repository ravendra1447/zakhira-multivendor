import 'package:flutter/material.dart';
import 'package:whatsappchat/theme/app_colors.dart';
import 'package:whatsappchat/theme/app_typography.dart';
import 'package:whatsappchat/theme/app_spacing.dart';

/// Modern chip-style filter button
class FilterChipWidget extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  const FilterChipWidget({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 36,
            padding: AppSpacing.paddingHorizontalMD,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary(context)
                  : Colors.transparent,
              border: Border.all(
                color: AppColors.primary(context),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : AppColors.primary(context),
                  ),
                  AppSpacing.horizontalSpaceSM,
                ],
                Text(
                  label,
                  style: AppTypography.label(context).copyWith(
                    color: isSelected
                        ? Colors.white
                        : AppColors.primary(context),
                    fontWeight: AppTypography.medium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
