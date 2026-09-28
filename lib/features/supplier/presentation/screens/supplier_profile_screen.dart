import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/router/route_names.dart';
import '../../../../models/product.dart';
import '../../../../services/verification/verification_application_model.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/page_heading.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/data/models/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../customer/marketplace/presentation/providers/marketplace_providers.dart';
import '../providers/supplier_providers.dart';

/// Supplier profile — matching homeowner design with centered avatar,
/// left-border section cards, and edit/view toggle.
class SupplierProfileScreen extends ConsumerStatefulWidget {
  const SupplierProfileScreen({super.key});

  @override
  ConsumerState<SupplierProfileScreen> createState() =>
      _SupplierProfileScreenState();
}

class _SupplierProfileScreenState
    extends ConsumerState<SupplierProfileScreen> {
  bool _editing = false;
  bool _saving = false;
  late TextEditingController _businessNameCtrl;
  late TextEditingController _businessPhoneCtrl;
  late TextEditingController _businessAddressCtrl;

  @override
  void initState() {
    super.initState();
    _businessNameCtrl = TextEditingController();
    _businessPhoneCtrl = TextEditingController();
    _businessAddressCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _businessPhoneCtrl.dispose();
    _businessAddressCtrl.dispose();
    super.dispose();
  }

  void _startEditing(AppUser user) {
    final supplier = supplierFromUser(user);
    _businessNameCtrl.text = supplier.name;
    _businessPhoneCtrl.text = user.businessPhone ?? user.phone ?? '';
    _businessAddressCtrl.text = user.businessAddress ?? user.address ?? '';
    setState(() => _editing = true);
  }

  Future<void> _save(AppUser user) async {
    final name = _businessNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Business name cannot be empty'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(authStateProvider.notifier).updateProfile(
            name: user.name,
            phone: user.phone,
            address: user.address,
            businessName: name,
            businessPhone: _businessPhoneCtrl.text.trim(),
            businessAddress: _businessAddressCtrl.text.trim(),
          );
      if (mounted) {
        setState(() => _editing = false);
        showAppSnackbar(
          context,
          'Business profile updated',
          color: AppColors.success,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Could not save your profile',
            isError: true,
            detail: e.toString(),
            duration: const Duration(seconds: 3));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancelEditing() {
    setState(() => _editing = false);
  }

  Future<void> _changePassword() async {
    final user = ref.read(currentUserProvider);
    final email = user?.email ?? '';
    if (email.isEmpty) {
      showAppSnackbar(context, 'No email on file', isError: true);
      return;
    }
    // Same shared helper as Log out / Delete: long half-width buttons,
    // centered pair, 16px gap (a bespoke AlertDialog here once again
    // produced narrow, touching buttons).
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset Password?',
      message: 'A password reset link will be sent to $email. '
          'Check your inbox after a few minutes.',
      confirmLabel: 'Send Reset Link',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(authStateProvider.notifier).sendPasswordResetEmail(email);
      if (mounted) {
        showAppSnackbar(
          context,
          'Password reset email sent to $email',
          color: AppColors.success,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
          context,
          'Could not send reset email',
          isError: true,
          detail: e.toString(),
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need to sign in again to manage your store.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(authStateProvider.notifier).logout();
    } catch (_) {
      if (mounted) {
        showAppSnackbar(context, 'Could not log out — try again',
            isError: true, duration: const Duration(seconds: 3));
      }
    }
  }

  // ── Verification ───────────────────────────────────────────────────────

  void _goVerification() =>
      context.pushNamed(RouteNames.supplierVerification);

  /// Badge action for the current verification status — the one place the
  /// "what can I do now" choice lives, so it always matches the state
  /// machine (`none`/`rejected` may apply, `pending` is read-only).
  Widget _verificationAction(AppUser user, VerificationApplication? application) {
    final status =
        resolveVerificationStatus(user.verificationStatus, application);
    switch (status) {
      case 'verified':
        return const SizedBox.shrink();
      case 'pending':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.schedule, size: 14, color: AppColors.warning),
              const SizedBox(width: 6),
              Text('Application under review',
                  style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning)),
            ],
          ),
        );
      case 'rejected':
        final note = (application?.reviewNote ?? '').trim();
        return Column(
          children: [
            if (note.isNotEmpty) ...[
              Text(
                'Rejected: $note',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 11.5, color: AppColors.error, height: 1.4),
              ),
              const SizedBox(height: 6),
            ],
            _verificationButton(label: 'Re-apply'),
          ],
        );
      default: // 'none' — never applied
        return _verificationButton(label: 'Apply for verification');
    }
  }

  /// Rendered only for statuses the state machine allows ('none'/'rejected'),
  /// so the button is always live.
  Widget _verificationButton({required String label}) {
    return OutlinedButton.icon(
      onPressed: _goVerification,
      icon: const Icon(Icons.badge_outlined, size: 16),
      label: Text(label,
          style:
              GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final supplier = user == null ? null : supplierFromUser(user);
    // Live application document: the stored profile status only refreshes
    // with the session, so the admin's decision lands here first.
    final application =
        ref.watch(myVerificationApplicationProvider).valueOrNull;
    final verificationStatus = user == null
        ? 'none'
        : resolveVerificationStatus(user.verificationStatus, application);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: user == null || supplier == null
            ? const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'Not signed in',
                subtitle: 'Sign in as a supplier to view your profile.',
              )
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(marketplaceProductsProvider);
                },
                color: AppColors.accent,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                      16, 16, 16, MediaQuery.paddingOf(context).bottom + 24),
                  children: [
                    const PageHeading(title: 'Profile'),
                    const SizedBox(height: 16),
                    // ── Avatar with gradient ring ──
                    Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.accent, AppColors.accentLight],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 38,
                            backgroundColor: AppColors.primary,
                            child: Text(
                              _initials(supplier.name),
                              style: GoogleFonts.poppins(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textOnDark),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (!_editing) ...[
                          Text(supplier.name,
                              style: GoogleFonts.poppins(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          Text(user.email,
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 4),
                          StatusBadge.verification(verificationStatus),
                          const SizedBox(height: 8),
                          if (user.isSupplier)
                            _verificationAction(user, application),
                          const SizedBox(height: 14),
                          // Edit profile button
                          SizedBox(
                            height: 38,
                            child: OutlinedButton.icon(
                              onPressed: () => _startEditing(user),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: Text('Edit Profile',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13, fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Business profile ──
                  _SectionCard(
                    title: 'Business Profile',
                    accentColor: AppColors.accent,
                    subtitle: 'Shown on your listings and to buyers',
                    children: _editing
                        ? [
                            _EditField(Icons.storefront_outlined,
                                'Business Name', _businessNameCtrl),
                            _EditField(Icons.phone_outlined, 'Business Phone',
                                _businessPhoneCtrl,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ]),
                            _EditField(Icons.location_on_outlined,
                                'Business Address', _businessAddressCtrl,
                                maxLines: 2),
                          ]
                        : [
                            _Field(Icons.storefront_outlined, 'Business Name',
                                supplier.name),
                            _Field(
                                Icons.phone_outlined,
                                'Business Phone',
                                user.businessPhone ??
                                    user.phone ??
                                    'Not set'),
                            _Field(
                                Icons.location_on_outlined,
                                'Business Address',
                                user.businessAddress ??
                                    user.address ??
                                    'Not set'),
                          ],
                  ),
                  const SizedBox(height: 16),

                  // ── Store info ──
                  if (!_editing) ...[
                    _SectionCard(
                      title: 'Your Store',
                      accentColor: AppColors.secondaryAccent,
                      children: [
                        _Field(Icons.verified_outlined, 'Verification',
                            StatusBadge.verificationLabel(verificationStatus)),
                        _Field(
                            Icons.inventory_2_outlined,
                            'Products Listed',
                            '${productsOfSupplier(productsAsync.valueOrNull ?? const <Product>[], user.uid).length}'),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Edit actions ──
                  if (_editing) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving ? null : _cancelEditing,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saving ? null : () => _save(user),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Account ──
                  if (!_editing) ...[
                    _SectionCard(
                      title: 'Account',
                      accentColor: AppColors.textHint,
                      children: [
                        _LinkRow(Icons.password_outlined, 'Change Password',
                            _changePassword),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Logout ──
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 52),
                      child: OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout, color: AppColors.error),
                        label: const Text('Logout',
                            style: TextStyle(color: AppColors.error)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.error),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Delete account ──
                    TextButton(
                      onPressed: () async {
                        final confirmed = await showConfirmDialog(
                          context,
                          title: 'Delete Account?',
                          message:
                              'This action cannot be undone. All your data will be permanently removed.',
                          confirmLabel: 'Delete',
                          destructive: true,
                        );
                        if (confirmed) {
                          ref.read(authStateProvider.notifier).logout();
                        }
                      },
                      child: Text('Delete Account',
                          style: GoogleFonts.poppins(
                              color: AppColors.error, fontSize: 13)),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String initial(String s) => s.substring(0, 1).toUpperCase();
    if (parts.length == 1) return initial(parts.first);
    return initial(parts.first) + initial(parts.last);
  }
}

/// ── Section card with left accent border (matching homeowner) ──────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.accentColor = AppColors.accent,
    this.subtitle,
  });

  final String title;
  final List<Widget> children;
  final Color accentColor;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: accentColor, width: 3),
        ),
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
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppColors.textHint)),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// ── View-mode field row ────────────────────────────────────────────────

class _Field extends StatelessWidget {
  const _Field(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textHint),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// ── Edit-mode text field row ───────────────────────────────────────────

class _EditField extends StatelessWidget {
  const _EditField(this.icon, this.label, this.controller,
      {this.keyboardType, this.inputFormatters, this.maxLines = 1});

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textHint),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              maxLines: maxLines,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.accent, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ── Link row (tappable, for Account section) ──────────────────────────

class _LinkRow extends StatelessWidget {
  const _LinkRow(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: AppColors.textPrimary)),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }
}
