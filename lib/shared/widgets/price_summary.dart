import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/pricing.dart';

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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: bold ? 15 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color:
                    bold ? AppColors.textPrimary : AppColors.textSecondary,
                letterSpacing: 0.1,
                height: 1.4,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: bold ? 17 : 14,
              fontWeight: FontWeight.w700,
              color: valueColor ??
                  (bold ? AppColors.accent : AppColors.textPrimary),
              letterSpacing: bold ? -0.3 : 0.1,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class PriceSummaryCard extends StatelessWidget {
  const PriceSummaryCard({
    super.key,
    required this.breakdown,
    this.discountLabel,
    this.taxLabel = 'Tax',
    this.dividerVerticalPadding = 6,
  });

  final PriceBreakdown breakdown;

  final String? discountLabel;

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
          'Self-collection',
          'FREE',
          valueColor: AppColors.success,
        ),
        SummaryLine(taxLabel, Formatters.myr(breakdown.tax)),
        Padding(
          padding: EdgeInsets.symmetric(vertical: dividerVerticalPadding),
          child: Divider(height: 1, color: AppColors.divider),
        ),
        SummaryLine('Total', Formatters.myr(breakdown.total), bold: true),
      ],
    );
  }
}
