import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/order.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/product_image.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../providers/supplier_providers.dart';

/// Sales analytics — hand-rolled 6-month revenue bars (no chart dependency),
/// top products by units sold and summary figures. All money figures only
/// include THIS supplier's line items; cancelled orders never count.
class SalesAnalyticsScreen extends ConsumerStatefulWidget {
  const SalesAnalyticsScreen({super.key});

  @override
  ConsumerState<SalesAnalyticsScreen> createState() =>
      _SalesAnalyticsScreenState();
}

/// Mutable tally used while aggregating top products.
class _Tally {
  _Tally({required this.name, required this.image});
  String name;
  String image;
  int qty = 0;
  int revenue = 0;
}

class _SalesAnalyticsScreenState extends ConsumerState<SalesAnalyticsScreen> {
  Future<void> _refresh() async {
    final uid = ref.read(currentUserProvider)?.uid ?? '';
    try {
      final _ = await ref.refresh(supplierOrdersProvider(uid).future);
    } catch (_) {
      // Best effort pull-to-refresh.
    }
  }

  static String _compact(int amount) {
    if (amount >= 1000000) {
      final k = (amount / 1000000).toStringAsFixed(1);
      return '${k.endsWith('.0') ? k.substring(0, k.length - 2) : k}M';
    }
    if (amount >= 1000) {
      final k = (amount / 1000).toStringAsFixed(1);
      return '${k.endsWith('.0') ? k.substring(0, k.length - 2) : k}k';
    }
    return '$amount';
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.read(currentUserProvider)?.uid ?? '';
    final ordersAsync = ref.watch(supplierOrdersProvider(uid));
    final orders = ordersAsync.valueOrNull ?? const <Order>[];

    final sold = revenueOrders(orders, uid).toList();
    final totalOrders = sold.length;
    final totalRevenue = totalRevenueOf(sold, uid);
    final avgOrderValue =
        totalOrders == 0 ? 0 : totalRevenue ~/ totalOrders;

    // Months oldest → newest (includes the current partial month).
    final now = DateTime.now();
    final months = List.generate(
        6, (i) => DateTime(now.year, now.month - (5 - i), 1));
    final monthly = months.map((m) => revenueInMonth(orders, uid, m)).toList();
    final maxMonthly =
        monthly.fold<int>(0, (acc, v) => v > acc ? v : acc);

    final tally = _topProducts(sold, uid);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Analytics')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.accent,
        child: ordersAsync.isLoading && ordersAsync.valueOrNull == null
            ? const _AnalyticsSkeleton()
            : ordersAsync.hasError && orders.isEmpty
                ? LayoutBuilder(
                    builder: (context, constraints) =>
                        SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: EmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not load analytics',
                          subtitle: 'Check your connection and try again.',
                          actionLabel: 'Retry',
                          onAction: _refresh,
                        ),
                      ),
                    ),
                  )
                : orders.isEmpty
                    ? LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minHeight: constraints.maxHeight),
                            child: EmptyState(
                              icon: Icons.insights_outlined,
                              title: 'No sales yet',
                              subtitle: 'Charts and insights appear here '
                                  'once buyers order from your store.',
                            ),
                          ),
                        ),
                      )
                    : _content(months, monthly, maxMonthly, totalOrders,
                        totalRevenue, avgOrderValue, tally),
      ),
    );
  }

  int totalRevenueOf(List<Order> sold, String uid) =>
      sold.fold(0, (sum, o) => sum + mySubtotal(o, uid));

  List<_Tally> _topProducts(List<Order> sold, String uid) {
    final byProduct = <String, _Tally>{};
    for (final order in sold) {
      for (final item in orderItemsForSupplier(order, uid)) {
        final entry = byProduct.putIfAbsent(
            item.productId, () => _Tally(name: item.name, image: item.image));
        entry.qty += item.quantity;
        entry.revenue += item.lineTotal;
      }
    }
    final list = byProduct.values.toList()
      ..sort((a, b) => b.qty.compareTo(a.qty));
    return list.take(3).toList();
  }

  Widget _content(List<DateTime> months, List<int> monthly, int maxMonthly,
      int totalOrders, int totalRevenue, int avgOrderValue,
      List<_Tally> top) {
    final now = DateTime.now();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // ── Summary figures ──
        Row(
          children: [
            StatCard(
              icon: Icons.receipt_long_outlined,
              label: 'Total orders',
              value: '$totalOrders',
              gradient: const [AppColors.secondaryAccent, AppColors.gradientBlue],
            ),
            const SizedBox(width: 10),
            StatCard(
              icon: Icons.receipt_outlined,
              label: 'Avg order value',
              value: Formatters.myr(avgOrderValue),
              gradient: const [AppColors.warning, AppColors.gradientOrange],
            ),
            const SizedBox(width: 10),
            StatCard(
              icon: Icons.payments_outlined,
              label: 'Total revenue',
              value: Formatters.myr(totalRevenue),
              gradient: const [AppColors.accent, AppColors.gradientGreen],
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Revenue bar chart (hand-rolled) ──
        _card(
          title: 'Revenue — last 6 months',
          subtitle: 'Your items only; cancelled orders excluded',
          child: monthly.every((v) => v == 0)
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 26),
                  child: Column(
                    children: [
                      Icon(Icons.bar_chart_outlined,
                          size: 34, color: AppColors.textHint),
                      const SizedBox(height: 10),
                      Text(
                        'No sales recorded in this period',
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : SizedBox(
                  height: 190,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < months.length; i++)
                        Expanded(
                          child: _MonthBar(
                            month: months[i],
                            value: monthly[i],
                            barHeight:
                                monthly[i] / maxMonthly * 120, // 120 max px
                            showYear: months[i].year != now.year,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 14),

        // ── Top products ──
        _card(
          title: 'Top products',
          subtitle: 'By units sold across non-cancelled orders',
          child: top.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No products sold yet — share your store to get '
                    'your first order.',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < top.length; i++)
                      _TopProductRow(index: i, tally: top[i]),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _card({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
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
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// ── One monthly bar ─────────────────────────────────────────────────────

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.value,
    required this.barHeight,
    required this.showYear,
  });

  final DateTime month;
  final int value;
  final double barHeight;
  final bool showYear;

  @override
  Widget build(BuildContext context) {
    final amount = value == 0
        ? ''
        : 'RM ${_SalesAnalyticsScreenState._compact(value)}';
    final label =
        '${Formatters.monthShort(month.month)}${showYear ? " '${(month.year % 100).toString().padLeft(2, '0')}" : ''}';
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          amount,
          style: GoogleFonts.poppins(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: value == 0 ? AppColors.textHint : AppColors.accent,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 120,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              width: 22,
              height: barHeight,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.gradientGreen, AppColors.accent],
                ),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }
}

/// ── Top product row ─────────────────────────────────────────────────────

class _TopProductRow extends StatelessWidget {
  const _TopProductRow({required this.index, required this.tally});

  final int index;
  final _Tally tally;

  @override
  Widget build(BuildContext context) {
    final rankColor = switch (index) {
      0 => AppColors.accent,
      1 => AppColors.secondaryAccent,
      _ => AppColors.warning,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: rankColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${index + 1}',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 40,
              height: 40,
              child: ProductImage(
                imageUrl: tally.image,
                fit: BoxFit.cover,
                errorIconSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tally.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${tally.qty} ${tally.qty == 1 ? 'unit' : 'units'} sold',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formatters.myr(tally.revenue),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'revenue',
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ── Loading skeleton ────────────────────────────────────────────────────

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, [double? w, double r = 8]) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(r),
          ),
        );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: box(92, null, 16)),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Container(
          height: 240,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              box(15, 180),
              const SizedBox(height: 6),
              box(10, 240),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 6; i++) ...[
                    if (i > 0) const Spacer(),
                    box(40 + (i * 13) % 70, 22, 5),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          height: 130,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
        ),
      ],
    );
  }
}
