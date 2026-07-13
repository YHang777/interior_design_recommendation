import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/gradient_scaffold.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

class SupplierProfileScreen extends ConsumerWidget {
  const SupplierProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return GradientScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView(
        children: [
          const SizedBox(height: 20),
          // Avatar
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Colors.white,
              child: Icon(Icons.store, size: 40, color: Colors.brown.shade400),
            ),
          ),
          const SizedBox(height: 12),
          Text(user?.name ?? 'Supplier',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(user?.email ?? '',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white.withValues(alpha: 0.8))),
          const SizedBox(height: 24),

          // Business Info
          _SectionCard(title: 'Business Information', children: [
            _Field('Business Name', user?.name ?? 'Elegant Interiors Co.'),
            _Field('Email', user?.email ?? 'contact@elegantinteriors.com'),
            _Field('Phone', user?.phone ?? '+60 12-345 6789'),
            _Field('Address', user?.address ?? 'Kuala Lumpur, Malaysia'),
          ]),
          const SizedBox(height: 16),

          // Change Password
          _SectionCard(title: 'Change Password', children: [
            const Text('Update your account password',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password change emailed (mocked)')),
                );
              },
              icon: const Icon(Icons.lock_reset),
              label: const Text('Change Password'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // Logout
          ElevatedButton.icon(
            onPressed: () => ref.read(authStateProvider.notifier).logout(),
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Logout', style: TextStyle(color: Colors.white)),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.brown.shade900)),
          const SizedBox(height: 14),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text('$label: ', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey)),
          Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.brown.shade900))),
        ],
      ),
    );
  }
}
