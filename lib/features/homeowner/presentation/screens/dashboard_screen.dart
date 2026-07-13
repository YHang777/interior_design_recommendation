import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/gradient_scaffold.dart';
import '../../../../shared/widgets/quick_action_button.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Homeowner dashboard — main landing page after login.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return GradientScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // ── Header ──
            _DashboardHeader(userName: user?.name ?? 'User'),
            const SizedBox(height: 24),

            // ── Quick Stats ──
            _QuickStatsSection(context: context),
            const SizedBox(height: 20),

            // ── Notifications ──
            _NotificationsSection(),
            const SizedBox(height: 20),

            // ── Quick Actions ──
            _QuickActionsSection(context: context),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─── Header Widget ───

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.userName});
  final String userName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Avatar
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.person,
            color: AppColors.primary,
            size: 32,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back!',
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                userName,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        // Notification bell
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: Colors.white, size: 22),
            onPressed: () {},
          ),
        ),
      ],
    );
  }
}

// ─── Quick Stats ───

class _QuickStatsSection extends StatelessWidget {
  const _QuickStatsSection({required this.context});
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          StatCard(
            icon: Icons.account_balance_wallet,
            label: 'Budget',
            value: '5.2K',
            gradient: const [Color(0xFF4CAF50), Color(0xFF66BB6A)],
            onTap: () => context.push('/budget'),
          ),
          const SizedBox(width: 12),
          StatCard(
            icon: Icons.shopping_bag,
            label: 'Purchases',
            value: '3',
            gradient: const [Color(0xFF2196F3), Color(0xFF42A5F5)],
            onTap: () => context.push('/marketplace'),
          ),
          const SizedBox(width: 12),
          StatCard(
            icon: Icons.trending_up,
            label: 'Recent',
            value: '2',
            gradient: const [Color(0xFFFF9800), Color(0xFFFFB74D)],
            onTap: () => context.push('/saved'),
          ),
        ],
      ),
    );
  }
}

// ─── Notifications ───

class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Recent Activity',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        _NotificationCard(
          icon: Icons.local_shipping,
          title: 'Order #1234 Shipped!',
          subtitle: 'Your furniture is on the way',
          time: '2 hours ago',
          color: const Color(0xFF4CAF50),
        ),
        const SizedBox(height: 8),
        _NotificationCard(
          icon: Icons.warning,
          title: 'Budget Alert',
          subtitle: 'Kitchen renovation exceeded budget',
          time: 'Yesterday',
          color: const Color(0xFFFF5722),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.brown.shade900)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.brown.shade600)),
              ],
            ),
          ),
          Text(time,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: Colors.brown.shade400)),
        ],
      ),
    );
  }
}

// ─── Quick Actions ───

class _QuickActionsSection extends StatelessWidget {
  const _QuickActionsSection({required this.context});
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.brown.shade900,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              QuickActionButton(
                icon: Icons.camera_alt,
                label: 'Scan Room',
                gradient: const [Color(0xFF9C27B0), Color(0xFFBA68C8)],
                onTap: () => context.go('/scan'),
              ),
              QuickActionButton(
                icon: Icons.psychology,
                label: 'AI Rec',
                gradient: const [Color(0xFF3F51B5), Color(0xFF5C6BC0)],
                onTap: () => context.go('/ai'),
              ),
              QuickActionButton(
                icon: Icons.store,
                label: 'Marketplace',
                gradient: const [Color(0xFF009688), Color(0xFF4DB6AC)],
                onTap: () => context.go('/marketplace'),
              ),
              QuickActionButton(
                icon: Icons.style,
                label: 'Style Library',
                gradient: const [Color(0xFFE91E63), Color(0xFFF48FB1)],
                onTap: () => context.push('/saved'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
