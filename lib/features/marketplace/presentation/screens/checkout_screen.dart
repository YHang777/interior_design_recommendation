import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/validators.dart';
import '../../../../../features/auth/presentation/providers/auth_providers.dart';
import '../../../../../models/order.dart';
import '../providers/marketplace_providers.dart';

/// Checkout screen — shipping form, payment method, order summary, place order.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  String _paymentMethod = 'card_fpx';
  bool _submitting = false;

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
    super.dispose();
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    if (_submitting) return;

    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    final config =
        ref.read(configProvider).valueOrNull;
    final shippingFee = config?.shippingFee ?? 25;
    final freeThreshold = config?.freeShippingThreshold ?? 500;
    final total = ref.read(cartTotalProvider);
    final actualShipping = total >= freeThreshold ? 0 : shippingFee;

    final user = ref.read(currentUserProvider);
    final service = ref.read(marketplaceServiceProvider);

    setState(() => _submitting = true);

    try {
      // Build order items from cart
      final items = cart
          .map((ci) => OrderItem(
                productId: ci.product.id,
                name: ci.product.name,
                image: ci.product.image,
                unitPrice: ci.product.price,
                quantity: ci.quantity,
                supplierId: ci.product.supplier.id,
              ))
          .toList();

      final order = Order(
        id: '',
        orderNumber: '',
        customerId: user?.uid ?? 'anonymous',
        customerName: _nameCtrl.text.trim(),
        customerEmail: user?.email ?? '',
        customerPhone: _phoneCtrl.text.trim(),
        shippingAddress: _addressCtrl.text.trim(),
        items: items,
        status: OrderStatus.pending,
        paymentMethod: _paymentMethod,
        subtotal: total,
        shippingFee: actualShipping,
        total: total + actualShipping,
        createdAt: DateTime.now(),
      );

      final created = await service.createOrder(order);

      if (!mounted) return;

      // Clear cart
      ref.read(cartProvider.notifier).clear();

      // Navigate to confirmation
      context.pushReplacement(
        '/marketplace/order-confirmation',
        extra: {
          'orderNumbers': [created.orderNumber],
          'total': created.total,
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order failed: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);
    final configAsync = ref.watch(configProvider);

    final shippingFee =
        configAsync.whenOrNull(data: (c) => c.shippingFee) ?? 25;
    final freeThreshold =
        configAsync.whenOrNull(data: (c) => c.freeShippingThreshold) ?? 500;
    final actualShipping = total >= freeThreshold ? 0 : shippingFee;
    final grandTotal = total + actualShipping;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Checkout')),
      body: cart.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Your cart is empty',
                      style: TextStyle(
                          fontSize: 16, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Back to Cart'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Shipping Details ──
                const Text('Shipping Details',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Form(
                  key: _formKey,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: Icon(Icons.person)),
                          validator: Validators.required,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Phone Number',
                              prefixIcon: Icon(Icons.phone)),
                          keyboardType: TextInputType.phone,
                          validator: Validators.required,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _addressCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Shipping Address',
                              prefixIcon:
                                  Icon(Icons.location_on)),
                          maxLines: 3,
                          validator: Validators.required,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Payment Method ──
                const Text('Payment Method',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                _PaymentOption(
                  icon: Icons.credit_card,
                  title: 'Card / FPX',
                  subtitle: 'Credit card or online banking',
                  value: 'card_fpx',
                  groupValue: _paymentMethod,
                  onChanged: (v) =>
                      setState(() => _paymentMethod = v!),
                ),
                _PaymentOption(
                  icon: Icons.account_balance_wallet,
                  title: 'E-Wallet',
                  subtitle: 'Touch \'n Go, GrabPay, etc.',
                  value: 'ewallet',
                  groupValue: _paymentMethod,
                  onChanged: (v) =>
                      setState(() => _paymentMethod = v!),
                ),
                _PaymentOption(
                  icon: Icons.payments,
                  title: 'Cash on Delivery',
                  subtitle: 'Pay when you receive',
                  value: 'cod',
                  groupValue: _paymentMethod,
                  onChanged: (v) =>
                      setState(() => _paymentMethod = v!),
                ),
                const SizedBox(height: 20),

                // ── Order Summary ──
                const Text('Order Summary',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      ...cart.map((ci) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Text(
                                    '${ci.product.name} × ${ci.quantity}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors
                                            .textSecondary)),
                                const Spacer(),
                                Text(
                                    Formatters.myr(
                                        ci.lineTotal),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors
                                            .textPrimary)),
                              ],
                            ),
                          )),
                      const Divider(),
                      _SummaryLine(
                          'Subtotal', Formatters.myr(total)),
                      _SummaryLine('Shipping',
                          Formatters.myr(actualShipping)),
                      if (total >= freeThreshold)
                        const Text(
                            '🎉 Free shipping applied!',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.success)),
                      const Divider(),
                      _SummaryLine('Total',
                          Formatters.myr(grandTotal),
                          bold: true),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Place Order ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _placeOrder,
                    style: ElevatedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white),
                          )
                        : Text(
                            'Place Order — ${Formatters.myr(grandTotal)}',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                const SizedBox(height: 32),
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
  final String title, subtitle, value, groupValue;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? AppColors.accent : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: RadioListTile<String>(
        value: value,
        groupValue: groupValue,
        onChanged: onChanged,
        activeColor: AppColors.accent,
        title: Row(
          children: [
            Icon(icon,
                size: 20,
                color: selected
                    ? AppColors.accent
                    : AppColors.textSecondary),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
        subtitle: Text(subtitle,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine(this.label, this.value, {this.bold = false});
  final String label, value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: bold ? 16 : 14,
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.w400)),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 18 : 14,
                  fontWeight: FontWeight.w700,
                  color: bold
                      ? AppColors.accent
                      : AppColors.textPrimary)),
        ],
      ),
    );
  }
}
