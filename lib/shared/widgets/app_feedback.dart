import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  // Pick icon prefix based on type
  final iconData = isError ? Icons.error : Icons.check_circle;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: duration,
      backgroundColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: effectiveColor,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: isError
                  ? AppColors.errorLight
                  : AppColors.successLight,
              width: 4,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: effectiveColor.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(iconData, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    actionLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
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
