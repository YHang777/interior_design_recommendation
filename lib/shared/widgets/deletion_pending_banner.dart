import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/user_errors.dart';
import '../../features/auth/data/datasources/account_deletion_datasource.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import 'app_feedback.dart';

/// Shows the signed-in user's account-deletion state at the top of the
/// profile screens:
///
/// * `grace` — a warning card with the purge date and **Recover account**;
/// * `pending_email` — a small "check your email" row with **Cancel request****;
/// * `none` / `cancelled` / `purged` — nothing.
///
/// Fetch errors and loading also render nothing: this banner informs, it
/// never blocks. Recovering invalidates [deletionStatusProvider] so the
/// card disappears without a pull-to-refresh.
class DeletionPendingBanner extends ConsumerWidget {
  const DeletionPendingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // valueOrNull: loading (null) and fetch errors (null) both fail silent.
    final status = ref.watch(deletionStatusProvider).valueOrNull;
    if (status == null) return const SizedBox.shrink();

    switch (status.status) {
      case 'grace':
        return _GraceCard(status: status, ref: ref);
      case 'pending_email':
        return _PendingEmailRow(ref: ref);
      default:
        return const SizedBox.shrink();
    }
  }
}

/// `grace`: the emailed link was confirmed — 7 days to recover.
class _GraceCard extends StatelessWidget {
  const _GraceCard({required this.status, required this.ref});

  final DeletionStatus status;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final when = status.purgeAt ?? status.graceUntil;
    final body = when == null
        ? 'Your account is scheduled for deletion. You can recover it '
            'before then.'
        : 'Your account will be deleted on ${Formatters.shortDate(when)}. '
            'You can recover it before then.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account scheduled for deletion',
            style: GoogleFonts.poppins(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => _cancel(
              context,
              ref,
              successMessage: 'Account restored',
              fallback: 'Could not recover the account. Please try again.',
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.textOnDark,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Recover account',
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `pending_email`: the confirmation email is out — offer an early out.
class _PendingEmailRow extends StatelessWidget {
  const _PendingEmailRow({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Deletion requested — check your email to confirm.',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _cancel(
              context,
              ref,
              successMessage: 'Deletion request cancelled.',
              fallback: 'Could not cancel the request. Please try again.',
            ),
            child: Text(
              'Cancel request',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared cancel/recover handler: restore the account, tell the person,
/// then re-fetch the status so the banner clears.
///
/// Errors are shown, never thrown — the banner must not crash the screen
/// that hosts it. The status is re-fetched on failure too: a 404 means the
/// request vanished server-side, and a stale card is the worst outcome.
Future<void> _cancel(
  BuildContext context,
  WidgetRef ref, {
  required String successMessage,
  required String fallback,
}) async {
  try {
    await ref.read(authStateProvider.notifier).cancelAccountDeletion();
    if (!context.mounted) return;
    ref.invalidate(deletionStatusProvider);
    showAppSnackbar(context, successMessage, color: AppColors.success);
  } catch (e) {
    if (!context.mounted) return;
    ref.invalidate(deletionStatusProvider);
    showAppSnackbar(context, userMessage(e, fallback: fallback), isError: true);
  }
}
