import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Avatar + name
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    (user?.name ?? 'U')[0].toUpperCase(),
                    style: GoogleFonts.poppins(
                        fontSize: 28, fontWeight: FontWeight.bold,
                        color: AppColors.textOnDark),
                  ),
                ),
                const SizedBox(height: 12),
                Text(user?.name ?? 'User',
                    style: GoogleFonts.poppins(
                        fontSize: 20, fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                Text(user?.email ?? '',
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Personal Info Card
          _SectionCard(title: 'Personal Information', children: [
            _Field('Full Name', user?.name ?? 'User'),
            _Field('Email', user?.email ?? ''),
            _Field('Phone', user?.phone ?? 'Not set'),
            _Field('Address', user?.address ?? 'Not set'),
          ]),
          const SizedBox(height: 16),

          // Quick Links
          _SectionCard(title: 'Tools', children: [
            _LinkRow(Icons.account_balance_wallet, 'Budget Planner',
                () => context.push('/budget')),
            _LinkRow(Icons.assessment, 'Reports', () {}),
          ]),
          const SizedBox(height: 16),

          // Settings
          _SectionCard(title: 'Settings', children: [
            _LinkRow(Icons.lock_outline, 'Change Password', () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Password change emailed (mocked)')),
              );
            }),
          ]),
          const SizedBox(height: 16),

          // Logout
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => ref.read(authStateProvider.notifier).logout(),
              icon: const Icon(Icons.logout, color: AppColors.error),
              label: const Text('Logout',
                  style: TextStyle(color: AppColors.error)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Delete
          TextButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete Account?'),
                  content: const Text('This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        ref.read(authStateProvider.notifier).logout();
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error),
                      child: const Text('Delete',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
            child: Text('Delete Account',
                style: GoogleFonts.poppins(
                    color: AppColors.error, fontSize: 13)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.accent, size: 22),
        title: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 14, color: AppColors.textPrimary)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
        onTap: onTap,
      ),
    );
  }
}
