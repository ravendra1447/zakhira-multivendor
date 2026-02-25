import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:whatsappchat/theme/app_typography.dart';

/// Action button with gradient background
class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final List<Color>? gradientColors;
  final double? height;
  final double? width;
  final bool isLoading;
  final IconData? icon;

  const GradientButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.gradientColors,
    this.height,
    this.width,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final defaultGradient = [
      const Color(0xFF25D366),
      const Color(0xFF128C7E),
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : () {
          HapticFeedback.mediumImpact();
          onPressed();
        },
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: width,
          height: height ?? 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors ?? defaultGradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: (gradientColors?.first ?? defaultGradient.first)
                    .withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        text,
                        style: AppTypography.button(context),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
