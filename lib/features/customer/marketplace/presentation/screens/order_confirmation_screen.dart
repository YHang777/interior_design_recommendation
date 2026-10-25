import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/router/route_names.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/pricing.dart';
import '../../../../../models/order.dart';
import '../../../../../models/product.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/price_summary.dart';
import '../providers/marketplace_providers.dart';

class OrderConfirmationScreen extends ConsumerWidget {
  const OrderConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extra = GoRouterState.of(context).extra;
    final orderId = extra is String && extra.isNotEmpty ? extra : null;

    final orderAsync = orderId == null
        ? null
        : ref.watch(orderFetchProvider(orderId));
    final loading = orderAsync != null &&
        orderAsync.isLoading &&
        orderAsync.valueOrNull == null;
    final fetchFailed = orderAsync?.hasError ?? false;
    final order = orderAsync?.valueOrNull;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: loading
              ? const _ConfirmationSkeleton()
              : order == null
                  ? EmptyState(
                      icon: fetchFailed
                          ? Icons.cloud_off_outlined
                          : Icons.receipt_long_outlined,
                      title: fetchFailed
                          ? 'Could not load your order'
                          : 'Order not found',
                      subtitle: fetchFailed
                          ? 'Check your connection and try again.'
                          : 'We could not find the order you just placed.',
                      actionLabel: fetchFailed ? 'Try again' : 'Back to home',
                      onAction: () {
                        if (fetchFailed) {
                          ref.invalidate(orderFetchProvider(orderId!));
                        } else {
                          context.goNamed(RouteNames.homeownerMarketplace);
                        }
                      },
                    )
                  : _SuccessView(order: order),
        ),
      ),
    );
  }
}

class _SuccessView extends ConsumerWidget {
  const _SuccessView({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider).valueOrNull;
    final taxLabel =
        config == null ? 'Tax' : 'Tax (${taxPercentLabel(config.taxRate)})';

    final breakdown = PriceBreakdown.fromStored(
      subtotal: order.subtotal,
      discount: order.discount,
      tax: order.tax,
      total: order.total,
    );

    final liveProducts = {
      for (final p
          in ref.watch(marketplaceProductsProvider).valueOrNull ??
              const <Product>[])
        p.id: p,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      children: [
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.accent, AppColors.gradientGreen],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_circle,
                      size: 56, color: Colors.white),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Payment successful!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Order #${Formatters.formatOrderNumber(order.orderNumber)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your payment is confirmed and your items are reserved. '
          'You can track the order anytime in your orders.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),

        _InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 20, color: AppColors.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Paid ${Formatters.myr(order.total)}'
                      '${order.paymentMethodLabel.isEmpty ? '' : ' · ${order.paymentMethodLabel}'}',
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              if (order.paymentIntentId.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Ref ${order.paymentIntentId}',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textHint),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        _InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PICKUP FROM',
                  style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                      color: AppColors.textHint)),
              const SizedBox(height: 8),
              for (final supplierId in order.supplierIdsInItemOrder) ...[
                if (supplierId != order.supplierIdsInItemOrder.first)
                  const SizedBox(height: 8),
                _pickupRow(order, supplierId, liveProducts),
              ],
              const SizedBox(height: 8),
              Text(
                '${order.customerName}'
                '${order.customerPhone.trim().isEmpty ? '' : ' · ${order.customerPhone.trim()}'}'
                ' — the supplier will contact you to arrange collection.',
                style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        if (order.paymentStatus == PaymentStatus.paid &&
            order.paymentIntentId.isNotEmpty) ...[
          const SizedBox(height: 10),
          _InfoCard(
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.pushNamed(
                  RouteNames.orderReceipt,
                  pathParameters: {'orderId': order.id},
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: BorderSide(
                      color: AppColors.accent.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.receipt_outlined, size: 18),
                label: const Text('View payment receipt',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _InfoCard(
          child: PriceSummaryCard(
            breakdown: breakdown,
            discountLabel:
                'Membership discount${order.membershipTier.isEmpty ? '' : ' (${order.membershipTier})'}',
            taxLabel: taxLabel,
          ),
        ),
        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.gradientGreen],
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: ElevatedButton(
              onPressed: () => context.pushNamed(
                RouteNames.homeownerOrderDetail,
                pathParameters: {'id': order.id},
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: const Text('Track order',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.goNamed(RouteNames.homeownerMarketplace),
          child: const Text('Continue shopping'),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

Widget _pickupRow(
  Order order,
  String supplierId,
  Map<String, Product> liveProducts,
) {
  final firstItem = order.items.firstWhere(
    (it) => it.supplierId == supplierId,
    orElse: () => order.items.first,
  );
  final supplier = liveProducts[firstItem.productId]?.supplier;
  final name = supplier?.name.trim().isNotEmpty == true
      ? supplier!.name.trim()
      : 'Supplier store';
  final address = supplier?.address.trim() ?? '';
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.storefront_outlined,
          size: 16, color: AppColors.accent),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            if (address.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(address,
                  style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.textSecondary)),
            ],
          ],
        ),
      ),
    ],
  );
}

class _ConfirmationSkeleton extends StatelessWidget {
  const _ConfirmationSkeleton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: AppColors.divider,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 180,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: 140,
              height: 13,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 28),
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Container(
                width: double.infinity,
                height: 74,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
