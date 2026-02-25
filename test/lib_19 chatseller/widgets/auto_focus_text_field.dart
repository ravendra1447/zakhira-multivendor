import 'package:flutter/material.dart';
import 'package:whatsappchat/theme/app_colors.dart';
import 'package:whatsappchat/theme/app_typography.dart';
import 'package:whatsappchat/theme/app_spacing.dart';

/// Text field with auto-focus capability
class AutoFocusTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool isLastField;
  final Function(String)? onFieldComplete;
  final String? Function(String?)? validator;
  final int? maxLines;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  const AutoFocusTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.focusNode,
    this.nextFocusNode,
    this.isLastField = false,
    this.onFieldComplete,
    this.validator,
    this.maxLines = 1,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  State<AutoFocusTextField> createState() => _AutoFocusTextFieldState();
}

class _AutoFocusTextFieldState extends State<AutoFocusTextField> {
  bool _hasFocus = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _hasFocus = widget.focusNode?.hasFocus ?? false;
    });
  }

  void _onChanged(String value) {
    // Validate input
    if (widget.validator != null) {
      setState(() {
        _errorText = widget.validator!(value);
      });

      // If validation passes and field is complete, move to next field
      if (_errorText == null && value.isNotEmpty) {
        if (widget.onFieldComplete != null) {
          widget.onFieldComplete!(value);
        }

        // Auto-focus next field
        if (!widget.isLastField && widget.nextFocusNode != null) {
          Future.delayed(const Duration(milliseconds: 100), () {
            widget.nextFocusNode!.requestFocus();
          });
        } else if (widget.isLastField) {
          // Unfocus keyboard on last field
          widget.focusNode?.unfocus();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTypography.label(context),
        ),
        AppSpacing.verticalSpaceSM,
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: _hasFocus
                ? [
                    BoxShadow(
                      color: AppColors.primary(context).withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            keyboardType: widget.keyboardType,
            maxLines: widget.maxLines,
            obscureText: widget.obscureText,
            onChanged: _onChanged,
            style: AppTypography.bodyMedium(context),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: AppTypography.bodyMedium(context).copyWith(
                color: AppColors.textHint(context),
              ),
              prefixIcon: widget.prefixIcon,
              suffixIcon: widget.suffixIcon,
              errorText: _errorText,
              filled: true,
              fillColor: AppColors.surface(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppColors.border(context),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppColors.border(context),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppColors.primary(context),
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppColors.error(context),
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppColors.error(context),
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
