import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/pricing.dart';

/// One label/value row of a money summary — the shared replacement for the
/// private `_Line`/`_SummaryLine` copies the checkout, order-confirmation
/// and buyer-order-detail screens each used to keep. Same fonts, spacing
/// and colors as the originals.
class SummaryLine extends StatelessWidget {
  const SummaryLine(this.label, this.value,
      {super.key, this.bold = false, this.valueColor});

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 15 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color: bold ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 17 : 13.5,
              fontWeight: FontWeight.w700,
              color: valueColor ??
                  (bold ? AppColors.accent : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The standard money column — Subtotal, membership discount (when > 0),
/// Shipping (FREE in success green once unlocked), Tax and a divider before
/// the bold Total — rendered from one [PriceBreakdown].
///
/// Screens wrap this in their own bordered card; [dividerVerticalPadding]
/// lets each screen keep its original rhythm above the Total divider.
class PriceSummaryCard extends StatelessWidget {
  const PriceSummaryCard({
    super.key,
    required this.breakdown,
    this.discountLabel,
    this.taxLabel = 'Tax',
    this.dividerVerticalPadding = 6,
  });

  final PriceBreakdown breakdown;

  /// Label for the discount row (e.g. "Membership discount (Gold)").
  /// The row only renders while [PriceBreakdown.discount] is > 0.
  final String? discountLabel;

  /// Tax row label, e.g. "Tax (6%)".
  final String taxLabel;

  final double dividerVerticalPadding;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SummaryLine('Subtotal', Formatters.myr(breakdown.subtotal)),
        if (breakdown.discount > 0)
          SummaryLine(
            discountLabel ?? 'Membership discount',
            '−${Formatters.myr(breakdown.discount)}',
            valueColor: AppColors.success,
          ),
        SummaryLine(
          'Shipping',
          breakdown.shippingFee == 0
              ? 'FREE'
              : Formatters.myr(breakdown.shippingFee),
          valueColor: breakdown.shippingFee == 0
              ? AppColors.success
              : null,
        ),
        SummaryLine(taxLabel, Formatters.myr(breakdown.tax)),
        Padding(
          padding: EdgeInsets.symmetric(vertical: dividerVerticalPadding),
          child: const Divider(height: 1),
        ),
        SummaryLine('Total', Formatters.myr(breakdown.total), bold: true),
      ],
    );
  }
}
