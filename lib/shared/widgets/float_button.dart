import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';

/// Round circular overlay button used for floating controls (back / AR /
/// wishlist). Promoted from `product_detail_screen.dart`'s private `_FloatButton`.
class FloatButton extends StatelessWidget {
  const FloatButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.iconColor = Colors.white,
    this.background,
    this.size = 48,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color iconColor;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background ?? AppColors.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
        ),
      ),
    );
  }
}

/// iOS-style floating back control for header-less pushed screens.
///
/// Defaults to a solid white circle with a dark arrow so it stays readable over
/// light page content. Dark/photo pages pass [background]/[iconColor] to match.
class FloatingBackButton extends StatelessWidget {
  const FloatingBackButton({
    super.key,
    this.onTap,
    this.background,
    this.iconColor,
    this.tooltip = 'Back',
  });

  /// Defaults to `context.pop()`. Pass a custom callback when the screen can be
  /// deep-linked without pop history.
  final VoidCallback? onTap;
  final Color? background;
  final Color? iconColor;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return FloatButton(
      icon: Icons.arrow_back,
      onTap: onTap ?? () => context.pop(),
      tooltip: tooltip,
      background: background ?? AppColors.surface,
      iconColor: iconColor ?? AppColors.textPrimary,
    );
  }
}
