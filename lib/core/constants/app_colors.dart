import 'package:flutter/material.dart';

/// Centralized color palette extracted from the existing design.
/// Prevents hardcoded Color(0xFF...) scattered across the codebase.
class AppColors {
  AppColors._();

  // Primary palette — soft warm browns
  static const Color primary = Color(0xFFBCAAA4);
  static const Color primaryLight = Color(0xFFD7CCC8);
  static const Color primaryLighter = Color(0xFFEFEBE9);

  // Secondary — teal accent
  static const Color secondary = Color(0xFF80CBC4);

  // Backgrounds
  static const Color background = Color(0xFFF8F6F1);
  static const Color surface = Colors.white;

  // Text
  static Color textPrimary = Colors.brown.shade900;
  static Color textSecondary = Colors.brown.shade700;
  static Color textHint = Colors.brown.shade300;
  static const Color textOnPrimary = Colors.white;

  // Status
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFE53935);
  static const Color warning = Color(0xFFFFA726);

  // Misc
  static const Color divider = Color(0xFFE0E0E0);
  static Color greyLight = Colors.grey.shade200;
  static Color greyMedium = Colors.grey.shade400;
}
