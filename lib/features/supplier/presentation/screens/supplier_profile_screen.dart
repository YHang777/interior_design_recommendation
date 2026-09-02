import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../models/product.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/data/models/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../providers/supplier_providers.dart';

/// Supplier profile — editable business identity (threaded into every
/// product they publish), verification badge, account actions.
class SupplierProfileScreen extends ConsumerStatefulWidget {
  const SupplierProfileScreen({super.key});

  @override
  ConsumerState<SupplierProfileScreen> createState() =>
      _SupplierProfileScreenState();
}

class _SupplierProfileScreenState
    extends ConsumerState<SupplierProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _businessNameCtrl;
  late final TextEditingController _businessPhoneCtrl;
  late final TextEditingController _businessAddressCtrl;
  bool _saving = false;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    final supplier = user == null ? null : supplierFromUser(user);
    _businessNameCtrl = TextEditingController(text: supplier?.name ?? '');
    _businessPhoneCtrl =
        TextEditingController(text: user?.businessPhone ?? user?.phone ?? '');
    _businessAddressCtrl = TextEditingController(
        text: user?.businessAddress ?? user?.address ?? '');
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _businessPhoneCtrl.dispose();
    _businessAddressCtrl.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _save(AppUser user) async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _attempted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final notifier = ref.read(authStateProvider.notifier);
    try {
      await notifier.updateProfile(
        name: user.name,
        phone: user.phone,
        address: user.address,
        businessName: _businessNameCtrl.text.trim(),
        businessPhone: _businessPhoneCtrl.text.trim(),
        businessAddress: _businessAddressCtrl.text.trim(),
      );
      if (mounted) {
        showAppSnackbar(
          context,
          'Profile updated — new listings carry these business details',
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

  Future<void> _changePassword() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Change password',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Password changes are handled from the sign-in screen — use '
          '"Forgot password?" to reset your password. Changing it in-app '
          'is coming in a future update.',
          style: GoogleFonts.poppins(
            fontSize: 13.5,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
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
      // Router redirects to /login automatically once signed out.
    } catch (_) {
      if (mounted) {
        showAppSnackbar(context, 'Could not log out — try again',
            isError: true, duration: const Duration(seconds: 3));
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final supplier = user == null ? null : supplierFromUser(user);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Store profile')),
      body: user == null || supplier == null
          ? const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Not signed in',
              subtitle: 'Sign in as a supplier to view your profile.',
            )
          : RefreshIndicator(
              onRefresh: () async {
                try {
                  final _ =
                      await ref.refresh(marketplaceProductsProvider.future);
                } catch (_) {}
              },
              color: AppColors.accent,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // ── Identity header ──
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.primaryLight],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _initials(supplier.name),
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                supplier.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textOnDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  color:
                                      Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge.verification(user.verificationStatus),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Business profile form ──
                  _sectionCard(
                    title: 'Business profile',
                    subtitle:
                        'Shown on your listings and to buyers at checkout',
                    child: Form(
                      key: _formKey,
                      autovalidateMode: _attempted
                          ? AutovalidateMode.always
                          : AutovalidateMode.disabled,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ProfileField(
                            label: 'Business name',
                            icon: Icons.storefront_outlined,
                            controller: _businessNameCtrl,
                            hint: 'e.g. Nordic Living Sdn Bhd',
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return 'Business name is required';
                              if (t.length < 2) {
                                return 'Name is too short';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _ProfileField(
                            label: 'Business phone',
                            icon: Icons.phone_outlined,
                            controller: _businessPhoneCtrl,
                            hint: 'e.g. 0123456789',
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return null;
                              if (t.length < 9 || t.length > 12) {
                                return 'Enter a valid Malaysian phone number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _ProfileField(
                            label: 'Business address',
                            icon: Icons.location_on_outlined,
                            controller: _businessAddressCtrl,
                            hint: 'Pickup / return address',
                            maxLines: 2,
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return null;
                              if (t.length < 5) {
                                return 'Address is too short';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _saving
                                  ? null
                                  : () => _save(user),
                              child: _saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : const Text('Save changes'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Store snapshot ──
                  _sectionCard(
                    title: 'Your store',
                    child: Column(
                      children: [
                        _infoRow(
                          icon: Icons.verified_outlined,
                          label: 'Verification status',
                          valueWidget:
                              StatusBadge.verification(user.verificationStatus),
                        ),
                        Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.divider),
                        _infoRow(
                          icon: Icons.inventory_2_outlined,
                          label: 'Products listed',
                          value: '${productsOfSupplier(
                              productsAsync.valueOrNull ?? const <Product>[],
                              user.uid).length}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Account ──
                  _sectionCard(
                    title: 'Account',
                    child: Column(
                      children: [
                        _actionRow(
                          icon: Icons.password_outlined,
                          label: 'Change password',
                          color: AppColors.textPrimary,
                          onTap: _changePassword,
                        ),
                        Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.divider),
                        _actionRow(
                          icon: Icons.logout_outlined,
                          label: 'Log out',
                          color: AppColors.error,
                          onTap: _logout,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.textHint,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    String? value,
    Widget? valueWidget,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (valueWidget != null)
            valueWidget
          else if (value != null)
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
          ],
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

/// ── Profile text field (dark label + filled box) ────────────────────────

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.icon,
    required this.controller,
    required this.hint,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String hint;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon,
            color: AppColors.textSecondary, size: 19),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: maxLines > 1 ? 12 : 16,
        ),
      ),
    );
  }
}
