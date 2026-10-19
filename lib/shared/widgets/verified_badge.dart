import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../models/product.dart';

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.verificationStatus});

  final String verificationStatus;

  @override
  Widget build(BuildContext context) {
    if (verificationStatus != 'verified') return const SizedBox.shrink();

    return Container(
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

class VerifiedSellerLine extends StatelessWidget {
  const VerifiedSellerLine({
    super.key,
    required this.supplier,
    this.nameStyle,
  });

  final Supplier supplier;

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
