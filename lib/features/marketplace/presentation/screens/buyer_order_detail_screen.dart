import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/router/route_names.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/pricing.dart';
import '../../../../../features/auth/presentation/providers/auth_providers.dart';
import '../../../../../models/order.dart';
import '../../../../../models/review.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/price_summary.dart';
import '../../../../../shared/widgets/product_image.dart';
import '../../../../../shared/widgets/status_badge.dart';
import '../providers/marketplace_providers.dart';

/// Buyer-facing single-order view: live status timeline (per-step dates),
/// itemised totals, delivery info and contextual actions — cancel while
/// pending, reorder at any time, review each item once the order arrives.
///
/// Live: watches the order document (see [orderDetailProvider]) so supplier
/// status changes and own cancellations appear without a manual refresh.
class BuyerOrderDetailScreen extends ConsumerStatefulWidget {
  const BuyerOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<BuyerOrderDetailScreen> createState() =>
      _BuyerOrderDetailScreenState();
}

class _BuyerOrderDetailScreenState
    extends ConsumerState<BuyerOrderDetailScreen> {
  /// True while a cancel/reorder network call is in flight — disables the
  /// action bar so the same order cannot be cancelled twice.
  bool _working = false;

  Future<void> _cancelOrder(Order order) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel this order?',
      message: 'The order will be cancelled and the stock for every item '
          'will be restored. This cannot be undone.',
      confirmLabel: 'Cancel order',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _working = true);
    try {
      await ref.read(marketplaceRepositoryProvider).cancelOrder(order.id);
      if (mounted) {
        showAppSnackbar(context, 'Order cancelled — stock restored',
            color: AppColors.error);
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Could not cancel the order — $e',
            color: AppColors.error, duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Puts every still-available item of the order back into the cart at the
  /// ordered quantity (clamped to current stock by the cart notifier).
  /// Unavailable listings are skipped and reported once at the end.
  Future<void> _reorder(Order order) async {
    setState(() => _working = true);
    try {
      final products = await ref.read(marketplaceProductsProvider.future);
      final byId = {for (final p in products) p.id: p};

      var added = 0;
      var skipped = 0;
      for (final item in order.items) {
        final product = byId[item.productId];
        if (product == null || !product.isActive || product.isOutOfStock) {
          skipped++;
          continue;
        }
        ref.read(cartProvider.notifier).addItem(product, qty: item.quantity);
        added++;
      }
      if (!mounted) return;

      if (added == 0) {
        showAppSnackbar(context, 'These items are no longer available',
            color: AppColors.warning);
      } else if (skipped > 0) {
        showAddedToCartSnack(
          context,
          'Added $added of ${order.items.length} available items to your '
          'cart',
          onViewCart: () =>
              context.pushNamed(RouteNames.homeownerCart),
        );
      } else {
        showAddedToCartSnack(
          context,
          '$added item${added == 1 ? '' : 's'} added to your cart',
          onViewCart: () =>
              context.pushNamed(RouteNames.homeownerCart),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Could not load products for reorder — $e',
            color: AppColors.error, duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));
    final order = orderAsync.valueOrNull;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: canPop
            ? null
            : IconButton(
                tooltip: 'Back to home',
                icon: const Icon(Icons.home_outlined),
                onPressed: () =>
                    context.goNamed(RouteNames.homeownerDashboard),
              ),
        title: Text(
          order == null ? 'Order detail' : 'Order ${order.orderNumber}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: orderAsync.isLoading && order == null
          ? const _OrderSkeleton()
          : orderAsync.hasError
              ? EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load this order',
                  subtitle: 'Check your connection and try again.',
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(
                      orderDetailProvider(widget.orderId)),
                )
              : order == null
                  ? EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Order not found',
                      subtitle: 'It may have been removed from your account.',
                      actionLabel: 'Back to orders',
                      onAction: () =>
                          context.goNamed(RouteNames.homeownerOrderHistory),
                    )
                  : _OrderBody(order: order),
      bottomNavigationBar: order == null ? null : _actionBar(order),
    );
  }

  Widget _actionBar(Order order) {
    final buttons = <Widget>[
      Expanded(
        child: SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _working ? null : () => _reorder(order),
            child: const Text('Reorder'),
          ),
        ),
      ),
    ];
    if (order.status == OrderStatus.pending) {
      buttons.insert(
        0,
        SizedBox(
          height: 48,
          width: 130,
          child: OutlinedButton(
            onPressed: _working ? null : () => _cancelOrder(order),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
            ),
            child: const Text('Cancel order'),
          ),
        ),
      );
      buttons.insert(1, const SizedBox(width: 10));
    }
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: buttons),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Full scrollable content for a loaded order.
class _OrderBody extends ConsumerWidget {
  const _OrderBody({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tax label stays consistent with the checkout summary by deriving the
    // percentage from the same store config.
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _StatusCard(order: order),
        const SizedBox(height: 14),
        _sectionCard(
          context,
          'Items (${order.items.length})',
          child: Column(
            children: [
              for (var i = 0; i < order.items.length; i++) ...[
                if (i > 0) const Divider(height: 14, thickness: 0.6),
                _ItemRow(item: order.items[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          context,
          'Payment summary',
          child: PriceSummaryCard(
            breakdown: breakdown,
            discountLabel: 'Membership discount'
                '${order.membershipTier.isEmpty ? '' : ' (${order.membershipTier})'}',
            taxLabel: taxLabel,
            dividerVerticalPadding: 6,
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          context,
          'Delivery',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MetaRow(Icons.credit_card, order.paymentMethodLabel),
              const SizedBox(height: 8),
              _MetaRow(Icons.event_outlined,
                  'Placed ${Formatters.shortDateTime(order.createdAt)}'),
              const SizedBox(height: 8),
              _MetaRow(
                Icons.location_on_outlined,
                order.customerName,
                sub: order.shippingAddress,
              ),
              if (order.customerPhone.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                _MetaRow(Icons.phone_outlined,
                    Formatters.phone(order.customerPhone.trim())),
              ],
            ],
          ),
        ),
        // ── Reviews: once delivered, one review per item per order ──────
        if (order.status == OrderStatus.delivered) ...[
          const SizedBox(height: 14),
          _sectionCard(
            context,
            'Rate your items',
            child: Column(
              children: [
                for (final item in order.items) ...[
                  if (item != order.items.first)
                    const Divider(height: 14, thickness: 0.6),
                  _ReviewEntryRow(
                    order: order,
                    item: item,
                    onWrite: () => _submitReview(context, ref, order, item),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Order ${order.id}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textHint),
        ),
      ],
    );
  }

  Widget _sectionCard(BuildContext context, String title,
      {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Opens the write-review bottom sheet for one line item, then refreshes the
/// per-item state when the review was actually submitted.
Future<void> _submitReview(
  BuildContext context,
  WidgetRef ref,
  Order order,
  OrderItem item,
) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return;

  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReviewSheet(
      order: order,
      item: item,
      userId: user.uid,
      userName: user.name.trim().isEmpty ? 'Anonymous' : user.name,
    ),
  );
  if (submitted != true || !context.mounted) return;

  ref.invalidate(orderReviewProvider((
    productId: item.productId,
    orderId: order.id,
  )));
  showAppSnackbar(context, 'Thanks! Your review is live.',
      color: AppColors.success);
}

// ── Status card: header + timeline (or the cancelled banner) ────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
            children: [
              const Expanded(
                child: Text(
                  'Status',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              StatusBadge.order(order.status, compact: true),
            ],
          ),
          const SizedBox(height: 16),
          if (order.status == OrderStatus.cancelled)
            _CancelledBanner(order: order)
          else
            _StatusTimeline(order: order),
        ],
      ),
    );
  }
}

/// Red banner shown for cancelled orders (replaces the timeline).
class _CancelledBanner extends StatelessWidget {
  const _CancelledBanner({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final cancelDate = order.statusHistory[OrderStatus.cancelled.name];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cancel_outlined, color: AppColors.error, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Order cancelled',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Payment & stock restored'
                  '${cancelDate == null ? '' : ' on ${Formatters.shortDateTime(cancelDate)}'}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical progress: Pending → Confirmed → Shipped → Delivered with a
/// checkmark and per-step date for every reached stage. Dates come from
/// [Order.statusHistory]; the first step falls back to the order date.
class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.order});

  final Order order;

  static const _steps = [
    (OrderStatus.pending, 'Pending'),
    (OrderStatus.confirmed, 'Confirmed'),
    (OrderStatus.shipped, 'Shipped'),
    (OrderStatus.delivered, 'Delivered'),
  ];

  String? _captionFor(int index) {
    if (index != order.status.index) return null;
    return switch (order.status) {
      OrderStatus.pending => 'Awaiting seller confirmation',
      OrderStatus.confirmed => 'Fulfilment in progress',
      OrderStatus.shipped => 'On its way to you',
      OrderStatus.delivered => 'Enjoy your new space!',
      OrderStatus.cancelled => null, // replaced by the banner
    };
  }

  @override
  Widget build(BuildContext context) {
    final reached = switch (order.status) {
      OrderStatus.pending => 1,
      OrderStatus.confirmed => 2,
      OrderStatus.shipped => 3,
      OrderStatus.delivered => 4,
      OrderStatus.cancelled => 0, // banner replaces this timeline
    };

    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++)
          _stepRow(
            index: i,
            done: i < reached,
            date: order.statusHistory[_steps[i].$1.name] ??
                (i == 0 ? order.createdAt : null),
            caption: _captionFor(i),
          ),
      ],
    );
  }

  Widget _stepRow({
    required int index,
    required bool done,
    required DateTime? date,
    required String? caption,
  }) {
    final isLast = index == _steps.length - 1;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dot + connector column.
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: done ? AppColors.accent : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: done ? AppColors.accent : AppColors.border,
                      width: 2,
                    ),
                  ),
                  child: done
                      ? const Icon(Icons.check,
                          size: 13, color: AppColors.textOnDark)
                      : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2.4,
                      color: done
                          ? AppColors.accent.withValues(alpha: 0.35)
                          : AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _steps[index].$2,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              done ? FontWeight.w700 : FontWeight.w500,
                          color:
                              done ? AppColors.textPrimary : AppColors.textHint,
                        ),
                      ),
                      if (caption != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            caption,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (date != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      Formatters.shortDateTime(date),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Line item row ───────────────────────────────────────────────────────────

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: ProductImage(
                imageUrl: item.image,
                fit: BoxFit.cover,
                errorIconSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 10),
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
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.quantity} × ${Formatters.myr(item.unitPrice)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textHint,
                  ),
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
}

