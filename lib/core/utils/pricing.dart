class PriceBreakdown {
  const PriceBreakdown({
    required this.subtotal,
    required this.discount,
    required this.chargeable,
    required this.tax,
    required this.total,
  });

  final int subtotal;

  final int discount;

  final int chargeable;

  final int tax;

  final int total;

  factory PriceBreakdown.fromStored({
    required int subtotal,
    required int discount,
    required int tax,
    required int total,
  }) {
    return PriceBreakdown(
      subtotal: subtotal,
      discount: discount,
      chargeable: subtotal - discount,
      tax: tax,
      total: total,
    );
  }
}

PriceBreakdown computePriceBreakdown({
  required int subtotal,
  required int discountPercent,
  required double taxRate,
}) {
  final discount = (subtotal * discountPercent / 100).round();
  final chargeable = subtotal - discount;
  final tax = (chargeable * taxRate).round();
  return PriceBreakdown(
    subtotal: subtotal,
    discount: discount,
    chargeable: chargeable,
    tax: tax,
    total: chargeable + tax,
  );
}

String taxPercentLabel(double taxRate) =>
    '${(taxRate * 100).round()}%';
