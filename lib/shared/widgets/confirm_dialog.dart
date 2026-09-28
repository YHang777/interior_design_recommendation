import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';

/// Shared confirmation dialog used before destructive actions (deleting a
/// product, cancelling an order, discarding form changes, logging out).
///
/// Resolves to `true` when the user confirms, `false` when they cancel or
/// dismiss. A `destructive` confirm is rendered in [AppColors.error]; the
/// default confirm style uses [AppColors.accent].
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      icon: Icon(
        destructive ? Icons.warning_rounded : Icons.help_outline_rounded,
        size: 40,
        color: destructive ? AppColors.error : AppColors.accent,
      ),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 13.5,
          color: AppColors.textSecondary,
          height: 1.4,
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        ConfirmDialogActions(
          confirmLabel: confirmLabel,
          destructive: destructive,
          onCancel: () => Navigator.pop(ctx, false),
          onConfirm: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// The action row for every dialog in the app: two **long** buttons, the
/// pair centred as a group, with a real gap between them.
///
/// Use this as the sole child of `AlertDialog.actions` so no screen can
/// drift back to the narrow 110px pair. Each button is an `Expanded`, so it
/// fills half the dialog width; the 16px [SizedBox] is the visible spacing
/// between Cancel and the action.
///
/// Why not bare buttons: the theme's `ElevatedButton` sets
/// `minimumSize: Size(double.infinity, 52)`, so an unconstrained button
/// computes an infinite min-width and [OverflowBar] stacks the two of them
/// vertically, right-aligned — which is what made the old Logout dialog look
/// wrong. `Expanded` bounds each button to half the width and keeps them
/// side by side.
class ConfirmDialogActions extends StatelessWidget {
  const ConfirmDialogActions({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.onCancel,
    this.cancelLabel = 'Cancel',
    this.destructive = false,
  });

  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;

  /// Optional: omit to render the confirm button alone across the full
  /// width (for single-action dialogs).
  final VoidCallback? onCancel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    // 48px with 10px vertical padding: a tighter height squeezes the label
    // box below Poppins' ~22px line height and clips descenders (the 'g'
    // in "Sign In" bug).
    final confirm = ElevatedButton(
      onPressed: onConfirm,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: destructive ? AppColors.error : AppColors.accent,
        foregroundColor: AppColors.textOnDark,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        confirmLabel,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );

    final cancel = OutlinedButton(
      onPressed: onCancel,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        cancelLabel,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );

    if (onCancel == null) return confirm;

    return Row(
      children: [
        Expanded(child: cancel),
        const SizedBox(width: 16),
        Expanded(child: confirm),
      ],
    );
  }
}
