import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/page_heading.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../budget/data/budget_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../../data/stats/customer_stats.dart';
import '../../data/stats/stats_providers.dart';
import '../providers/design_providers.dart';

/// Homeowner dashboard — every stat and the Recent Activity feed come from
/// the shared stats layer (`homeowner/data/stats/`), which computes them
/// from live backend sources. Loading shows '…', failure shows '—' or a
/// retry card, and an empty account shows a real empty state: this screen
/// never renders placeholder numbers.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  /// Metric formatting: keep loading, error and real data distinct.
  static String _countValue(AsyncValue<int> value) => value.when(
        data: (v) => '$v',
        loading: () => '…',
        error: (_, __) => '—',
      );

  /// Budget tile: 'RM 4,200' once a plan exists, 'RM —' when none has been
  /// saved (or loading/failed) — never a fabricated figure.
  static String _budgetValue(CustomerStats stats) => stats.budget.when(
        data: (_) => stats.budgetLabel,
        loading: () => '…',
        error: (_, __) => '—',
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final name = user?.name ?? 'User';
    final stats = ref.watch(customerStatsProvider);

    // Time-appropriate greeting
    final hour = DateTime.now().hour;
    final greeting = switch (hour) {
      < 12 => 'Good Morning',
      < 17 => 'Good Afternoon',
      _ => 'Good Evening',
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      // Edge-to-edge display (SystemChrome in main.dart): the status bar
      // overlays page content, so the scroll column must start below it —
      // exactly how profile_screen.dart does it (SafeArea + 16px). Without
      // the inset the greeting slid under the phone's notification bar.
      // Bottom stays manual: the floating nav bar overlays the content.
      body: SafeArea(
        top: true,
        bottom: false,
        child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.paddingOf(context).bottom + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeading(
              title: '$greeting, $name',
              subtitle: 'Ready to design your space?',
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined,
                      color: AppColors.textPrimary),
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Welcome banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Let's design your dream home",
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        const SizedBox(height: 4),
                        Text('Start by scanning a room or browsing styles',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.8))),
                      ],
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        color: Colors.white, size: 24),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Stats — all computed by customerStatsProvider (see
            // homeowner/data/stats/stats_providers.dart for sources).
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                      icon: Icons.account_balance_wallet,
                      label: 'Budget',
                      value: _budgetValue(stats),
                      gradientColors: [AppColors.success, AppColors.gradientGreen]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                      icon: Icons.shopping_bag,
                      label: 'Purchases',
                      value: _countValue(stats.purchases),
                      gradientColors: [AppColors.secondaryAccent, AppColors.gradientBlue]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                      icon: Icons.bookmark,
                      label: 'Saved Designs',
                      value: _countValue(stats.savedDesigns),
                      gradientColors: [AppColors.warning, AppColors.gradientOrange]),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Quick Actions
            Text('Quick Actions',
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                      icon: Icons.dashboard,
                      label: 'Design',
                      gradientColors: const [Color(0xFF7B1FA2), Color(0xFFAB47BC)],
                      onTap: () => context.push('/design-editor')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionCard(
                      icon: Icons.psychology,
                      label: 'AI Design',
                      gradientColors: const [Color(0xFF1565C0), Color(0xFF42A5F5)],
                      onTap: () => context.push('/ai')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                      icon: Icons.store,
                      label: 'Shop',
                      gradientColors: const [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                      onTap: () => context.push('/marketplace')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionCard(
                      icon: Icons.palette,
                      label: 'Styles',
                      gradientColors: const [Color(0xFFE91E63), Color(0xFFEF5350)],
                      onTap: () => context.push('/saved')),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Recent Activity — real orders + saved designs only.
            Text('Recent Activity',
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            const _RecentActivity(),
            const SizedBox(height: 24),
          ],
        ),
      ),
      ),
    );
  }
}

// ─── Recent Activity ──────────────────────────────────────────────────────────

/// Renders `recentActivityProvider`: loading spinner, retryable error
/// card, proper empty state, or the real feed. Never invents rows.
class _RecentActivity extends ConsumerWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(recentActivityProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: activity.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (_, __) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load activity',
          subtitle: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: () {
            ref.invalidate(customerOrdersProvider);
            ref.invalidate(savedDesignsProvider);
            ref.invalidate(budgetPlanProvider);
          },
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const EmptyState(
              icon: Icons.timeline_outlined,
              title: 'No activity yet',
              subtitle: 'Your orders and saved designs will show up here.',
            );
          }
          return Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const Divider(height: 22),
                _ActivityRow(entries[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Icon + accent colour per real activity kind.
(IconData, Color) _activityStyle(ActivityKind kind) => switch (kind) {
      ActivityKind.orderPlaced =>
        (Icons.receipt_long_outlined, AppColors.secondaryAccent),
      ActivityKind.orderConfirmed =>
        (Icons.check_circle_outline, AppColors.success),
      ActivityKind.orderShipped =>
        (Icons.local_shipping_outlined, AppColors.secondaryAccent),
      ActivityKind.orderDelivered => (Icons.home_outlined, AppColors.success),
      ActivityKind.orderCancelled => (Icons.cancel_outlined, AppColors.error),
      ActivityKind.designSaved =>
        (Icons.design_services_outlined, AppColors.warning),
    };

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.entry);
  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _activityStyle(entry.kind);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(relativeTimeLabel(entry.timestamp, DateTime.now()),
              style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.textHint)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.gradientColors});
  final IconData icon;
  final String label;
  final String value;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            gradientColors[0].withValues(alpha: 0.08),
            gradientColors[1].withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: gradientColors[0].withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
              color: gradientColors[0].withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 10),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard(
      {required this.icon,
      required this.label,
      required this.gradientColors,
      required this.onTap});
  final IconData icon;
  final String label;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}
