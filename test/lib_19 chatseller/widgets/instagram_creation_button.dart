import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Instagram-style creation button with gradient background and camera icon
/// 
/// This button provides a quick way to access Instagram page creation functionality.
/// It features Instagram's brand gradient colors, circular design, and proper
/// accessibility support.
class InstagramCreationButton extends StatelessWidget {
  /// Callback function executed when the button is pressed
  final VoidCallback onPressed;
  
  /// Whether the button is enabled and interactive
  final bool isEnabled;
  
  /// Optional custom size for the button (defaults to 40x40 pixels)
  final double? size;

  const InstagramCreationButton({
    super.key,
    required this.onPressed,
    this.isEnabled = true,
    this.size,
  });

  /// Instagram brand gradient colors
  static const List<Color> _instagramGradient = [
    Color(0xFF833AB4), // Purple
    Color(0xFFE1306C), // Pink
    Color(0xFFFD1D1D), // Red
    Color(0xFFFC8019), // Orange
  ];

  @override
  Widget build(BuildContext context) {
    final buttonSize = size ?? 40.0;
    
    return Semantics(
      button: true,
      enabled: isEnabled,
      label: 'Create Instagram page',
      hint: 'Tap to create a new Instagram-style page',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? () {
            // Provide haptic feedback on button press
            HapticFeedback.mediumImpact();
            onPressed();
          } : null,
          borderRadius: BorderRadius.circular(buttonSize / 2),
          child: Container(
            width: buttonSize,
            height: buttonSize,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _instagramGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.3, 0.7, 1.0],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _instagramGradient.first.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.camera_alt,
              color: Colors.white,
              size: buttonSize * 0.5, // Icon size is 50% of button size
            ),
          ),
        ),
      ),
    );
  }
}