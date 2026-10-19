import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';

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

  final VoidCallback? onCancel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
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
