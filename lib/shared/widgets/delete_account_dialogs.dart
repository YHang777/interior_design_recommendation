import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/user_errors.dart';
import 'app_feedback.dart';
import 'confirm_dialog.dart';

const kDeleteAccountPhrase = 'DELETE MY ACCOUNT';

bool deletionPhraseMatches(String typed) =>
    typed.trim().toUpperCase() == kDeleteAccountPhrase;

Future<bool> showDeleteAccountFlow(
  BuildContext context, {
  required String confirmEmail,
  required Future<void> Function(String confirmEmail) onSubmit,
}) async {
  if (confirmEmail.trim().isEmpty) {
    showAppSnackbar(context, 'No email on file.', isError: true);
    return false;
  }

  final warned = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      icon: const Icon(
        Icons.warning_rounded,
        size: 40,
        color: AppColors.error,
      ),
      title: Text(
        'Delete your account?',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Your profile, saved designs, cart and wishlist will be '
            'deleted. Your order history is kept, but made anonymous.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'We will email you a confirmation link. The link works for '
            '24 hours. After you confirm, you have 7 days to recover '
            'your account.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        ConfirmDialogActions(
          confirmLabel: 'Continue',
          destructive: true,
          onCancel: () => Navigator.pop(ctx, false),
          onConfirm: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  if (warned != true || !context.mounted) return false;

  final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => const _TypeToConfirmDialog(),
      ) ??
      false;
  if (!confirmed || !context.mounted) return false;

  try {
    await onSubmit(confirmEmail);
    return true;
  } catch (e) {
    if (context.mounted) {
      showAppSnackbar(
        context,
        userMessage(e, fallback: 'Could not start account deletion. Please try again.'),
        isError: true,
      );
    }
    return false;
  }
}

class _TypeToConfirmDialog extends StatefulWidget {
  const _TypeToConfirmDialog();

  @override
  State<_TypeToConfirmDialog> createState() => _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState extends State<_TypeToConfirmDialog> {
  String _typed = '';

  bool get _matches => deletionPhraseMatches(_typed);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      icon: const Icon(
        Icons.warning_rounded,
        size: 40,
        color: AppColors.error,
      ),
      title: Text(
        'Confirm deletion',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Type the phrase below to continue.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (value) => setState(() => _typed = value),
            decoration: const InputDecoration(
              labelText: 'Confirmation phrase',
              hintText: kDeleteAccountPhrase,
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        _ConfirmDialogActions(
          confirmLabel: 'Request deletion',
          destructive: true,
          enabled: _matches,
          onCancel: () => Navigator.pop(context, false),
          onConfirm: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

class _ConfirmDialogActions extends StatelessWidget {
  const _ConfirmDialogActions({
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    required this.enabled,
    this.destructive = false,
  });

  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final confirm = ElevatedButton(
      onPressed: enabled ? onConfirm : null,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: destructive ? AppColors.error : AppColors.accent,
        foregroundColor: AppColors.textOnDark,
        disabledBackgroundColor: AppColors.error.withValues(alpha: 0.35),
        disabledForegroundColor: AppColors.textOnDark.withValues(alpha: 0.8),
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
        'Cancel',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );

    return Row(
      children: [
        Expanded(child: cancel),
        const SizedBox(width: 16),
        Expanded(child: confirm),
      ],
    );
  }
}
