import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/router/route_names.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/pricing.dart';
import '../../../../../models/order.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/price_summary.dart';
import '../providers/marketplace_providers.dart';

/// Order confirmation shown right after a successful checkout.
///
/// Receives the created ORDER ID as the GoRouter extra (a `String`) and
/// re-reads the order so the confirmation reflects what was actually
/// stored.
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
    // The tax label stays consistent with the checkout summary by deriving
    // the percentage from the same store config.
    final config = ref.watch(configProvider).valueOrNull;
    final taxLabel =
        config == null ? 'Tax' : 'Tax (${taxPercentLabel(config.taxRate)})';

    final breakdown = PriceBreakdown.fromStored(
      subtotal: order.subtotal,
      discount: order.discount,
      shippingFee: order.shippingFee,
      tax: order.tax,
      total: order.total,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      children: [
        // Animated success check.
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle,
                      size: 52, color: AppColors.success),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Order placed!',
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
        // No "we emailed you" claim — the demo does not send email.
        const Text(
          'Your order is confirmed. You can track it anytime in your '
          'orders.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),

        // Delivery ETA card.
        _InfoCard(
          child: Row(
            children: [
              const Icon(Icons.local_shipping_outlined,
                  size: 20, color: AppColors.accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Estimated delivery: 3–5 business days',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('DELIVER TO',
                  style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                      color: AppColors.textHint)),
              const SizedBox(height: 6),
              Text(order.customerName,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(order.shippingAddress,
                  style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Text(
                '${order.paymentMethodLabel}'
                '${order.customerPhone.trim().isEmpty ? '' : ' · ${order.customerPhone.trim()}'}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
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

        // Actions.
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => context.pushNamed(
              RouteNames.homeownerOrderDetail,
              pathParameters: {'id': order.id},
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Track order',
                style: TextStyle(fontSize: 16)),
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

/// Grey placeholder blocks shown while the fresh order is fetched.
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
