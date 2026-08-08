import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../models/cart_item.dart';
import '../providers/marketplace_providers.dart';

/// Shopping cart with quantity controls, order summary, and checkout button.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);
    final configAsync = ref.watch(configProvider);
    final itemCount = ref.watch(cartCountProvider);

    final shippingFee = configAsync.whenOrNull(data: (c) => c.shippingFee) ?? 25;
    final freeThreshold =
        configAsync.whenOrNull(data: (c) => c.freeShippingThreshold) ?? 500;
    final actualShipping = total >= freeThreshold ? 0 : shippingFee;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Shopping Cart ($itemCount)'),
        actions: cart.isNotEmpty
            ? [
                TextButton(
                  onPressed: () {
                    ref.read(cartProvider.notifier).clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cart cleared'),
                        backgroundColor: AppColors.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: const Text('Clear All',
                      style: TextStyle(
                          color: AppColors.textOnDark,
                          fontWeight: FontWeight.w500)),
                ),
              ]
            : null,
      ),
      body: cart.isEmpty
          ? EmptyState(
              icon: Icons.shopping_cart_outlined,
              title: 'Your cart is empty',
              subtitle: 'Browse the marketplace to find items you love',
              actionLabel: 'Start Shopping',
              onAction: () => context.pop(),
            )
          : Column(
              children: [
                // Cart items
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: cart.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final ci = cart[index];
                      return _CartItemTile(item: ci, ref: ref);
                    },
                  ),
                ),

                // Order summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border:
                        Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(
                          'Subtotal', Formatters.myr(total)),
                      const SizedBox(height: 4),
                      _SummaryRow(
                        'Shipping',
                        actualShipping == 0
                            ? 'FREE'
                            : Formatters.myr(actualShipping),
                        valueColor: actualShipping == 0
                            ? AppColors.success
                            : null,
                      ),
                      if (total < freeThreshold) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Free shipping on orders over ${Formatters.myr(freeThreshold)}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      _SummaryRow(
                        'Total',
                        Formatters.myr(total + actualShipping),
                        bold: true,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () =>
                              context.push('/marketplace/checkout'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 16),
                          ),
                          child: Text(
                            'Proceed to Checkout — ${Formatters.myr(total + actualShipping)}',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            context.push('/marketplace/orders'),
                        child: const Text('View Order History'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({required this.item, required this.ref});
  final CartItem item;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              item.product.image,
              width: 72,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 72,
                height: 56,
                color: AppColors.divider,
                child: const Icon(Icons.image,
                    color: AppColors.textHint),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.product.name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(Formatters.myr(item.product.price),
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(Formatters.myr(item.lineTotal),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent)),
              ],
            ),
          ),

          // Quantity controls
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiniButton(
                  icon: Icons.remove,
                  onTap: () => ref
                      .read(cartProvider.notifier)
                      .decrement(item.product.id),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('${item.quantity}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
                _MiniButton(
                  icon: Icons.add,
                  onTap: () => ref
                      .read(cartProvider.notifier)
                      .increment(item.product.id),
                ),
              ],
            ),
          ),

          // Remove
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 20, color: AppColors.error),
            onPressed: () {
              ref
                  .read(cartProvider.notifier)
                  .removeItem(item.product.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '${item.product.name} removed from cart'),
                  backgroundColor: AppColors.error,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 16, color: AppColors.textPrimary),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value,
      {this.bold = false, this.valueColor});
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: bold ? 16 : 14,
                fontWeight:
                    bold ? FontWeight.w700 : FontWeight.w400,
                color: AppColors.textPrimary)),
        Text(value,
            style: TextStyle(
                fontSize: bold ? 18 : 14,
                fontWeight:
                    bold ? FontWeight.w700 : FontWeight.w600,
                color: valueColor ??
                    (bold
                        ? AppColors.accent
                        : AppColors.textPrimary))),
      ],
    );
  }
}
