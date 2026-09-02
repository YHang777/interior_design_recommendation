import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/order.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/filter_chip_bar.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../providers/supplier_providers.dart';

/// Supplier's incoming orders. Totals shown per order are for THIS supplier's
/// line items only — shared (multi-seller) orders never leak other sellers'
/// money figures into the summary row.
class OrderManagementScreen extends ConsumerStatefulWidget {
  const OrderManagementScreen({super.key});

  @override
  ConsumerState<OrderManagementScreen> createState() =>
      _OrderManagementScreenState();
}

enum _OrderBucket { all, fresh, processing, completed }

class _OrderManagementScreenState
    extends ConsumerState<OrderManagementScreen> {
  _OrderBucket _bucket = _OrderBucket.all;

  static _OrderBucket _bucketOf(OrderStatus status) => switch (status) {
        OrderStatus.pending => _OrderBucket.fresh,
        OrderStatus.confirmed || OrderStatus.shipped =>
          _OrderBucket.processing,
        OrderStatus.delivered || OrderStatus.cancelled =>
          _OrderBucket.completed,
      };

  void _open(Order o) => context.pushNamed(
        RouteNames.supplierOrderDetail,
        pathParameters: {'id': o.id},
      );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final supplierId = user?.uid ?? '';
    final ordersAsync = ref.watch(supplierOrdersProvider(supplierId));
    final isLoading =
        ordersAsync.isLoading && ordersAsync.valueOrNull == null;
    final all = ordersAsync.valueOrNull ?? const <Order>[];

    final filtered = all
        .where((o) =>
            _bucket == _OrderBucket.all || _bucketOf(o.status) == _bucket)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Orders')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.accent,
        child: isLoading
            ? const _OrdersSkeletonList()
            : ordersAsync.hasError && all.isEmpty
                ? _scrollableState(
                    EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load orders',
                      subtitle: 'Check your connection and try again.',
                      actionLabel: 'Retry',
                      onAction: _refresh,
                    ),
                  )
                : all.isEmpty
                    ? _scrollableState(
                        EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No orders yet',
                          subtitle: 'Orders placed on your products by '
                              'buyers will show up here instantly.',
                        ),
                      )
                    : _content(supplierId, filtered, all.length),
      ),
    );
  }

  Future<void> _refresh() async {
    final uid = ref.read(currentUserProvider)?.uid ?? '';
    try {
      final _ = await ref.refresh(supplierOrdersProvider(uid).future);
    } catch (_) {
      // Best effort — the stream reports errors on its own.
    }
  }

  Widget _content(String supplierId, List<Order> filtered, int total) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        FilterChipBar<_OrderBucket>(
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.filter_alt_outlined,
                size: 16, color: AppColors.textSecondary),
          ),
          options: _OrderBucket.values,
          selected: _bucket,
          labelBuilder: (b) => switch (b) {
            _OrderBucket.all => 'All',
            _OrderBucket.fresh => 'New',
            _OrderBucket.processing => 'Processing',
            _OrderBucket.completed => 'Completed',
          },
          onSelected: (b) => setState(() => _bucket = b),
        ),
        if (filtered.isEmpty) ...[
          const SizedBox(height: 32),
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No ${_bucketLabel().toLowerCase()} orders',
            subtitle: 'Orders that match this filter will appear here.',
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 2),
            child: Text(
              '${filtered.length} of $total orders',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: AppColors.textHint,
              ),
            ),
          ),
          ...filtered.map((o) => _OrderTile(
                order: o,
                supplierId: supplierId,
                myCount: myLineItemCount(o, supplierId),
                myTotal: mySubtotal(o, supplierId),
                onTap: () => _open(o),
              )),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  String _bucketLabel() => switch (_bucket) {
        _OrderBucket.all => 'All',
        _OrderBucket.fresh => 'New',
        _OrderBucket.processing => 'Processing',
        _OrderBucket.completed => 'Completed',
      };

  Widget _scrollableState(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

/// ── Order card ──────────────────────────────────────────────────────────

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.order,
    required this.supplierId,
    required this.myCount,
    required this.myTotal,
    required this.onTap,
  });

  final Order order;
  final String supplierId;
  final int myCount;
  final int myTotal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Formatters.formatOrderNumber(order.orderNumber),
                          style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Placed ${Formatters.shortDateTime(order.createdAt)}',
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: AppColors.textHint,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.person_outline,
                                size: 13, color: AppColors.textHint),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                order.customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge.order(order.status, compact: true),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined,
                      size: 14, color: AppColors.textHint),
                  const SizedBox(width: 6),
                  Text(
                    myCount == 1 ? '1 of your items' : '$myCount of your items',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    Formatters.myr(myTotal),
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ── Loading skeleton rows ───────────────────────────────────────────────

class _OrdersSkeletonList extends StatelessWidget {
  const _OrdersSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 108,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 12,
                  width: 140,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Spacer(),
                Container(
                  height: 18,
                  width: 60,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 10,
              width: 90,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 10,
              width: 120,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
