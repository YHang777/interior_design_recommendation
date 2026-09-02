import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Uniform floating-snackbar helpers used across the marketplace screens.
/// Every mutation gives feedback (design rule) — these keep the look
/// consistent and replace any stale snackbar before showing a new one.
///
/// Both variants render identically; [showAppSnackbarOn] exists for call
/// sites that must show feedback AFTER popping the screen that owns the
/// (now unmounted) BuildContext — pass the captured ScaffoldMessengerState
/// there.

/// Shows a floating [SnackBar] with [message]. Themed via [color] (default
/// accent); an optional [actionLabel]/[onAction] pair renders a
/// SnackBarAction. [isError] paints the bar with [AppColors.error] and wins
/// over [color]; [detail] is appended to the message ("... (detail)").
void showAppSnackbar(
  BuildContext context,
  String message, {
  Color color = AppColors.accent,
  Duration duration = const Duration(seconds: 2),
  String? actionLabel,
  VoidCallback? onAction,
  bool isError = false,
  String? detail,
}) {
  showAppSnackbarOn(
    ScaffoldMessenger.of(context),
    message,
    color: color,
    duration: duration,
    actionLabel: actionLabel,
    onAction: onAction,
    isError: isError,
    detail: detail,
  );
}

/// [showAppSnackbar] against an already-captured [ScaffoldMessengerState] —
/// for contexts that are no longer mounted by the time feedback is shown.
void showAppSnackbarOn(
  ScaffoldMessengerState messenger,
  String message, {
  Color color = AppColors.accent,
  Duration duration = const Duration(seconds: 2),
  String? actionLabel,
  VoidCallback? onAction,
  bool isError = false,
  String? detail,
}) {
  final effectiveColor = isError ? AppColors.error : color;
  final text = detail == null ? message : '$message ($detail)';
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: effectiveColor,
      behavior: SnackBarBehavior.floating,
      duration: duration,
      action: actionLabel == null || onAction == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              textColor: Colors.white,
              onPressed: onAction,
            ),
    ),
  );
}

/// "Added to cart" feedback with a "View cart" shortcut action.
void showAddedToCartSnack(
  BuildContext context,
  String message, {
  VoidCallback? onViewCart,
}) {
  showAppSnackbar(
    context,
    message,
    color: AppColors.success,
    duration: const Duration(seconds: 3),
    actionLabel: onViewCart == null ? null : 'View cart',
    onAction: onViewCart,
  );
}
