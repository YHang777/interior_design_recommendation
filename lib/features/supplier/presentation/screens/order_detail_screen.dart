import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/order.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/product_image.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../providers/supplier_providers.dart';

/// Full order view for a supplier — buyer details, status timeline, the
/// supplier's own line items (highlighted) next to other sellers' items
/// (muted), and contextual status actions.
class SupplierOrderDetailScreen extends ConsumerStatefulWidget {
  const SupplierOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<SupplierOrderDetailScreen> createState() =>
      _SupplierOrderDetailScreenState();
}

class _SupplierOrderDetailScreenState
    extends ConsumerState<SupplierOrderDetailScreen> {
  /// Status action currently being executed (confirm/ship/deliver/cancel).
  bool _working = false;

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _advance(Order order, OrderStatus next) async {
    final actionLabel = switch (next) {
      OrderStatus.confirmed => 'Confirm',
      OrderStatus.shipped => 'Mark as shipped',
      _ => 'Mark as delivered',
    };
    final confirmed = await showConfirmDialog(
      context,
      title: '$actionLabel this order?',
      message: switch (next) {
        OrderStatus.confirmed =>
          'Confirming locks in the order and tells the buyer you are '
              'fulfilling it.',
        OrderStatus.shipped =>
          'Marking it shipped notifies the buyer that their items are '
              'on the way.',
        _ => 'Marking it delivered completes the order for the buyer.',
      },
      confirmLabel: actionLabel,
    );
    if (!confirmed || !mounted) return;

    setState(() => _working = true);
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      await repo.updateOrderStatus(order.id, next);
      if (mounted) {
        showAppSnackbar(
          context,
          switch (next) {
            OrderStatus.confirmed => 'Order confirmed',
            OrderStatus.shipped => 'Order marked as shipped',
            _ => 'Order marked as delivered',
          },
          color: AppColors.success,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Could not update the order',
            isError: true,
            detail: e.toString(),
            duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancel(Order order) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel this order?',
      message:
          'The buyer will be notified and product stock for every item in '
          'the order is restored automatically. This cannot be undone.',
      confirmLabel: 'Cancel order',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _working = true);
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      await repo.cancelOrder(order.id);
      if (mounted) {
        showAppSnackbar(context, 'Order cancelled — stock has been restored',
            color: AppColors.error, duration: const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Could not cancel the order',
            isError: true,
            detail: e.toString(),
            duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _callBuyer(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    try {
      final uri = Uri(scheme: 'tel', path: digits);
      final ok = await launchUrl(uri);
      if (!ok && mounted) {
        showAppSnackbar(context, 'Could not open the dialer',
            isError: true, duration: const Duration(seconds: 3));
      }
    } catch (_) {
      if (mounted) {
        showAppSnackbar(context, 'Could not open the dialer',
            isError: true, duration: const Duration(seconds: 3));
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final supplierId = user?.uid ?? '';
    final ordersAsync = ref.watch(supplierOrdersProvider(supplierId));
    final isLoading =
        ordersAsync.isLoading && ordersAsync.valueOrNull == null;

    final order = ordersAsync.valueOrNull
        ?.where((o) => o.id == widget.orderId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          order == null ? 'Order detail' : 'Order ${order.orderNumber}',
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : order == null
              ? ordersAsync.hasError
                  ? EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load this order',
                      subtitle: 'Check your connection and try again.',
                      actionLabel: 'Go back',
                      onAction: () => Navigator.of(context).maybePop(),
                    )
                  : EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Order not found',
                      subtitle: 'It may have been removed.',
                      actionLabel: 'Go back',
                      onAction: () => Navigator.of(context).maybePop(),
                    )
              : _body(order),
      bottomNavigationBar: order == null || order.status.isTerminal || _working
          ? null
          : _actionBar(order),
    );
  }

  Widget _body(Order order) {
    final uid = ref.read(currentUserProvider)?.uid ?? '';
    final myItems = orderItemsForSupplier(order, uid);
    final others = order.items.where((i) => i.supplierId != uid).toList();
    final myTotal = mySubtotal(order, uid);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _sectionCard(
          'Order status',
          child: _StatusTimeline(order: order),
        ),
        const SizedBox(height: 14),
        _sectionCard('Buyer', child: _buyerBlock(order)),
        const SizedBox(height: 14),
        _sectionCard(
          'Your items',
          trailing: StatusBadge.order(order.status, compact: true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in myItems) _ItemRow(item: item, mine: true),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 6),
                Divider(height: 1, thickness: 1, color: AppColors.divider),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Other sellers in this order',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
                for (final item in others)
                  Opacity(opacity: 0.55, child: _ItemRow(item: item)),
              ],
              const SizedBox(height: 6),
              Divider(height: 1, thickness: 1, color: AppColors.divider),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Payment: ${order.paymentMethodLabel}',
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Your items total',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            color: AppColors.textHint,
                          ),
                        ),
                        Text(
                          Formatters.myr(myTotal),
                          style: GoogleFonts.poppins(
                            fontSize: 16,
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
        ),
        const SizedBox(height: 16),
        Text(
          'Order ${order.orderNumber} · ${order.id}',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 10.5,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }

  Widget _buyerBlock(Order order) {
    final phone = order.customerPhone.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_outline,
                  size: 20, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.customerName,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    order.customerEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _callBuyer(phone),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.phone_outlined,
                      size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    Formatters.phone(phone),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accent,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.call_outlined,
                      size: 16, color: AppColors.accent),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on_outlined,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                order.shippingAddress,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Timeline ───────────────────────────────────────────────────────────

  Widget _sectionCard(String title, {required Widget child, Widget? trailing}) {
    return Container(
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
                title,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _actionBar(Order order) {
    final next = order.status.next;
    final actions = <Widget>[];
    if (order.status == OrderStatus.pending) {
      actions.add(_actionButton(
        label: 'Cancel order',
        filled: false,
        onTap: _working ? null : () => _cancel(order),
      ));
      actions.add(_actionButton(
        label: 'Confirm order',
        filled: true,
        onTap: _working ? null : () => _advance(order, OrderStatus.confirmed),
      ));
    } else if (next != null) {
      actions.add(_actionButton(
        label: 'Mark as ${next.label.toLowerCase()}',
        filled: true,
        onTap: _working ? null : () => _advance(order, next),
      ));
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: actions[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required bool filled,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 48,
      child: filled
          ? ElevatedButton(
              onPressed: onTap,
              child: onTap == null
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(label),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: .5)),
              ),
              child: onTap == null
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.error),
                    )
                  : Text(label),
            ),
    );
  }
}

/// ── Status timeline (Pending → Confirmed → Shipped → Delivered) ────────

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    if (order.status == OrderStatus.cancelled) return _cancelled();

    final currentIndex = switch (order.status) {
      OrderStatus.pending => 0,
      OrderStatus.confirmed => 1,
      OrderStatus.shipped => 2,
      _ => 3,
    };
    const steps = [
      (OrderStatus.pending, 'Pending', 'Order received'),
      (OrderStatus.confirmed, 'Confirmed', 'Fulfilment started'),
      (OrderStatus.shipped, 'Shipped', 'On its way to the buyer'),
      (OrderStatus.delivered, 'Delivered', 'Order complete'),
    ];
    // Only `createdAt` is stored per order (no per-status timestamps), so the
    // timeline shows the placed date under the first node and no others.
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _stepRow(
            index: i,
            total: steps.length,
            status: steps[i].$1,
            isCurrent: i == currentIndex,
            isDone: i < currentIndex,
            caption: i == 0
                ? 'Placed ${Formatters.shortDateTime(order.createdAt)}'
                : null,
          ),
      ],
    );
  }

  Widget _cancelled() {
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
          Icon(Icons.cancel_outlined, color: AppColors.error, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order cancelled',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Placed ${Formatters.shortDateTime(order.createdAt)}',
                  style: GoogleFonts.poppins(
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

  Widget _stepRow({
    required int index,
    required int total,
    required OrderStatus status,
    required bool isCurrent,
    required bool isDone,
    required String? caption,
  }) {
    final lineColor = (isDone || isCurrent)
        ? AppColors.accent.withValues(alpha: 0.35)
        : AppColors.border;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                _dot(isDone: isDone, isCurrent: isCurrent),
                if (index < total - 1)
                  Expanded(
                    child: Container(width: 2.4, color: lineColor),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: index < total - 1 ? 18 : 0,
                top: index == 0 ? 2 : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        status.label,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: isCurrent
                              ? AppColors.accent
                              : isDone
                                  ? AppColors.textPrimary
                                  : AppColors.textHint,
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        _PillPending(status: status),
                      ],
                    ],
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      style: GoogleFonts.poppins(
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

  Widget _dot({required bool isDone, required bool isCurrent}) {
    final Color bg;
    final Color borderColor;
    final Widget child;
    if (isDone || isCurrent) {
      bg = AppColors.accent;
      borderColor = AppColors.accent;
      child = Icon(Icons.check, size: 14, color: AppColors.textOnDark);
    } else {
      bg = AppColors.surface;
      borderColor = AppColors.border;
      child = const SizedBox.shrink();
    }
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Center(child: child),
    );
  }
}

class _PillPending extends StatelessWidget {
  const _PillPending({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      OrderStatus.pending => 'Action needed',
      OrderStatus.confirmed => 'In progress',
      OrderStatus.shipped => 'In transit',
      _ => '',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

/// ── Line item row ───────────────────────────────────────────────────────

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, this.mine = false});

  final OrderItem item;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: mine
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Your item',
                          style: GoogleFonts.poppins(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.quantity} × ${Formatters.myr(item.unitPrice)}',
                  style: GoogleFonts.poppins(
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
            style: GoogleFonts.poppins(
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
