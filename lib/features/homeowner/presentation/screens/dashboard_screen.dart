import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final name = user?.name ?? 'User';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hello, $name',
                style: GoogleFonts.poppins(
                    fontSize: 20, fontWeight: FontWeight.bold,
                    color: AppColors.textOnDark)),
            Text("Let's design your dream home",
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.textOnDark
                        .withValues(alpha: 0.7))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.textOnDark),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats
            Row(
              children: [
                _StatCard(
                    icon: Icons.account_balance_wallet,
                    label: 'Budget',
                    value: 'RM 5.2K',
                    color: AppColors.success),
                const SizedBox(width: 12),
                _StatCard(
                    icon: Icons.shopping_bag,
                    label: 'Purchases',
                    value: '3',
                    color: AppColors.secondaryAccent),
                const SizedBox(width: 12),
                _StatCard(
                    icon: Icons.bookmark,
                    label: 'Saved',
                    value: '2',
                    color: AppColors.warning),
              ],
            ),
            const SizedBox(height: 24),

            // Quick Actions
            Text('Quick Actions',
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Row(
              children: [
                _ActionCard(
                    icon: Icons.camera_alt, label: 'Scan', color: const Color(0xFF7B1FA2),
                    onTap: () => context.go('/scan')),
                const SizedBox(width: 12),
                _ActionCard(
                    icon: Icons.psychology, label: 'AI Design', color: const Color(0xFF1565C0),
                    onTap: () => context.go('/ai')),
                const SizedBox(width: 12),
                _ActionCard(
                    icon: Icons.store, label: 'Shop', color: const Color(0xFF2E7D32),
                    onTap: () => context.go('/marketplace')),
                const SizedBox(width: 12),
                _ActionCard(
                    icon: Icons.palette, label: 'Styles', color: const Color(0xFFE91E63),
                    onTap: () => context.push('/saved')),
              ],
            ),
            const SizedBox(height: 24),

            // Recent Activity
            Text('Recent Activity',
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8)],
              ),
              child: Column(
                children: [
                  _ActivityRow(Icons.local_shipping,
                      'Order #1234 Shipped', 'Your furniture is on the way', '2h ago',
                      AppColors.success),
                  const Divider(height: 20),
                  _ActivityRow(Icons.warning, 'Budget Alert',
                      'Kitchen renovation over budget', 'Yesterday', AppColors.warning),
                  const Divider(height: 20),
                  _ActivityRow(Icons.design_services,
                      'New design saved', 'Modern Living Room', '2 days ago', AppColors.secondaryAccent),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: color, width: 3)),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
          ),
          child: Column(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.icon, this.title, this.subtitle, this.time, this.color);
  final IconData icon;
  final String title, subtitle, time;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary)),
              Text(subtitle,
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Text(time,
            style: GoogleFonts.poppins(
                fontSize: 11, color: AppColors.textHint)),
      ],
    );
  }
}
