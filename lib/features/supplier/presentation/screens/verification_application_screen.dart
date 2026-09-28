import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../services/verification/verification_application_model.dart';
import '../../../../services/verification/verification_application_service.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/float_button.dart';
import '../../../../shared/widgets/page_heading.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/data/models/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../providers/supplier_providers.dart';

/// Supplier verification application — the only place a supplier submits the
/// IC + supporting documents an admin later reviews.
///
/// Four states, driven by the resolved status (profile field merged with the
/// live application stream):
///  - `'none'` / `'rejected'` → the form (rejected shows the admin's note
///    first so the re-application actually addresses it);
///  - `'pending'`            → read-only submitted summary;
///  - `'verified'`           → success state.
class VerificationApplicationScreen extends ConsumerStatefulWidget {
  const VerificationApplicationScreen({super.key});

  @override
  ConsumerState<VerificationApplicationScreen> createState() =>
      _VerificationApplicationScreenState();
}

class _VerificationApplicationScreenState
    extends ConsumerState<VerificationApplicationScreen> {
  final _picker = ImagePicker();

  File? _icFront;
  File? _icBack;
  final List<File> _supporting = [];

  // Inline validation — set on submit when a required image is missing,
  // cleared as soon as the image is picked.
  String? _icFrontError;
  String? _icBackError;
  bool _submitting = false;

  // ── Picking ────────────────────────────────────────────────────────────

  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.photo_camera_outlined, color: AppColors.accent),
              title: Text('Take a photo',
                  style: GoogleFonts.poppins(fontSize: 14)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.accent),
              title: Text('Choose from gallery',
                  style: GoogleFonts.poppins(fontSize: 14)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  /// Runs the picker; returns null for every "no file" outcome (dismissed
  /// sheet, cancelled picker, oversize) after telling the user what
  /// happened — the caller simply keeps its previous state.
  Future<File?> _pickFile() async {
    final source = await _chooseSource();
    if (source == null) return null;

    XFile? picked;
    try {
      // Light quality trim only — IC text must stay legible, so no maxWidth.
      picked = await _picker.pickImage(source: source, imageQuality: 90);
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Could not open the image picker.',
            isError: true, detail: '$e');
      }
      return null;
    }
    if (picked == null) {
      if (mounted) {
        showAppSnackbar(context, 'No image was selected.', isError: true);
      }
      return null;
    }

    final file = File(picked.path);
    final size = await file.length();
    if (size > kMaxVerificationFileBytes) {
      if (mounted) {
        showAppSnackbar(context, 'Images must be 10 MB or smaller.',
            isError: true);
      }
      return null;
    }
    return file;
  }

  Future<void> _pickIcImage({required bool front}) async {
    final file = await _pickFile();
    if (file == null || !mounted) return;
    setState(() {
      if (front) {
        _icFront = file;
        _icFrontError = null;
      } else {
        _icBack = file;
        _icBackError = null;
      }
    });
  }

  Future<void> _addSupporting() async {
    if (_supporting.length >= kMaxVerificationSupportingDocs) return;
    final file = await _pickFile();
    if (file == null || !mounted) return;
    setState(() => _supporting.add(file));
  }

  // ── Submit ─────────────────────────────────────────────────────────────

  Future<void> _submit(AppUser user) async {
    setState(() {
      _icFrontError =
          _icFront == null ? 'Front of your IC is required.' : null;
      _icBackError = _icBack == null ? 'Back of your IC is required.' : null;
    });
    if (_icFront == null || _icBack == null) {
      showAppSnackbar(context, 'Add the required IC images before submitting.',
          isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(verificationApplicationServiceProvider).submitApplication(
            uid: user.uid,
            email: user.email,
            businessName: user.businessName ?? user.name,
            icFront: _icFront!,
            icBack: _icBack!,
            supporting: List.of(_supporting),
          );
      if (!mounted) return;
      // The live application stream flips this screen to the read-only
      // "under review" summary — no navigation needed.
      setState(() {
        _icFront = null;
        _icBack = null;
        _supporting.clear();
      });
      showAppSnackbar(context, 'Verification application submitted',
          color: AppColors.success, duration: const Duration(seconds: 3));
    } on VerificationException catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Could not submit your application',
            isError: true, detail: e.message);
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Could not submit your application',
            isError: true, detail: '$e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final applicationAsync = ref.watch(myVerificationApplicationProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(child: _buildBody(user, applicationAsync)),
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 8,
            left: 8,
            child: const FloatingBackButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    AppUser? user,
    AsyncValue<VerificationApplication?> applicationAsync,
  ) {
    if (user == null) {
      return const Center(
        child: EmptyState(
          icon: Icons.person_off_outlined,
          title: 'Not signed in',
          subtitle: 'Sign in as a supplier to submit a verification '
              'application.',
        ),
      );
    }

    final application = applicationAsync.valueOrNull;
    if (application == null && applicationAsync.hasError) {
      // Resolving the status needs this document — guessing one would risk
      // rendering the form over a pending application.
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load your application',
        subtitle: 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(myVerificationApplicationProvider),
      );
    }
    if (application == null && applicationAsync.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    final status =
        resolveVerificationStatus(user.verificationStatus, application);

    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 60, 16, MediaQuery.paddingOf(context).bottom + 24),
      children: [
        const PageHeading(
          title: 'Supplier Verification',
          subtitle: 'Confirm your identity to earn the Verified badge that '
              'buyers see on your listings.',
        ),
        const SizedBox(height: 16),
        if (status == 'pending')
          _pendingSummary(application)
        else if (status == 'verified')
          _verifiedState()
        else ...[
          if (status == 'rejected') ...[
            _rejectedBanner(application),
            const SizedBox(height: 12),
          ],
          _form(user),
        ],
      ],
    );
  }

  // ── States ─────────────────────────────────────────────────────────────

  Widget _rejectedBanner(VerificationApplication? application) {
    final note = (application?.reviewNote ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cancel_outlined, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.isEmpty
                      ? 'Your application was rejected'
                      : 'Your application was rejected: $note',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Address the feedback above, then re-apply with fresh '
                  'photos of your documents.',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(AppUser user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoCard(),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _icTile(
                title: 'IC front (required)',
                file: _icFront,
                error: _icFrontError,
                onPick: () => _pickIcImage(front: true),
                onRemove: () => setState(() => _icFront = null),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _icTile(
                title: 'IC back (required)',
                file: _icBack,
                error: _icBackError,
                onPick: () => _pickIcImage(front: false),
                onRemove: () => setState(() => _icBack = null),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Supporting documents (optional)',
            style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(
          'Up to $kMaxVerificationSupportingDocs images — business '
          'registration, licences, etc.',
          style:
              GoogleFonts.poppins(fontSize: 11.5, color: AppColors.textHint),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _supporting.length; i++)
          _supportingRow(_supporting[i], () => setState(() => _supporting.removeAt(i))),
        if (_supporting.isNotEmpty) const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _supporting.length >= kMaxVerificationSupportingDocs
              ? null
              : _addSupporting,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: Text('Add supporting document',
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _submitting ? null : () => _submit(user),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text('Submit application',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _infoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What you need to submit',
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(
            '• Clear photos of the front and back of your IC\n'
            '• Optional supporting documents (up to '
            '$kMaxVerificationSupportingDocs)\n'
            '• Each image up to '
            '${kMaxVerificationFileBytes ~/ (1024 * 1024)} MB\n\n'
            'An admin reviews your documents before your listing shows the '
            'Verified badge.',
            style: GoogleFonts.poppins(
                fontSize: 12, color: AppColors.textSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _icTile({
    required String title,
    required File? file,
    required String? error,
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPick,
          child: Container(
            height: 132,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: error != null ? AppColors.error : AppColors.border,
                width: error != null ? 1.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: file == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_a_photo_outlined,
                            color: AppColors.textHint, size: 26),
                        const SizedBox(height: 6),
                        Text('Tap to add',
                            style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                color: AppColors.textHint)),
                      ],
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(file, fit: BoxFit.cover),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _tileAction(Icons.refresh, 'Replace', onPick),
                            const SizedBox(width: 6),
                            _tileAction(Icons.close, 'Remove', onRemove),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.error)),
        ],
      ],
    );
  }

  Widget _tileAction(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      ),
    );
  }

  Widget _supportingRow(File file, VoidCallback onRemove) {
    final name = file.path.split(RegExp(r'[/\\]')).last;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.attachment_outlined,
              size: 18, color: AppColors.textHint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: AppColors.textPrimary),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 18, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _pendingSummary(VerificationApplication? application) {
    final submittedAt = application?.submittedAt;
    final documents = application?.documents ?? const <VerificationDocument>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusBadge.verification('pending'),
              const SizedBox(height: 10),
              Text('Under review by an admin',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(
                'An admin is reviewing your IC and supporting documents. '
                'This page updates automatically once a decision is made — '
                'no need to refresh.',
                style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.5),
              ),
              if (submittedAt != null) ...[
                const SizedBox(height: 10),
                Text('Submitted ${Formatters.shortDateTime(submittedAt.toLocal())}',
                    style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textHint)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Submitted documents',
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        if (application == null)
          // The profile says pending but no application document exists —
          // say so instead of rendering an empty list as if nothing was sent.
          Text(
            'No document details are on file for this application. If this '
            'persists, contact support.',
            style: GoogleFonts.poppins(
                fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
          )
        else
          for (final doc in documents) _documentRow(doc),
      ],
    );
  }

  Widget _documentRow(VerificationDocument doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            switch (doc.kind) {
              kVerificationDocIcFront => Icons.credit_card_outlined,
              kVerificationDocIcBack => Icons.credit_card_outlined,
              _ => Icons.attach_file_outlined,
            },
            size: 18,
            color: AppColors.textHint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_kindLabel(doc.kind),
                    style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textHint)),
                Text(doc.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_formatSize(doc.sizeBytes),
              style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _verifiedState() {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.successLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.verified, size: 48, color: AppColors.success),
        ),
        const SizedBox(height: 16),
        Text('Your business is verified',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(
          'An admin approved your documents. Buyers now see the Verified '
          'badge on your name and listings.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
              fontSize: 13, color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 14),
        StatusBadge.verification('verified'),
      ],
    );
  }

  static String _kindLabel(String kind) => switch (kind) {
        kVerificationDocIcFront => 'IC front',
        kVerificationDocIcBack => 'IC back',
        _ => 'Supporting document',
      };

  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}