// ── Per-item "write review / reviewed ✓" state row ──────────────────────────

class _ReviewEntryRow extends ConsumerWidget {
  const _ReviewEntryRow({
    required this.order,
    required this.item,
    required this.onWrite,
  });

  final Order order;
  final OrderItem item;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewAsync = ref.watch(orderReviewProvider((
      productId: item.productId,
      orderId: order.id,
    )));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 38,
              height: 38,
              child: ProductImage(
                imageUrl: item.image,
                fit: BoxFit.cover,
                errorIconSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          reviewAsync.when(
            loading: () => const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, __) => TextButton(
              onPressed: () => ref.invalidate(orderReviewProvider((
                productId: item.productId,
                orderId: order.id,
              ))),
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
            data: (review) => review == null
                ? TextButton.icon(
                    onPressed: onWrite,
                    icon: const Icon(Icons.rate_review_outlined,
                        size: 16, color: AppColors.accent),
                    label: const Text('Write review',
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.accent)),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 13, color: AppColors.success),
                        SizedBox(width: 4),
                        Text('Reviewed ✓',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.success)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Write-review bottom sheet ───────────────────────────────────────────────

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({
    required this.order,
    required this.item,
    required this.userId,
    required this.userName,
  });

  final Order order;
  final OrderItem item;
  final String userId;
  final String userName;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  static const int _minCommentLength = 10;

  int _rating = 0;
  bool _submitting = false;
  String? _commentError;
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _rating == 0) return;
    final comment = _commentCtrl.text.trim();
    if (comment.length < _minCommentLength) {
      setState(() => _commentError =
          'Please share at least $_minCommentLength characters of feedback');
      return;
    }
    setState(() {
      _commentError = null;
      _submitting = true;
    });

