import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/user_errors.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import '../../models/order.dart';
import '../../services/invoice/invoice_pdf.dart';
import '../widgets/app_feedback.dart';
import '../widgets/empty_state.dart';
import '../widgets/float_button.dart';
import '../widgets/page_heading.dart';
import '../widgets/price_summary.dart';
import '../widgets/status_badge.dart';

/// Tax invoice for ONE supplier's portion of an order — the seller's
/// paperwork and the buyer's receipt for that shipment, opened from the
/// supplier's order detail (accept / view) and the buyer's order detail.
///
/// Live: resolves the order through the signed-in user's own order stream —
/// the supplier stream for the seller, the customer stream for the buyer —
/// with the same find-by-id pattern as the two order detail screens, so an
/// invoice issued moments ago is already here on arrival.
class OrderInvoiceScreen extends ConsumerStatefulWidget {
  const OrderInvoiceScreen({
    super.key,
    required this.orderId,
    required this.supplierId,
  });

  final String orderId;

  /// The seller this invoice belongs to — a shared order has one per seller.
  final String supplierId;

  @override
  ConsumerState<OrderInvoiceScreen> createState() =>
      _OrderInvoiceScreenState();
}

class _OrderInvoiceScreenState extends ConsumerState<OrderInvoiceScreen> {
  /// A share/print call in flight — disables both buttons so one tap cannot
  /// queue two OS dialogs.
  bool _working = false;

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _share(OrderInvoice invoice) async {
    setState(() => _working = true);
    try {
      await InvoicePdf.share(invoice);
      if (mounted) {
        showAppSnackbar(context, 'Invoice PDF ready to share',
            duration: const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
            context,
            userMessage(e,
                fallback:
                    'Could not prepare the invoice PDF. Please try again.'),
            isError: true,
            duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _print(OrderInvoice invoice) async {
    setState(() => _working = true);
    try {
      await InvoicePdf.print(invoice);
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
                    'Could not prepare the invoice PDF. Please try again.'),
            isError: true,
            duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Re-subscribes to whichever order stream this role resolves through.
  void _retry() {
    if (ref.read(currentUserProvider)?.uid == widget.supplierId) {
      ref.invalidate(supplierOrdersProvider(widget.supplierId));
    } else {
      ref.invalidate(customerOrdersProvider);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserProvider)?.uid ?? '';
    // Seller resolves through their supplier stream, buyer through theirs —
    // Firestore only lets each role read their own list anyway.
    final ordersAsync = uid == widget.supplierId
        ? ref.watch(supplierOrdersProvider(widget.supplierId))
        : ref.watch(customerOrdersProvider);
    final isLoading =
        ordersAsync.isLoading && ordersAsync.valueOrNull == null;
    final order = ordersAsync.valueOrNull
        ?.where((o) => o.id == widget.orderId)
        .firstOrNull;
    final invoice = order?.invoiceFor(widget.supplierId);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : order == null
                    ? ordersAsync.hasError
                        ? EmptyState(
                            icon: Icons.cloud_off_outlined,
                            title: 'Could not load this invoice',
                            subtitle: 'Check your connection and try again.',
                            actionLabel: 'Retry',
                            onAction: _retry,
                          )
                        : EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'Order not found',
                            subtitle: 'It may have been removed.',
                            actionLabel: 'Back',
                            onAction: () =>
                                Navigator.of(context).maybePop(),
                          )
                    // Never a crash and never a dead Share/Print: the seller
                    // simply has not issued this shipment's paperwork yet.
                    : invoice == null
                        ? EmptyState(
                            icon: Icons.request_page_outlined,
                            title: 'No invoice yet',
                            subtitle:
                                'The seller has not issued this invoice yet.',
                            actionLabel: 'Back',
                            onAction: () =>
                                Navigator.of(context).maybePop(),
                          )
                        : _body(order, invoice),
          ),
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 8,
            left: 8,
            child: const FloatingBackButton(),
          ),
        ],
      ),
      bottomNavigationBar: invoice == null ? null : _actionBar(invoice),
    );
  }

  Widget _body(Order order, OrderInvoice invoice) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 60, 16, MediaQuery.paddingOf(context).bottom + 32),
      children: [
        PageHeading(
          title: 'Invoice ${invoice.invoiceNumber}',
          subtitle: 'Issued ${Formatters.shortDate(invoice.issuedAt)}',
          actions: [StatusBadge.order(order.status, compact: true)],
        ),
        const SizedBox(height: 16),
        _sectionCard('From', child: _partyBlock(name: invoice.supplierName, lines: [
          invoice.supplierAddress,
          if (invoice.supplierPhone.trim().isNotEmpty)
            Formatters.phone(invoice.supplierPhone.trim()),
          invoice.supplierEmail,
        ])),
        const SizedBox(height: 14),
        _sectionCard('To', child: _partyBlock(name: invoice.customerName, lines: [
          invoice.shippingAddress,
          if (invoice.customerPhone.trim().isNotEmpty)
            Formatters.phone(invoice.customerPhone.trim()),
          invoice.customerEmail,
        ])),
        const SizedBox(height: 14),
        _sectionCard(
          'Reference',
          child: Column(
            children: [
              _refRow('Order',
                  Formatters.formatOrderNumber(invoice.orderNumber)),
              _refRow('Order placed',
                  Formatters.shortDateTime(invoice.orderCreatedAt)),
              // The invoice freezes the raw payment code; the order holds the
              // same value, so its label getter can pretty-print it here.
              if (invoice.paymentMethod.trim().isNotEmpty)
                _refRow('Payment', order.paymentMethodLabel),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          'Items',
          child: invoice.items.isEmpty
              ? Text(
                  'No items on this invoice.',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: AppColors.textHint),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < invoice.items.length; i++) ...[
                      if (i > 0)
                        Divider(height: 14, thickness: 0.6,
                            color: AppColors.divider),
                      _itemRow(invoice.items[i]),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${invoice.lineCount} line items · '
                      '${invoice.unitCount} units',
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: AppColors.textHint),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          'Totals',
          child: Column(
            children: [
              SummaryLine('Items subtotal', Formatters.myr(invoice.subtotal)),
              SummaryLine('Shipping', Formatters.myr(invoice.shippingFee)),
              Divider(height: 1, thickness: 1, color: AppColors.divider),
              SummaryLine(
                'Total for this shipment',
                Formatters.myr(invoice.total),
                bold: true,
              ),
              // Order-level discount/tax are not attributable to one seller,
              // so they are stated for reference and never summed into the
              // shipment total.
              if (invoice.orderDiscount > 0 || invoice.orderTax > 0) ...[
                const SizedBox(height: 6),
                Text(
                  _adjustmentNote(invoice),
                  textAlign: TextAlign.right,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textHint,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Order ${invoice.orderNumber} · ${invoice.orderId}',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 10.5,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }

  // ── Building blocks ────────────────────────────────────────────────────

  String _adjustmentNote(OrderInvoice invoice) {
    final parts = <String>[
      if (invoice.orderDiscount > 0)
        'Order-level discount: ${Formatters.myr(invoice.orderDiscount)}',
      if (invoice.orderTax > 0) 'Tax: ${Formatters.myr(invoice.orderTax)}',
    ];
    return '${parts.join(' · ')} (not charged to this shipment)';
  }

  Widget _sectionCard(String title, {required Widget child}) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
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

  /// One from/to block. Empty fields are dropped rather than shown blank.
  Widget _partyBlock({required String name, required List<String> lines}) {
    final details = <String>[
      for (final raw in lines)
        if (raw.trim().isNotEmpty) raw.trim(),
    ];
    if (name.trim().isEmpty && details.isEmpty) {
      return Text(
        'Not recorded',
        style: GoogleFonts.poppins(
            fontSize: 12.5, color: AppColors.textHint),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (name.trim().isNotEmpty) ...[
          Text(
            name.trim(),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (details.isNotEmpty) const SizedBox(height: 4),
        ],
        for (final line in details)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              line,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _refRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
                fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.quantity} × ${Formatters.myr(item.unitPrice)}',
                  style: GoogleFonts.poppins(
                      fontSize: 11.5, color: AppColors.textHint),
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

  // ── Action bar ─────────────────────────────────────────────────────────

  Widget _actionBar(OrderInvoice invoice) {
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
                child: _pdfButton(
                  label: 'Share PDF',
                  filled: true,
                  onTap: _working ? null : () => _share(invoice),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _pdfButton(
                  label: 'Print',
                  filled: false,
                  onTap: _working ? null : () => _print(invoice),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pdfButton({
    required String label,
    required bool filled,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 52,
      child: filled
          ? Container(
              decoration: BoxDecoration(
                gradient: onTap != null
                    ? const LinearGradient(
                        colors: [AppColors.accent, AppColors.gradientGreen],
                      )
                    : null,
                borderRadius: BorderRadius.circular(14),
                color: onTap == null ? AppColors.border : null,
              ),
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.transparent,
                  disabledForegroundColor: AppColors.textHint,
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: onTap == null
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: onTap == null
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textSecondary),
                    )
                  : Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
            ),
    );
  }
}
