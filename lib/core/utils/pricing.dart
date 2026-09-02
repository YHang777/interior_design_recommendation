/// The one place money math happens for an order or cart. All amounts are
/// whole-ringgit integers.
///
/// Relationship between fields:
///   chargeable   = subtotal − discount
///   shippingFee  = 0 when chargeable ≥ freeShippingThreshold, else the
///                  flat fee
///   tax          = round(chargeable × taxRate)
///   total        = chargeable + shippingFee + tax
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

  /// Membership discount applied (whole ringgit).
  final int discount;

  /// Subtotal minus discount — the amount shipping thresholds compare
  /// against.
  final int chargeable;

  /// Effective shipping charge (0 once free shipping unlocks).
  final int shippingFee;

  /// Sales tax on the chargeable amount (whole ringgit).
  final int tax;

  final int total;

  /// Builds a breakdown from values ALREADY computed/stored on an order
  /// (the confirmation and order-detail screens re-display a persisted
  /// order rather than recompute it).
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

/// Computes a [PriceBreakdown] with the app's standard rules:
///
/// - the membership discount is applied first,
/// - shipping is free once the POST-DISCOUNT chargeable amount reaches the
///   [freeShippingThreshold] (the cart banner and the checkout summary must
///   both follow this or they contradict each other),
/// - tax applies to the chargeable amount.
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

/// Human label for a tax rate, e.g. 0.06 → "6%".
String taxPercentLabel(double taxRate) =>
    '${(taxRate * 100).round()}%';
