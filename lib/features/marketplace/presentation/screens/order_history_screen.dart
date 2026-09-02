import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/router/route_names.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../models/order.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/product_image.dart';
import '../../../../../shared/widgets/status_badge.dart';
import '../providers/marketplace_providers.dart';

/// Buyer's order history — live list grouped into status tabs:
/// All / Processing / Delivered / Cancelled. Cards open the buyer order
/// detail screen (`/marketplace/orders/:id`).
class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(customerOrdersProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('My Orders'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.accent,
            indicatorWeight: 3,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(text: 'All'),
              Tab(text: 'Processing'),
              Tab(text: 'Delivered'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: ordersAsync.when(
          skipLoadingOnRefresh: true,
          loading: () => const _OrdersSkeleton(),
          error: (_, __) => EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load your orders',
            subtitle: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(customerOrdersProvider),
          ),
          data: (orders) {
            // Newest first; live status changes move cards across tabs.
            final sorted = [...orders]
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return TabBarView(
              children: [
                _OrdersTab(
                  orders: sorted,
                  emptyIcon: Icons.receipt_long_outlined,
                  emptyTitle: 'No orders yet',
                  emptySubtitle:
                      'Your purchases will appear here with live tracking.',
                  emptyAction: 'Browse the store',
                ),
                _OrdersTab(
                  orders: sorted
                      .where((o) => !o.status.isTerminal)
                      .toList(),
                  emptyIcon: Icons.inventory_2_outlined,
                  emptyTitle: 'Nothing being processed',
                  emptySubtitle:
                      'Orders awaiting confirmation, being prepared or on '
                      'their way will appear here.',
                  emptyAction: 'Browse the store',
                ),
                _OrdersTab(
                  orders: sorted
                      .where((o) => o.status == OrderStatus.delivered)
                      .toList(),
                  emptyIcon: Icons.local_shipping_outlined,
                  emptyTitle: 'No delivered orders yet',
                  emptySubtitle:
                      'Completed orders land here, ready to be reviewed.',
                  emptyAction: 'Browse the store',
                ),
                _OrdersTab(
                  orders: sorted
                      .where((o) => o.status == OrderStatus.cancelled)
                      .toList(),
                  emptyIcon: Icons.cancel_outlined,
                  emptyTitle: 'No cancelled orders',
                  emptySubtitle: 'Cancelled orders will appear here.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One status tab: pull-to-refresh list of order cards, or the tab's own
/// empty state (empty tabs offer a "Browse" shortcut where useful).
class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({
    required this.orders,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptySubtitle,
    this.emptyAction,
  });

  final List<Order> orders;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptySubtitle;
  final String? emptyAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (orders.isEmpty) {
      return EmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        subtitle: emptySubtitle,
        actionLabel: emptyAction,
        onAction: emptyAction == null
            ? null
            : () => context.goNamed(RouteNames.homeownerMarketplace),
      );
    }

    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(customerOrdersProvider),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _OrderCard(order: orders[index]);
        },
      ),
    );
  }
}

/// One order: order number + status, date, thumbnail strip, total and any
/// refund badge. Tap opens the buyer order detail screen.
class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    const thumbCount = 3;
    final itemCount = order.items.length;
    final thumbs = order.items.take(thumbCount).toList();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.pushNamed(
          RouteNames.homeownerOrderDetail,
          pathParameters: {'id': order.id},
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Order ${order.orderNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge.order(order.status, compact: true),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${Formatters.shortDate(order.createdAt)} · '
                      '$itemCount item${itemCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    Formatters.myr(order.total),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 46,
                child: Row(
                  children: [
                    for (var t = 0; t < thumbs.length; t++) ...[
                      if (t > 0) const SizedBox(width: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ProductImage(
                          imageUrl: thumbs[t].image,
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                          errorIconSize: 18,
                        ),
                      ),
                    ],
                    if (itemCount > thumbCount) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '+${itemCount - thumbCount} more',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (order.refundStatus != null) ...[
                const SizedBox(height: 10),
                StatusBadge.refund(order.refundStatus!, compact: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder cards while the Firestore order stream hydrates.
class _OrdersSkeleton extends StatelessWidget {
  const _OrdersSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Container(
            height: 130,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 140,
                      height: 13,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 64,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: 110,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    for (var j = 0; j < 3; j++) ...[
                      if (j > 0) const SizedBox(width: 6),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
