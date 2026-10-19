import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';

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

class FloatingBackButton extends StatelessWidget {
  const FloatingBackButton({
    super.key,
    this.onTap,
    this.background,
    this.iconColor,
    this.tooltip = 'Back',
  });

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
