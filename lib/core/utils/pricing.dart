class PriceBreakdown {
  const PriceBreakdown({
    required this.subtotal,
    required this.discount,
    required this.chargeable,
    required this.shippingFee,
    required this.tax,
    required this.total,
  });

  final int subtotal;

  final int discount;

  final int chargeable;

  final int shippingFee;

  final int tax;

  final int total;

  factory PriceBreakdown.fromStored({
    required int subtotal,
    required int discount,
    required int shippingFee,
    required int tax,
    required int total,
  }) {
    return PriceBreakdown(
      subtotal: subtotal,
      discount: discount,
      chargeable: subtotal - discount,
      shippingFee: shippingFee,
      tax: tax,
      total: total,
    );
  }
}

PriceBreakdown computePriceBreakdown({
  required int subtotal,
  required int discountPercent,
  required int shippingFee,
  required int freeShippingThreshold,
  required double taxRate,
}) {
  final discount = (subtotal * discountPercent / 100).round();
  final chargeable = subtotal - discount;
  final effectiveShipping =
      chargeable >= freeShippingThreshold ? 0 : shippingFee;
  final tax = (chargeable * taxRate).round();
  return PriceBreakdown(
    subtotal: subtotal,
    discount: discount,
    chargeable: chargeable,
    shippingFee: effectiveShipping,
    tax: tax,
    total: chargeable + effectiveShipping + tax,
  );
}

String taxPercentLabel(double taxRate) =>
    '${(taxRate * 100).round()}%';
