import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/pricing.dart';
import '../../core/utils/user_errors.dart';
import '../../features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import '../../models/order.dart';
import '../../services/invoice/receipt_pdf.dart';
import '../widgets/app_feedback.dart';
import '../widgets/empty_state.dart';
import '../widgets/float_button.dart';
import '../widgets/page_heading.dart';
import '../widgets/price_summary.dart';

class OrderReceiptScreen extends ConsumerStatefulWidget {
  const OrderReceiptScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderReceiptScreen> createState() => _OrderReceiptScreenState();
}

class _OrderReceiptScreenState extends ConsumerState<OrderReceiptScreen> {
  bool _working = false;

  Future<void> _share(Order order) async {
    setState(() => _working = true);
    try {
      await ReceiptPdf.share(order);
      if (mounted) {
        showAppSnackbar(context, 'Receipt PDF ready to share',
            duration: const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
            context,
            userMessage(e,
                fallback:
                    'Could not prepare the receipt PDF. Please try again.'),
            isError: true,
            duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _print(Order order) async {
    setState(() => _working = true);
    try {
      await ReceiptPdf.print(order);
      if (mounted) {
        showAppSnackbar(context, 'Print dialog opened',
            duration: const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
            context,
            userMessage(e,
                fallback:
                    'Could not prepare the receipt PDF. Please try again.'),
            isError: true,
            duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderFetchProvider(widget.orderId));
    final isLoading =
        orderAsync.isLoading && orderAsync.valueOrNull == null;
    final order = orderAsync.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : order == null ||
                        order.paymentStatus != PaymentStatus.paid
                    ? EmptyState(
                        icon: orderAsync.hasError
                            ? Icons.cloud_off_outlined
                            : Icons.receipt_long_outlined,
                        title: orderAsync.hasError
                            ? 'Could not load this receipt'
                            : order == null
                                ? 'Receipt not found'
                                : 'No payment yet',
                        subtitle: orderAsync.hasError
                            ? 'Check your connection and try again.'
                            : order == null
                                ? 'It may have been removed.'
                                : 'A receipt appears once the order is paid.',
                        actionLabel: orderAsync.hasError ? 'Retry' : 'Back',
                        onAction: () {
                          if (orderAsync.hasError) {
                            ref.invalidate(orderFetchProvider(widget.orderId));
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        },
                      )
                    : _body(order),
          ),
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 8,
            left: 8,
            child: const FloatingBackButton(),
          ),
        ],
      ),
      bottomNavigationBar: order == null ||
              order.paymentStatus != PaymentStatus.paid
          ? null
          : _actionBar(order),
    );
  }

  Widget _body(Order order) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 60, 16, MediaQuery.paddingOf(context).bottom + 32),
      children: [
        PageHeading(
          title: 'Payment receipt',
          subtitle: Formatters.formatOrderNumber(order.orderNumber),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 22, color: AppColors.success),
                  const SizedBox(width: 8),
                  Text(
                    'PAID',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppColors.success,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    Formatters.myr(order.total),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _metaLine(
                  'Method',
                  order.paymentMethodLabel.isEmpty
                      ? '—'
                      : order.paymentMethodLabel),
              if (order.paidAt != null)
                _metaLine('Paid', Formatters.shortDateTime(order.paidAt!)),
              if (order.paymentIntentId.isNotEmpty)
                _metaLine('Reference', order.paymentIntentId),
              _metaLine('Billed to',
                  '${order.customerName}'
                  '${order.customerEmail.trim().isEmpty ? '' : ' · ${order.customerEmail.trim()}'}'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Items (${order.items.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < order.items.length; i++) ...[
                if (i > 0) const Divider(height: 14, thickness: 0.6),
                _itemRow(order.items[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          child: PriceSummaryCard(
            breakdown: PriceBreakdown.fromStored(
              subtotal: order.subtotal,
              discount: order.discount,
              tax: order.tax,
              total: order.total,
            ),
            discountLabel: 'Membership discount'
                '${order.membershipTier.isEmpty ? '' : ' (${order.membershipTier})'}',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Collect from each supplier\'s store — suppliers will contact you '
          'to arrange pickup.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            height: 1.4,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _metaLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(OrderItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.quantity} × ${Formatters.myr(item.unitPrice)}',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textHint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            Formatters.myr(item.lineTotal),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBar(Order order) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: _working
                          ? null
                          : const LinearGradient(
                              colors: [
                                AppColors.accent,
                                AppColors.gradientGreen
                              ],
                            ),
                      borderRadius: BorderRadius.circular(14),
                      color: _working ? AppColors.border : null,
                    ),
                    child: ElevatedButton(
                      onPressed: _working ? null : () => _share(order),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.transparent,
                        disabledForegroundColor: AppColors.textHint,
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _working
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Share PDF',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _working ? null : () => _print(order),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _working
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textSecondary),
                          )
                        : const Text('Print',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
