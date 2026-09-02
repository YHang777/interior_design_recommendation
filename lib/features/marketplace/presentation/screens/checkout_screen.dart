import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/router/route_names.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/pricing.dart';
import '../../../../../features/auth/presentation/providers/auth_providers.dart';
import '../../../../../models/cart_item.dart';
import '../../../../../models/order.dart';
import '../../../../../services/marketplace_repository.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/price_summary.dart';
import '../../../../../shared/widgets/product_image.dart';
import '../providers/marketplace_providers.dart';

/// Checkout — delivery form, payment method, priced order summary and the
/// stock-safe "Place order" action.
///
/// The order can be built from the whole cart (default) or from a single
/// product when the screen is opened with a [BuyNowRequest] extra: the
/// buy-now order contains ONLY that item and the cart is left untouched.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  String _paymentMethod = 'fpx';
  bool _submitting = false;

  /// Deterministic order id for THIS submission session: generated on the
  /// first attempt and reused across retries so a re-submit after an
  /// ambiguous failure is idempotent (createOrder returns the existing
  /// order instead of charging twice). Reset once an order lands.
  String? _pendingOrderId;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _nameCtrl = TextEditingController(text: user?.name ?? '');
    _phoneCtrl = TextEditingController(text: user?.phone ?? '');
    _addressCtrl = TextEditingController(text: user?.address ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  static String? _phoneValidator(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Phone number is required';
    final digitsOnly =
        v.replaceAll(RegExp(r'[\s\-+()]'), '');
    if (digitsOnly.length < 9 ||
        digitsOnly.length > 15 ||
        !RegExp(r'^\d+$').hasMatch(digitsOnly)) {
      return 'Enter a valid phone number (9–15 digits)';
    }
    return null;
  }

  static String? _addressValidator(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Delivery address is required';
    if (v.length < 10) {
      return 'Please enter your full delivery address (min 10 characters)';
    }
    return null;
  }

  /// The Buy-Now payload carried by this route, when there is one.
  BuyNowRequest? _buyNowRequest() {
    final extra = GoRouterState.of(context).extra;
    return extra is BuyNowRequest ? extra : null;
  }

  /// The rows this checkout will place: the whole (reconciliated) cart, or a
  /// single live-resolved row for a Buy-Now request.
  List<CartRow> _checkoutRows() {
    final buyNow = _buyNowRequest();
    if (buyNow == null) return ref.read(cartRowsProvider);
    final products = ref.read(marketplaceProductsProvider).valueOrNull;
    final live =
        products?.where((p) => p.id == buyNow.product.id).firstOrNull;
    return [
      CartRow(
        item: CartItem(product: buyNow.product, quantity: buyNow.quantity),
        live: live ?? buyNow.product,
        missing: live == null && products != null,
        inactive: live != null && !live.isActive,
      ),
    ];
  }

  /// The failure copy for a blocked row — mirrors the cart screen's banners.
  String? _rowBlockMessage(CartRow row) {
    if (row.missing) return 'No longer available';
    if (row.inactive) return 'No longer on sale';
    if (row.live.stock <= 0) return 'Out of stock';
    return null;
  }

  Future<void> _placeOrder() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      if (!mounted) return;
      showAppSnackbar(context, 'Please fix the highlighted fields',
          color: AppColors.error);
      // The delivery fields sit at the top of the form — scroll back up so
      // the error highlights are actually visible.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (!mounted || !_scrollCtrl.hasClients) return;
        await _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
      return;
    }

    final buyNow = _buyNowRequest();
    final rows = _checkoutRows();
    if (rows.isEmpty) {
      if (!mounted) return;
      showAppSnackbar(context, 'Your cart is empty', color: AppColors.error);
      return;
    }
    // Safety net for rows that went off-sale while on this screen.
    final blocked = rows.where((r) => _rowBlockMessage(r) != null).toList();
    if (blocked.isNotEmpty) {
      if (!mounted) return;
      await _showUnavailableDialog(
        '"${blocked.first.live.name}" ${_rowBlockMessage(blocked.first)!.toLowerCase()}.',
        popOnClose: false,
      );
      return;
    }

    final config = ref.read(configProvider).valueOrNull;
    final tier = ref.read(customerMembershipTierProvider);
    final user = ref.read(currentUserProvider);
    final repo = ref.read(marketplaceRepositoryProvider);
    if (config == null || user == null) {
      if (!mounted) return;
      showAppSnackbar(context, 'Store settings are still loading — '
          'please try again in a moment.', color: AppColors.warning);
      return;
    }

    // ── Money math (shared calculator — same numbers as the summary) ──────
    final subtotal = rows.fold<int>(
        0, (sum, r) => sum + r.live.price * r.effectiveQty);
    final breakdown = computePriceBreakdown(
      subtotal: subtotal,
      discountPercent: tier?.discountPercent ?? 0,
      shippingFee: config.shippingFee,
      freeShippingThreshold: config.freeShippingThreshold,
      taxRate: config.taxRate,
    );

    setState(() => _submitting = true);

    try {
      final items = rows
          .map((r) => OrderItem(
                productId: r.live.id,
                name: r.live.name,
                image: r.live.image,
                unitPrice: r.live.price,
                quantity: r.effectiveQty,
                supplierId: r.live.resolvedSupplierId,
              ))
          .toList();

      _pendingOrderId ??= MarketplaceRepository.newOrderId();
      final order = Order(
        id: _pendingOrderId!,
        orderNumber: '',
        customerId: user.uid,
        customerName: _nameCtrl.text.trim(),
        customerEmail: user.email,
        customerPhone: _phoneCtrl.text.trim(),
        shippingAddress: _addressCtrl.text.trim(),
        items: items,
        status: OrderStatus.pending,
        paymentMethod: _paymentMethod,
        subtotal: breakdown.subtotal,
        shippingFee: breakdown.shippingFee,
        discount: breakdown.discount,
        tax: breakdown.tax,
        membershipTier: tier?.name ?? 'Free',
        total: breakdown.total,
        createdAt: DateTime.now(),
      );

      final created = await repo.createOrder(order);
      if (!mounted) return;

      // Commit the cart clear BEFORE navigating — the confirmation screen
      // must never race a fire-and-forget delete that could resurrect the
      // purchased rows on the next hydration. Buy-now leaves the cart
      // untouched (only the single item was ordered).
      if (buyNow == null) {
        await ref.read(cartProvider.notifier).clearAndPersist();
        if (!mounted) return;
      }
      _pendingOrderId = null;
      context.pushReplacementNamed(
        RouteNames.homeownerOrderConfirmation,
        extra: created.id,
      );
    } on StateError catch (e) {
      // Stock/availability raced between the cart and the transaction —
      // deterministic: nothing committed, safe to retry after adjusting.
      if (!mounted) return;
      await _showUnavailableDialog(e.message, popOnClose: false);
    } catch (_) {
      // Ambiguous failure (timeout, dropped connection, ...): the order MAY
      // have committed server-side. Say so, and keep the same order id for
      // retries — createOrder is idempotent per id, so a re-tap returns the
      // stored order instead of placing it twice.
      if (!mounted) return;
      showAppSnackbar(
        context,
        'Order may have been placed — check your orders',
        color: AppColors.error,
        duration: const Duration(seconds: 6),
        actionLabel: 'View my orders',
        onAction: () =>
            context.pushNamed(RouteNames.homeownerOrderHistory),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Explains a stock/availability failure and sends the buyer back to the
  /// cart to fix quantities. [popOnClose] also pops this screen when the
  /// dialog is dismissed by tapping outside.
  Future<void> _showUnavailableDialog(
    String message, {
    required bool popOnClose,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Some items are no longer available',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          '$message\n\nGo back to your cart, adjust the quantities and try '
          'again.',
          style: const TextStyle(
            fontSize: 13.5,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Stay here',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.pop();
            },
            child: const Text('Back to cart'),
          ),
        ],
      ),
    );
    if (popOnClose && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final buyNow = _buyNowRequest();
    final cart = ref.watch(cartProvider);
    final rows = buyNow == null
        ? ref.watch(cartRowsProvider)
        : _checkoutRows();
    final configAsync = ref.watch(configProvider);
    final tier = ref.watch(customerMembershipTierProvider);

    final config = configAsync.valueOrNull;
    final moneyReady = config != null;
    final unavailableRows =
        rows.where((r) => _rowBlockMessage(r) != null).toList();

    PriceBreakdown? breakdown;
    if (moneyReady) {
      final subtotal =
          rows.fold<int>(0, (sum, r) => sum + r.live.price * r.effectiveQty);
      breakdown = computePriceBreakdown(
        subtotal: subtotal,
        discountPercent: tier?.discountPercent ?? 0,
        shippingFee: config.shippingFee,
        freeShippingThreshold: config.freeShippingThreshold,
        taxRate: config.taxRate,
      );
    }
    final discountPercent = tier?.discountPercent ?? 0;

    final canPlace = !_submitting &&
        moneyReady &&
        unavailableRows.isEmpty &&
        (buyNow != null || rows.isNotEmpty);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Checkout')),
      body: buyNow == null && cart.isEmpty
          ? EmptyState(
              icon: Icons.remove_shopping_cart_outlined,
              title: 'Your cart is empty',
              subtitle: 'Add something you love before checking out.',
              actionLabel: 'Browse the store',
              onAction: () => context.goNamed(RouteNames.homeownerMarketplace),
            )
          : ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                // ── Delivery details ──
                const _SectionTitle('Delivery details'),
                const SizedBox(height: 10),
                Form(
                  key: _formKey,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Full name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            hintText: 'e.g. 012-345 6789',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: _phoneValidator,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _addressCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Delivery address',
                            hintText: 'Street, area, city, postcode, state',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                          validator: _addressValidator,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Payment method ──
                const _SectionTitle('Payment method'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 15, color: AppColors.warning),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Demo checkout — payments are simulated and no '
                          'real charge will occur.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _PaymentOption(
                  icon: Icons.account_balance_outlined,
                  title: 'FPX Online Banking',
                  subtitle: 'Maybank2u, CIMB Clicks, Public Bank and more',
                  value: 'fpx',
                  groupValue: _paymentMethod,
                  onChanged: (v) =>
                      setState(() => _paymentMethod = v ?? 'fpx'),
                ),
                _PaymentOption(
                  icon: Icons.credit_card,
                  title: 'Credit / Debit Card',
                  subtitle: 'Visa, Mastercard or American Express',
                  value: 'card',
                  groupValue: _paymentMethod,
                  onChanged: (v) =>
                      setState(() => _paymentMethod = v ?? 'fpx'),
                ),
                if (_paymentMethod == 'card') ...[
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 15, color: AppColors.warning),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Card payment is simulated in this demo — no '
                            'card details are collected.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                _PaymentOption(
                  icon: Icons.payments_outlined,
                  title: 'Cash on Delivery',
                  subtitle: 'Pay when your order arrives',
                  value: 'cod',
                  groupValue: _paymentMethod,
                  onChanged: (v) =>
                      setState(() => _paymentMethod = v ?? 'fpx'),
                ),
                const SizedBox(height: 20),

                // ── Order summary (Buy-Now mode renames the section) ──
                _SectionTitle(buyNow == null ? 'Order summary' : 'Buy now'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      for (final row in rows) ...[
                        _ItemSummaryRow(row: row),
                        if (_rowBlockMessage(row) != null)
                          _RowBlockNotice(
                              message: _rowBlockMessage(row)!),
                      ],
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1),
                      ),
                      if (!moneyReady)
                        const _SummarySkeleton()
                      else if (breakdown != null)
                        PriceSummaryCard(
                          breakdown: breakdown,
                          discountLabel:
                              'Membership discount (${tier?.name ?? ''}'
                              ' · $discountPercent%)',
                          taxLabel:
                              'Tax (${taxPercentLabel(config.taxRate)})',
                          dividerVerticalPadding: 8,
                        ),
                    ],
                  ),
                ),
                if (unavailableRows.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    buyNow == null
                        ? 'Some items are no longer available — remove them '
                            'from your cart to continue'
                        : 'This item is no longer available — go back and '
                            'choose another',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // ── Place order ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canPlace ? _placeOrder : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Place order'
                            '${breakdown == null ? '' : ' · ${Formatters.myr(breakdown.total)}'}',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'By placing this order you agree to receive the items at '
                  'the delivery address above.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Grey placeholder lines shown in the summary while store config (the
/// shipping fee / free-shipping threshold / tax rate) is still loading —
/// the screen never invents fallback prices.
class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 90 + 40.0 * i,
                height: 11,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Spacer(),
              Container(
                width: 80,
                height: 11,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Compact amber line under a checkout item that can no longer be bought —
/// copy mirrors the cart screen's row banners.
class _RowBlockNotice extends StatelessWidget {
  const _RowBlockNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 14, color: AppColors.warning),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}

/// One cart line in the summary: thumb, name × qty, line total. Rendered
/// against the row's LIVE product so the amounts match the current
/// catalogue.
class _ItemSummaryRow extends StatelessWidget {
  const _ItemSummaryRow({required this.row});

  final CartRow row;

  @override
  Widget build(BuildContext context) {
    final product = row.live;
    final quantity = row.effectiveQty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ProductImage(
              product: product,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorIconSize: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '× $quantity',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            Formatters.myr(product.price * quantity),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final String groupValue;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: RadioListTile<String>(
        value: value,
        groupValue: groupValue,
        onChanged: onChanged,
        activeColor: AppColors.accent,
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        title: Row(
          children: [
            Icon(icon,
                size: 20,
                color:
                    selected ? AppColors.accent : AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ],
        ),
        subtitle: Text(subtitle,
            style: const TextStyle(
                fontSize: 11.5, color: AppColors.textSecondary)),
      ),
    );
  }
}
