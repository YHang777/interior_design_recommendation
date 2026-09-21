import 'package:flutter/material.dart';

/// Modern Minimal design palette.
/// Clean whites, dark charcoal, forest green accents.
class AppColors {
  AppColors._();

  // Primary — dark charcoal/navy
  static const Color primary = Color(0xFF1A1A2E);
  static const Color primaryLight = Color(0xFF2D2D44);

  // Accent — forest green (CTAs, active states)
  static const Color accent = Color(0xFF2E7D32);
  static const Color accentLight = Color(0xFF4CAF50);
  static const Color accentDark = Color(0xFF1B5E20);

  // Secondary accent — navy blue (links)
  static const Color secondaryAccent = Color(0xFF1565C0);

  // Backgrounds
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Colors.white;
  static const Color surfaceElevated = Color(0xFFFAFBFC);
  static const Color surfaceContainer = Color(0xFFF3F4F6);

  // Text
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFF9CA3AF);
  static const Color textOnDark = Colors.white;

  // Status
  static const Color success = Color(0xFF2E7D32);
  static const Color error = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);

  // Status backgrounds
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color errorLight = Color(0xFFFFEBEE);
  static const Color warningLight = Color(0xFFFFF8E1);

  // Lighter secondary stops for StatCard/QuickActionButton gradients and
  // bar charts (pairs with the primary status colors above).
  static const Color gradientGreen = Color(0xFF66BB6A);
  static const Color gradientBlue = Color(0xFF42A5F5);
  static const Color gradientOrange = Color(0xFFFFB74D);
  static const Color gradientRed = Color(0xFFEF5350);

  // Borders & dividers
  static const Color border = Color(0xFFE5E7EB);
  static const Color divider = Color(0xFFF3F4F6);

  // Skeleton / shimmer
  static const Color shimmer = Color(0xFFE5E7EB);
  static const Color shimmerHighlight = Color(0xFFF3F4F6);

  // Glass / frosted effects
  static const Color glass = Color(0x80FFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);
}
