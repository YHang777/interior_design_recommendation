import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/status_badge.dart';
import '../../../../../models/order.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';

/// Supplier order detail — full order info with status advancement actions.
class SupplierOrderDetailScreen extends ConsumerWidget {
  const SupplierOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);

    return ordersAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Order Details')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Error')),
        body: EmptyState(
          icon: Icons.error_outline,
          title: 'Failed to load order',
          actionLabel: 'Go Back',
          onAction: () => context.pop(),
        ),
      ),
      data: (orders) {
        final order =
            orders.where((o) => o.id == orderId).firstOrNull;
        if (order == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(title: const Text('Not Found')),
            body: EmptyState(
              icon: Icons.help_outline,
              title: 'Order not found',
              actionLabel: 'Go Back',
              onAction: () => context.pop(),
            ),
          );
        }

        final color = StatusBadge.colorForOrderStatus(order.status);

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: Text('Order #${order.orderNumber}')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Status banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    StatusBadge.order(order.status),
                    const SizedBox(height: 8),
                    Text(
                      'Placed on ${_fmt(order.createdAt)}',
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Items
              const Text('Items',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              ...order.items.map((item) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(8),
                          child: Image.asset(
                            item.image,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(
                              width: 48,
                              height: 48,
                              color: AppColors.divider,
                              child: const Icon(Icons.image,
                                  size: 20,
                                  color:
                                      AppColors.textHint),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(item.name,
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.w600,
                                      fontSize: 14)),
                              Text(
                                  '${Formatters.myr(item.unitPrice)} × ${item.quantity}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors
                                          .textSecondary)),
                            ],
                          ),
                        ),
                        Text(
                            Formatters.myr(item.lineTotal),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppColors.accent)),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),

              // Customer info
              const Text('Customer',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _Row(Icons.person, order.customerName),
                    _Row(Icons.phone, order.customerPhone),
                    _Row(Icons.email, order.customerEmail),
                    _Row(Icons.location_on,
                        order.shippingAddress),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Payment & totals
              const Text('Payment',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _SummaryRow(
                        'Method',
                        order.paymentMethodLabel),
                    const Divider(),
                    _SummaryRow('Subtotal',
                        Formatters.myr(order.subtotal)),
                    _SummaryRow('Shipping',
                        Formatters.myr(order.shippingFee)),
                    const Divider(),
                    _SummaryRow('Total',
                        Formatters.myr(order.total),
                        bold: true),
                  ],
                ),
              ),

              // Refund
              if (order.refundStatus != null) ...[
                const SizedBox(height: 16),
                const Text('Refund',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                StatusBadge.refund(order.refundStatus!),
              ],

              const SizedBox(height: 24),

              // Status actions (supplier only)
              if (!order.status.isTerminal) ...[
                if (order.status.next != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final service = ref.read(
                              marketplaceServiceProvider);
                          await service.updateOrderStatus(
                            order.id,
                            order.status.next!.name,
                          );
                          ref.invalidate(ordersProvider);
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Order marked as ${order.status.next!.label}'),
                              backgroundColor:
                                  AppColors.success,
                              behavior:
                                  SnackBarBehavior.floating,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Failed: $e'),
                              backgroundColor:
                                  AppColors.error,
                              behavior:
                                  SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(
                          'Mark as ${order.status.next!.label}'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final confirm =
                          await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text(
                              'Cancel Order?'),
                          content: const Text(
                              'This action cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(
                                      ctx, false),
                              child: const Text('No'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  Navigator.pop(
                                      ctx, true),
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor:
                                    AppColors.error,
                              ),
                              child: const Text(
                                  'Yes, Cancel'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      try {
                        final service = ref.read(
                            marketplaceServiceProvider);
                        await service.updateOrderStatus(
                            order.id, 'cancelled');
                        ref.invalidate(ordersProvider);
                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Order cancelled'),
                            backgroundColor:
                                AppColors.error,
                            behavior:
                                SnackBarBehavior.floating,
                          ),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          SnackBar(
                            content: Text('Failed: $e'),
                            backgroundColor:
                                AppColors.error,
                            behavior:
                                SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.cancel,
                        color: AppColors.error),
                    label: const Text('Cancel Order',
                        style:
                            TextStyle(color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: AppColors.error),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, {this.bold = false});
  final String label, value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: bold ? 16 : 14,
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.w400)),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 18 : 14,
                  fontWeight: FontWeight.w700,
                  color: bold
                      ? AppColors.accent
                      : AppColors.textPrimary)),
        ],
      ),
    );
  }
}
