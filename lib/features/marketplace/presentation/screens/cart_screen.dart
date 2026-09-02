import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/router/route_names.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/pricing.dart';
import '../../../../../features/auth/presentation/providers/auth_providers.dart';
import '../../../../../models/app_config_data.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/product_image.dart';
import '../../../../../shared/widgets/quantity_stepper.dart';
import '../providers/marketplace_providers.dart';

/// Shopping cart with quantity controls, swipe-to-delete (with UNDO),
/// free-shipping progress and a sticky checkout bar. Every row is
/// reconciliated against the live catalogue ([cartRowsProvider]) so
/// price/stock changes surface immediately instead of on the checkout
/// transaction.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(cartRowsProvider);
    final cart = ref.watch(cartProvider);
    final itemCount = ref.watch(cartCountProvider);
    final hydrated = ref.watch(cartHydratedProvider);
    final uid = ref.watch(currentUserProvider)?.uid;
    final configAsync = ref.watch(configProvider);
    final tier = ref.watch(customerMembershipTierProvider);

    final config = configAsync.valueOrNull;
    final isHydrating = uid != null && !hydrated && cart.isEmpty;

    // Money shown in the checkout bar follows the LIVE product prices the
    // rows are displayed against, billed at the effective (stock-capped)
    // quantity so it always matches what the order transaction accepts.
    final subtotal = rows.fold<int>(
        0, (sum, row) => sum + row.live.price * row.effectiveQty);
    final hasInvalidRows = rows.any((row) => row.unavailable);

    void removeItem(CartRow row) {
      ref.read(cartProvider.notifier).removeItem(row.item.product.id);
      showAppSnackbar(
        context,
        '${row.live.name} removed',
        color: AppColors.error,
        duration: const Duration(seconds: 5),
        actionLabel: 'UNDO',
        onAction: () {
          final restored =
              ref.read(cartProvider.notifier).restoreItem(row.item);
          if (!restored && context.mounted) {
            showAppSnackbar(context, 'Out of stock now — could not restore',
                color: AppColors.warning);
          }
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Shopping Cart'),
        actions: [
          if (cart.isNotEmpty)
            TextButton(
              onPressed: () async {
                final confirmed = await showConfirmDialog(
                  context,
                  title: 'Clear your cart?',
                  message:
                      'All $itemCount item${itemCount == 1 ? '' : 's'} will '
                      'be removed from your cart.',
                  confirmLabel: 'Clear all',
                  destructive: true,
                );
                if (!confirmed || !context.mounted) return;
                ref.read(cartProvider.notifier).clear();
                showAppSnackbar(context, 'Cart cleared',
                    color: AppColors.error);
              },
              child: const Text('Clear all',
                  style: TextStyle(
                      color: AppColors.textOnDark,
                      fontWeight: FontWeight.w500)),
            ),
        ],
      ),
      body: isHydrating
          ? const _CartSkeleton()
          : cart.isEmpty
              ? EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  title: 'Your cart is empty',
                  subtitle: 'Browse the marketplace to find items you love',
                  actionLabel: 'Browse the store',
                  onAction: () =>
                      context.goNamed(RouteNames.homeownerMarketplace),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // The free-shipping banner and the checkout summary
                          // must agree: both go through the shared calculator
                          // (free once the POST-discount chargeable amount
                          // reaches the threshold). Until store config has
                          // loaded, a neutral skeleton is shown instead of
                          // invented defaults.
                          if (config == null)
                            const _FreeShippingSkeleton()
                          else
                            _FreeShippingCard(
                              shippingFee: config.shippingFee,
                              freeShippingThreshold:
                                  config.freeShippingThreshold,
                              taxRate: config.taxRate,
                              discountPercent: tier?.discountPercent ?? 0,
                              chargeableBase: subtotal,
                            ),
                          const SizedBox(height: 12),
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            Dismissible(
                              key: ValueKey(
                                  'cart-${rows[i].item.product.id}'),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) => removeItem(rows[i]),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: AppColors.error,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.delete_outline,
                                    color: AppColors.textOnDark, size: 26),
                              ),
                              child: _CartItemCard(
                                row: rows[i],
                                onRemove: () => removeItem(rows[i]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _CheckoutBar(
                      itemCount: itemCount,
                      subtotal: subtotal,
                      hasInvalidRows: hasInvalidRows,
                      tier: tier,
                      onCheckout: () =>
                          context.pushNamed(RouteNames.homeownerCheckout),
                    ),
                  ],
                ),
    );
  }
}

/// Free-shipping progress — bar + remaining amount below the threshold,
/// celebration once unlocked. Computed with the shared [PriceBreakdown]
/// rules so it can never contradict the checkout summary.
class _FreeShippingCard extends StatelessWidget {
  const _FreeShippingCard({
    required this.chargeableBase,
    required this.discountPercent,
    required this.shippingFee,
    required this.freeShippingThreshold,
    required this.taxRate,
  });

