import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/product.dart';
import 'rating_stars.dart';

/// Reusable product card used in marketplace grid, wishlist, and related
/// products. All colors from AppColors — no raw Color() values.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.isWishlisted = false,
    this.onTap,
    this.onAddToCart,
    this.onToggleWishlist,
    this.onArPreview,
    this.compact = false,
  });

  final Product product;
  final bool isWishlisted;
  final VoidCallback? onTap;
  final VoidCallback? onAddToCart;
  final VoidCallback? onToggleWishlist;
  final VoidCallback? onArPreview;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image with overlays ──
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Image.asset(
                      product.image,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.divider,
                        child: const Icon(Icons.image,
                            size: 32, color: AppColors.textHint),
                      ),
                    ),
                  ),

                  // Eco-friendly badge (top-left)
                  if (product.isEcoFriendly)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.eco, size: 12, color: Colors.white),
                            SizedBox(width: 2),
                            Text('Eco',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),

                  // Wishlist heart (top-right)
                  if (onToggleWishlist != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onToggleWishlist,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isWishlisted
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 18,
                              color: isWishlisted
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Out of stock overlay
                  if (product.isOutOfStock)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16)),
                        ),
                        child: const Center(
                          child: Text('Out of Stock',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),

                  // AR preview button (bottom-right of image)
                  if (onArPreview != null && !product.isOutOfStock)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onArPreview,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.75),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.view_in_ar,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Info section ──
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.all(compact ? 8 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),

                    // Rating
                    if (!compact)
                      RatingStars(
                        rating: product.rating,
                        count: product.ratingCount,
                        size: 11,
                      ),

                    // Price row
                    Row(
                      children: [
                        Text(
                          Formatters.myr(product.price),
                          style: GoogleFonts.poppins(
                            fontSize: compact ? 13 : 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accent,
                          ),
                        ),
                        if (product.originalPrice != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            Formatters.myr(product.originalPrice!),
                            style: GoogleFonts.poppins(
                              fontSize: compact ? 10 : 11,
                              decoration: TextDecoration.lineThrough,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Category + Stock + Add-to-cart
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                AppColors.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            product.category,
                            style: GoogleFonts.poppins(
                                fontSize: compact ? 8 : 9,
                                color: AppColors.accent),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          product.isOutOfStock
                              ? 'OOS'
                              : product.isLowStock
                                  ? '${product.stock} left'
                                  : '',
                          style: GoogleFonts.poppins(
                            fontSize: compact ? 8 : 9,
                            color: product.isLowStock
                                ? AppColors.warning
                                : AppColors.textHint,
                          ),
                        ),
                        const Spacer(),
                        if (onAddToCart != null && !product.isOutOfStock)
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onAddToCart,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.add,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
