import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../models/product.dart';

/// Buyer-facing "Verified" trust pill for suppliers an admin has approved
/// (IC + documents reviewed). Style follows [StatusBadge] compact density:
/// success tint, Poppins, icon + label — small enough never to out-shout a
/// product name.
///
/// The gate lives HERE, not at the call sites: anything other than exactly
/// 'verified' renders [SizedBox.shrink], so a pending/rejected supplier can
/// never show a trust signal on the buyer side. Absence of the badge is the
/// signal — there is deliberately no greyed-out "Unverified" variant.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.verificationStatus});

  /// `Supplier.verificationStatus` — 'none' | 'pending' | 'verified' |
  /// 'rejected'.
  final String verificationStatus;

  @override
  Widget build(BuildContext context) {
    if (verificationStatus != 'verified') return const SizedBox.shrink();

    return Container(
      // Dense on purpose: the badge shares the product card's tight info
      // column, where every extra pixel risks a RenderFlex overflow on
      // narrow (320dp) phones.
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified, size: 11, color: AppColors.success),
          const SizedBox(width: 4),
          Text(
            'Verified',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Seller attribution line: the supplier's name followed by [VerifiedBadge]
/// on one row (name first, so the pill reads as "this seller is verified").
///
/// Renders [SizedBox.shrink] unless the supplier is genuinely verified —
/// screens using it are pixel-identical for unverified sellers, which keeps
/// the addition surgical and the signal honest.
class VerifiedSellerLine extends StatelessWidget {
  const VerifiedSellerLine({
    super.key,
    required this.supplier,
    this.nameStyle,
  });

  final Supplier supplier;

  /// Style for the supplier name; defaults to a hint-toned caption so the
  /// pill stays the more prominent of the two.
  final TextStyle? nameStyle;

  @override
  Widget build(BuildContext context) {
    if (!supplier.isVerified) return const SizedBox.shrink();

    final name = supplier.name.trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name.isNotEmpty) ...[
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: nameStyle ??
                  GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textHint,
                    height: 1.2,
                  ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        VerifiedBadge(verificationStatus: supplier.verificationStatus),
      ],
    );
  }
}
