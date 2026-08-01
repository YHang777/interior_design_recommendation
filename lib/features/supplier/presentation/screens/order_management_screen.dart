import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/status_badge.dart';
import '../../../../../shared/widgets/filter_chip_bar.dart';
import '../../../../../models/order.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';

/// Supplier order management — view and manage incoming orders from buyers.
class OrderManagementScreen extends ConsumerStatefulWidget {
  const OrderManagementScreen({super.key});

  @override
  ConsumerState<OrderManagementScreen> createState() =>
      _OrderManagementScreenState();
}

class _OrderManagementScreenState
    extends ConsumerState<OrderManagementScreen> {
  String _statusFilter = 'All';

  static const _statusFilters = [
    'All',
    'Pending',
    'Confirmed',
    'Shipped',
    'Delivered',
    'Cancelled',
  ];

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Orders')),
      body: Column(
        children: [
          // Status filter
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: FilterChipBar<String>(
              options: _statusFilters,
              selected: _statusFilter,
              onSelected: (v) =>
                  setState(() => _statusFilter = v),
            ),
          ),

          // Orders list
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Failed to load orders',
                actionLabel: 'Retry',
                onAction: () =>
                    ref.invalidate(ordersProvider),
              ),
              data: (orders) {
                final filtered = _statusFilter == 'All'
                    ? orders
                    : orders
                        .where((o) =>
                            o.status.label == _statusFilter)
                        .toList();

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt_long,
                    title:
                        _statusFilter == 'All'
                            ? 'No orders yet'
                            : 'No $_statusFilter orders',
                    subtitle:
                        _statusFilter == 'All'
                            ? 'Orders placed by buyers will appear here'
                            : null,
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(ordersProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final order = filtered[index];
                      return _OrderCard(order: order);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          context.push('/supplier/orders/${order.id}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order #${order.orderNumber}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
                StatusBadge.order(order.status),
              ],
            ),
            const SizedBox(height: 6),

            // Customer
            Row(
              children: [
                const Icon(Icons.person,
                    size: 14,
                    color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(order.customerName,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 6),

            // Items preview
            Text(
              order.items
                  .map((i) => i.name)
                  .join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textHint),
            ),
            const SizedBox(height: 8),

            // Total + date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${order.items.length} item${order.items.length == 1 ? '' : 's'} • ${_fmt(order.createdAt)}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary),
                ),
                Text(
                  Formatters.myr(order.total),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accent),
                ),
              ],
            ),

            // Refund badge
            if (order.refundStatus != null) ...[
              const SizedBox(height: 6),
              StatusBadge.refund(order.refundStatus!),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';
}