  /// Pre-discount subtotal of the cart rows.
  final int chargeableBase;
  final int discountPercent;
  final int shippingFee;
  final int freeShippingThreshold;
  final double taxRate;

  @override
  Widget build(BuildContext context) {
    final bd = computePriceBreakdown(
      subtotal: chargeableBase,
      discountPercent: discountPercent,
      shippingFee: shippingFee,
      freeShippingThreshold: freeShippingThreshold,
      taxRate: taxRate,
    );
    final threshold = freeShippingThreshold;
    final unlocked = bd.shippingFee == 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                unlocked
                    ? Icons.celebration_outlined
                    : Icons.local_shipping_outlined,
                size: 18,
                color: unlocked ? AppColors.success : AppColors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  unlocked
                      ? "You've unlocked FREE shipping"
                      : 'Free shipping unlocks at '
                          '${Formatters.myr(threshold)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: unlocked
                        ? AppColors.success
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (!unlocked) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (bd.chargeable / threshold).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.divider,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add ${Formatters.myr(threshold - bd.chargeable)} more for '
              'FREE shipping',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Neutral block shown in place of the free-shipping banner while store
/// config is still loading.
class _FreeShippingSkeleton extends StatelessWidget {
  const _FreeShippingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined,
                  size: 18, color: AppColors.textHint),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Free shipping unlocks at …',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single cart line: thumb, name, unit price, stepper, line total, remove.
/// State comes from the reconciliated [CartRow] — the live catalogue product
/// wins for name/price/stock, and rows whose product vanished or went
/// off-sale carry their own banner.
class _CartItemCard extends ConsumerWidget {
  const _CartItemCard({required this.row, required this.onRemove});

  final CartRow row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = row.live;
    final liveStock = row.liveStock;
    final outOfStock = row.unavailable;
    final quantityAdjusted =
        !row.missing && !row.inactive && liveStock > 0 &&
            row.item.quantity > liveStock;
    final shownQty = row.effectiveQty;

    final String? blockMessage;
    final IconData blockIcon;
    if (row.missing) {
      blockMessage = 'No longer available — remove this item to continue';
      blockIcon = Icons.remove_shopping_cart_outlined;
    } else if (row.inactive) {
      blockMessage = 'No longer on sale — remove this item to continue';
      blockIcon = Icons.pause_circle_outline;
    } else if (liveStock <= 0) {
      blockMessage = 'Out of stock — remove this item to continue';
      blockIcon = Icons.remove_shopping_cart_outlined;
    } else {
      blockMessage = null;
      blockIcon = Icons.error_outline;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ProductImage(
                  product: product,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorIconSize: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Remove from cart',
                          icon: const Icon(Icons.close,
                              size: 18, color: AppColors.textHint),
                          onPressed: onRemove,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Formatters.myr(product.price)} each',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (outOfStock)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.border,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Qty',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                          )
                        else
                          QuantityStepper(
                            value: shownQty,
                            min: 1,
                            max: liveStock,
                            compact: true,
                            onChanged: (value) => ref
                                .read(cartProvider.notifier)
                                .setQuantity(product.id, value),
                            onBlockedTap: liveStock > 1
                                ? () => showAppSnackbar(
                                      context,
                                      'Only $liveStock in stock',
                                      color: AppColors.warning,
                                    )
                                : null,
                          ),
                        const Spacer(),
                        Text(
                          Formatters.myr(product.price * row.effectiveQty),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (blockMessage != null)
            _RowNotice(icon: blockIcon, message: blockMessage)
          else if (quantityAdjusted)
            _RowNotice(
              icon: Icons.error_outline,
              message: 'Only $liveStock left — quantity adjusted',
            ),
        ],
      ),
    );
  }
}

class _RowNotice extends StatelessWidget {
  const _RowNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.warning.withValues(alpha: 0.95),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sticky bottom bar: subtotal, membership note, unavailable-item gate and
/// the full-width checkout button.
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.itemCount,
    required this.subtotal,
    required this.hasInvalidRows,
    required this.tier,
    required this.onCheckout,
  });

  final int itemCount;
  final int subtotal;
  final bool hasInvalidRows;
  final MembershipTier? tier;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final canCheckout = itemCount > 0 && !hasInvalidRows;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tier != null && tier!.discountPercent > 0) ...[
                Row(
                  children: [
                    const Icon(Icons.workspace_premium_outlined,
                        size: 16, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${tier!.name} member: ${tier!.discountPercent}% off '
                        'applies at checkout',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Text(
                    'Subtotal ($itemCount item${itemCount == 1 ? '' : 's'})',
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    Formatters.myr(subtotal),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
              if (hasInvalidRows) ...[
                const SizedBox(height: 4),
                const Text(
                  'Some items are no longer available — remove them to '
                  'checkout',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canCheckout ? onCheckout : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: const Text('Checkout',
                      style: TextStyle(fontSize: 15.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder cards shown while the Firestore cart hydrates.
class _CartSkeleton extends StatelessWidget {
  const _CartSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Container(
            height: 104,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 90,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 120,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