    try {
      final review = Review(
        // The review doc id IS the order id — one review per (product,
        // order), and "already reviewed?" stays a cheap doc read.
        id: widget.order.id,
        orderId: widget.order.id,
        userId: widget.userId,
        userName: widget.userName,
        rating: _rating,
        comment: comment,
        createdAt: DateTime.now(),
      );
      await ref
          .read(marketplaceRepositoryProvider)
          .addReview(widget.item.productId, review);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showAppSnackbar(context, 'Could not submit your review — $e',
            color: AppColors.error, duration: const Duration(seconds: 4));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: ProductImage(
                      imageUrl: widget.item.image,
                      fit: BoxFit.cover,
                      errorIconSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'How was it?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  InkWell(
                    onTap: _submitting
                        ? null
                        : () => setState(() => _rating = i),
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        i <= _rating ? Icons.star : Icons.star_border,
                        size: 34,
                        color: i <= _rating
                            ? AppColors.warning
                            : AppColors.border,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _commentCtrl,
              enabled: !_submitting,
              maxLength: 300,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Share what you liked (or didn’t)…',
                errorText: _commentError,
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting || _rating == 0 ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _rating == 0
                            ? 'Tap the stars to rate'
                            : 'Submit review',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small building blocks ───────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  const _MetaRow(this.icon, this.label, {this.sub});

  final IconData icon;
  final String label;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              if (sub != null && sub!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  sub!,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Loading skeleton ────────────────────────────────────────────────────────

class _OrderSkeleton extends StatelessWidget {
  const _OrderSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          Container(
            height: i == 0 ? 200 : 120,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 110,
                  height: 13,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(height: 18),
                for (var j = 0; j < 3; j++) ...[
                  if (j > 0) const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: AppColors.divider,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 11,
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
