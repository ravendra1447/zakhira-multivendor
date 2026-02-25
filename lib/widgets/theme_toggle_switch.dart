import 'package:flutter/material.dart';
import '../services/theme_service.dart';

class ThemeToggleSwitch extends StatefulWidget {
  const ThemeToggleSwitch({super.key});

  @override
  State<ThemeToggleSwitch> createState() => _ThemeToggleSwitchState();
}

class _ThemeToggleSwitchState extends State<ThemeToggleSwitch>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  late ThemeService _themeService;

  @override
  void initState() {
    super.initState();
    _themeService = ThemeService();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Initialize animation based on current theme
    if (_themeService.isDarkMode) {
      _animationController.value = 1.0;
    }

    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {
        if (_themeService.isDarkMode) {
          _animationController.forward();
        } else {
          _animationController.reverse();
        }
      });
    }
  }

  void _toggleTheme() {
    _themeService.toggleTheme();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleTheme,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            width: 120,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Light/Dark text labels
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Text(
                      'Light',
                      style: TextStyle(
                        color: _animation.value < 0.5
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Text(
                      'Dark',
                      style: TextStyle(
                        color: _animation.value > 0.5
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                // Sliding toggle button
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  left: _animation.value * (120 - 32 - 8), // (container_width - toggle_width - padding)
                  right: (1 - _animation.value) * (120 - 32 - 8),
                  top: 4,
                  bottom: 4,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _animation.value > 0.5 ? Icons.dark_mode : Icons.light_mode,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
