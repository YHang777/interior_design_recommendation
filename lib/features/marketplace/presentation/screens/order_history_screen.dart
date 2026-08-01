import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/status_badge.dart';
import '../../../../../models/order.dart';
import '../../../../../features/auth/presentation/providers/auth_providers.dart';
import '../providers/marketplace_providers.dart';

/// Buyer's order history — lists past orders with status badges.
class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Orders')),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Failed to load orders',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(ordersProvider),
        ),
        data: (orders) {
          // Filter to current user's orders (fall back to all if user null)
          final myOrders = user != null
              ? orders
                  .where((o) => o.customerId == user.uid)
                  .toList()
              : orders;

          if (myOrders.isEmpty) {
            return EmptyState(
              icon: Icons.receipt_long,
              title: 'No orders yet',
              subtitle:
                  'Your purchases will appear here',
              actionLabel: 'Start Shopping',
              onAction: () => context.go('/marketplace'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(ordersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: myOrders.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final order = myOrders[index];
                return _OrderCard(order: order);
              },
            ),
          );
        },
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
            const SizedBox(height: 8),

            // Item thumbnails
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  ...order.items.take(4).map((item) =>
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(6),
                          child: Image.asset(
                            item.image,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(
                              width: 44,
                              height: 44,
                              color: AppColors.divider,
                              child: const Icon(Icons.image,
                                  size: 18,
                                  color:
                                      AppColors.textHint),
                            ),
                          ),
                        ),
                      )),
                  if (order.items.length > 4)
                    Text('+${order.items.length - 4} more',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${order.items.length} item${order.items.length == 1 ? '' : 's'} • ${_formatDate(order.createdAt)}',
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

            // Refund status
            if (order.refundStatus != null) ...[
              const SizedBox(height: 8),
              StatusBadge.refund(order.refundStatus!),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
