import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/router/route_names.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/pricing.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../../models/cart_item.dart';
import '../../../../../services/marketplace_api.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/float_button.dart';
import '../../../../../shared/widgets/page_heading.dart';
import '../../../../../shared/widgets/price_summary.dart';
import '../../../../../shared/widgets/product_image.dart';
import '../../../../../shared/widgets/verified_badge.dart';
import '../providers/marketplace_providers.dart';

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
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Wake the payment host now so Pay now doesn't absorb a cold start.
    MarketplaceApi().warmUp();
    final user = ref.read(currentUserProvider);
    _nameCtrl = TextEditingController(text: user?.name ?? '');
    _phoneCtrl = TextEditingController(text: user?.phone ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  static String? _phoneValidator(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Phone number is required';
    final digitsOnly = v.replaceAll(RegExp(r'[\s\-+()]'), '');
    if (digitsOnly.length < 9 ||
        digitsOnly.length > 15 ||
        !RegExp(r'^\d+$').hasMatch(digitsOnly)) {
      return 'Enter a valid phone number (9–15 digits)';
    }
    return null;
  }

  BuyNowRequest? _buyNowRequest() {
    final extra = GoRouterState.of(context).extra;
    return extra is BuyNowRequest ? extra : null;
  }

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
    if (config == null || user == null) {
      if (!mounted) return;
      showAppSnackbar(context, 'Store settings are still loading — '
          'please try again in a moment.', color: AppColors.warning);
      return;
    }

    setState(() => _submitting = true);

    // ── Stripe Payment Sheet: server creates the order + PaymentIntent ─────
    final api = MarketplaceApi();
    String? createdOrderId;
    var phase = 'intent';
    try {
      final intent = await api.createCheckoutIntent(
        items: [
          for (final r in rows)
            CheckoutItem(productId: r.live.id, quantity: r.effectiveQty),
        ],
        customerName: _nameCtrl.text.trim(),
        customerPhone: _phoneCtrl.text.trim(),
        membershipTier: tier?.name ?? 'Free',
      );
      createdOrderId = intent.orderId;

      phase = 'sheet';
      if (intent.clientSecret.isEmpty || intent.publishableKey.isEmpty) {
        throw PaymentApiException(
            'Payments are not set up yet. Please try again later.');
      }
      Stripe.publishableKey = intent.publishableKey;
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: intent.clientSecret,
          merchantDisplayName: 'Intellar',
          style: ThemeMode.light,
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      // The sheet closing is not proof of payment — the server re-checks
      // Stripe and marks the order paid (idempotent with the webhook).
      phase = 'verify';
      final verification = await api.verifyPayment(intent.orderId);
      if (!verification.paid) {
        await api.abandonCheckout(intent.orderId);
        if (!mounted) return;
        showAppSnackbar(context, 'Payment was not completed. Please try again.',
            color: AppColors.error);
        return;
      }

      if (buyNow == null) {
        await ref.read(cartProvider.notifier).clearAndPersist();
      }
      if (!mounted) return;
      context.pushReplacementNamed(
        RouteNames.homeownerOrderConfirmation,
        extra: intent.orderId,
      );
    } on StripeException catch (e) {
      if (createdOrderId != null) await api.abandonCheckout(createdOrderId);
      if (!mounted) return;
      if (e.error.code == FailureCode.Canceled) {
        showAppSnackbar(context, 'Payment cancelled');
      } else {
        showAppSnackbar(
            context, 'Payment could not be completed. Please try again.',
            color: AppColors.error);
      }
    } on PaymentApiException catch (e) {
      // Abandon is Stripe-state-checked server-side, so it is safe even if a
      // payment actually landed (it marks the order paid instead of releasing).
      if (createdOrderId != null) await api.abandonCheckout(createdOrderId);
      if (!mounted) return;
      if (phase == 'verify') {
        showAppSnackbar(
          context,
          'Payment may have completed — check your orders.',
          color: AppColors.warning,
          duration: const Duration(seconds: 6),
          actionLabel: 'View my orders',
          onAction: () => context.pushNamed(RouteNames.homeownerOrderHistory),
        );
      } else {
        showAppSnackbar(context, e.message, color: AppColors.error);
      }
    } catch (_) {
      if (createdOrderId != null) await api.abandonCheckout(createdOrderId);
      if (!mounted) return;
      if (phase == 'verify') {
        showAppSnackbar(
          context,
          'Payment may have completed — check your orders.',
          color: AppColors.warning,
          duration: const Duration(seconds: 6),
          actionLabel: 'View my orders',
          onAction: () => context.pushNamed(RouteNames.homeownerOrderHistory),
        );
      } else {
        showAppSnackbar(context, 'Something went wrong. Please try again.',
            color: AppColors.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

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
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ConfirmDialogActions(
            confirmLabel: 'Back to cart',
            cancelLabel: 'Stay here',
            onCancel: () => Navigator.pop(ctx),
            onConfirm: () {
              Navigator.pop(ctx);
              context.pop();
            },
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
      body: Stack(
        children: [
          buyNow == null && cart.isEmpty
              ? SafeArea(
                  child: EmptyState(
                    icon: Icons.remove_shopping_cart_outlined,
                    title: 'Your cart is empty',
                    subtitle: 'Add something you love before checking out.',
                    actionLabel: 'Browse the store',
                    onAction: () =>
                        context.goNamed(RouteNames.homeownerMarketplace),
                  ),
                )
              : SafeArea(
                  child: ListView(
                    controller: _scrollCtrl,
                    padding: EdgeInsets.fromLTRB(16, 60, 16,
                        MediaQuery.paddingOf(context).bottom + 32),
                    children: [
                      const PageHeading(title: 'Checkout'),
                      const SizedBox(height: 16),

                      // ── Contact details ──
                      const _SectionTitle('Contact details'),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: 'Phone number',
                                  hintText: 'e.g. 012-345 6789',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                ),
                                validator: _phoneValidator,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Suppliers will contact you on these details '
                                'to arrange collection.',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.4,
                                  color: AppColors.textHint
                                      .withValues(alpha: 0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Payment ──
                      const _SectionTitle('Payment'),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.lock_outline,
                                    size: 15, color: AppColors.accent),
                                SizedBox(width: 8),
                                Text(
                                  'Secure payment by Stripe',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Pay by credit / debit card or FPX online '
                              'banking. Your items are reserved while you '
                              'pay.',
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.4,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                            const Row(
                              children: [
                                Icon(Icons.storefront_outlined,
                                    size: 15, color: AppColors.accent),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Self-collection — collect your order '
                                    'from each supplier\'s store. No '
                                    'delivery fee.',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      height: 1.4,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
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

                      // ── Pay ──
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: canPlace
                                ? const LinearGradient(
                                    colors: [AppColors.accent, AppColors.gradientGreen],
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: ElevatedButton(
                            onPressed: canPlace ? _placeOrder : null,
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
                            child: _submitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Pay now'
                                      '${breakdown == null ? '' : ' · ${Formatters.myr(breakdown.total)}'}',
                                      maxLines: 1,
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'By paying you agree to collect the items from the '
                        'suppliers\' stores.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.4,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 8,
            left: 8,
            child: const FloatingBackButton(),
          ),
        ],
      ),
    );
  }
}

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
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            '${_stepNumber(title)}',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 1,
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static int _stepNumber(String title) {
    const steps = {
      'Contact details': 1,
      'Payment': 2,
      'Order summary': 3,
      'Buy now': 3,
    };
    return steps[title] ?? 0;
  }
}

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
                VerifiedSellerLine(
                  supplier: product.supplier,
                  nameStyle: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textHint,
                    height: 1.2,
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
