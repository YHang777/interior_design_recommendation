import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';

/// Large in-body page title replacing the removed AppBar header.
///
/// Carries no horizontal padding of its own — place it as the first child of a
/// screen's padded scroll column so it lines up with the rest of the content.
class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.titleStyle,
  });

  final String title;
  final String? subtitle;

  /// Trailing controls (former `AppBar.actions`) — icon buttons, text buttons,
  /// gradient chips.
  final List<Widget>? actions;

  /// Rare override for dynamic titles (e.g. wishlist count, AI style name).
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: titleStyle ??
                    GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                      height: 1.2,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions != null && actions!.isNotEmpty) ...[
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions!.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                actions![i],
              ],
            ],
          ),
        ],
      ],
    );
  }
}
