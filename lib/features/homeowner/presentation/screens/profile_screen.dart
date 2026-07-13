import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/gradient_scaffold.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Homeowner profile — edit info, change password, reports, delete account.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isHomeowner = user?.isHomeowner ?? true;

    return GradientScaffold(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          // ── Profile Form ──
          _ProfileForm(user: user),
          const SizedBox(height: 20),

          // ── Budget Planning ──
          _BudgetPlanningSection(context: context),
          const SizedBox(height: 20),

          // ── Reports (role-gated) ──
          _ReportsSection(isHomeowner: isHomeowner),
          const SizedBox(height: 20),

          // ── Change Password ──
          _ChangePasswordSection(),
          const SizedBox(height: 20),

          // ── Delete Account ──
          _DeleteAccountSection(ref: ref),
          const SizedBox(height: 20),

          // ── Logout ──
          ElevatedButton.icon(
            onPressed: () => ref.read(authStateProvider.notifier).logout(),
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Logout',
                style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Profile Form ───

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({required this.user});
  final dynamic user; // AppUser?

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  late final _nameCtrl = TextEditingController(text: widget.user?.name ?? '');
  late final _emailCtrl = TextEditingController(text: widget.user?.email ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.user?.phone ?? '');
  late final _addressCtrl = TextEditingController(text: widget.user?.address ?? '');
  String? _profilePic;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _showImagePicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Profile Picture'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _profilePic = 'assets/images/app_logo.jpg');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Photo taken (mocked)')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _profilePic = 'assets/images/app_logo.jpg');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Personal Information',
      child: Column(
        children: [
          // Avatar
          Center(
            child: GestureDetector(
              onTap: _showImagePicker,
              child: CircleAvatar(
                radius: 40,
                backgroundColor: Colors.brown.shade100,
                backgroundImage: _profilePic != null
                    ? AssetImage(_profilePic!)
                    : null,
                child: _profilePic == null
                    ? const Icon(Icons.person, size: 40,
                        color: AppColors.primary)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildField('Full Name', Icons.person, _nameCtrl),
          const SizedBox(height: 14),
          _buildField('Email', Icons.email, _emailCtrl, enabled: false),
          const SizedBox(height: 14),
          _buildField('Phone', Icons.phone, _phoneCtrl),
          const SizedBox(height: 14),
          _buildField('Address', Icons.location_on, _addressCtrl, maxLines: 2),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile saved (mocked)')),
              );
            },
            icon: const Icon(Icons.save),
            label: const Text('Save Changes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, IconData icon, TextEditingController ctrl,
      {bool enabled = true, int maxLines = 1}) {
    return TextFormField(
      controller: ctrl,
      enabled: enabled,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
      style: GoogleFonts.poppins(
          fontSize: 14, color: Colors.brown.shade900),
    );
  }
}

// ─── Budget Planning Section ───

class _BudgetPlanningSection extends StatelessWidget {
  const _BudgetPlanningSection({required this.context});
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Budget Planning',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Plan and track your renovation budget',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.brown.shade600)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/budget'),
              icon: const Icon(Icons.account_balance_wallet),
              label: const Text('Open Budget Planner'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reports Section ───

class _ReportsSection extends StatelessWidget {
  const _ReportsSection({required this.isHomeowner});
  final bool isHomeowner;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Reports',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('View your renovation and spending reports',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.brown.shade600)),
          const SizedBox(height: 12),
          if (isHomeowner) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.design_services),
                label: const Text('Design Analytics Report'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.pie_chart),
                label: const Text('Budget Plan Report'),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.assessment),
                label: const Text('Sales Report'),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Change Password ───

class _ChangePasswordSection extends StatefulWidget {
  @override
  State<_ChangePasswordSection> createState() =>
      _ChangePasswordSectionState();
}

class _ChangePasswordSectionState extends State<_ChangePasswordSection> {
  bool _expanded = false;

  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Change Password',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Update your password',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.brown.shade600)),
                Icon(_expanded
                    ? Icons.expand_less
                    : Icons.expand_more),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 16),
            _buildPwdField('Current Password', _currentCtrl),
            const SizedBox(height: 12),
            _buildPwdField('New Password', _newCtrl),
            const SizedBox(height: 12),
            _buildPwdField('Confirm New Password', _confirmCtrl),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                _showVerificationDialog(context);
              },
              icon: const Icon(Icons.lock_reset),
              label: const Text('Change Password'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPwdField(String label, TextEditingController ctrl) {
    return TextFormField(
      controller: ctrl,
      obscureText: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outlined),
      ),
    );
  }

  void _showVerificationDialog(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Verify Email'),
        content: const Text(
            'A verification code has been sent to your email. '
            'Enter it below to confirm.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _showSuccessDialog(ctx);
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.check_circle,
            color: AppColors.success, size: 48),
        title: const Text('Password Changed!'),
        content: const Text('Your password has been updated successfully.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _expanded = false);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ─── Delete Account ───

class _DeleteAccountSection extends ConsumerWidget {
  const _DeleteAccountSection({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SectionCard(
      title: 'Danger Zone',
      titleColor: Colors.red,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Permanently delete your account and all data',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.brown.shade600)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Account?'),
                    content: const Text(
                        'This action cannot be undone. All your data will be permanently removed.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Account deleted (mocked)')),
                          );
                          ref.read(authStateProvider.notifier).logout();
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                        child: const Text('Delete',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('Delete Account',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared Section Card ───

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.titleColor,
    required this.child,
  });

  final String title;
  final Color? titleColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: titleColor ?? Colors.brown.shade900,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
