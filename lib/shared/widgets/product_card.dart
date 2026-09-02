import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/product.dart';
import 'product_image.dart';
import 'rating_stars.dart';

/// Reusable product card used in marketplace grid and related-product rails.
/// All colors from AppColors — no raw Color() values.
///
/// Visual language (Loop 3): hero image (tag `product-{id}`), discount and
/// eco badges top-left, wishlist heart top-right, low-stock chip and overlay
/// quick actions (AR, add-to-cart) on the image, name/rating/price below.
/// Out-of-stock items get a scrim and lose their buy affordances.
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
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'product-${product.id}',
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      child: ProductImage(
                        product: product,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorIconSize: 32,
                      ),
                    ),
                  ),

                  // Top-left badges: discount first, eco underneath.
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (product.discountPercent != null)
                          _Badge(
                            text: '-${product.discountPercent}%',
                            background: AppColors.error,
                          ),
                        if (product.discountPercent != null &&
                            product.isEcoFriendly)
                          const SizedBox(height: 4),
                        if (product.isEcoFriendly)
                          const _Badge(
                            text: 'Eco',
                            icon: Icons.eco,
                            background: AppColors.success,
                          ),
                      ],
                    ),
                  ),

                  // Wishlist heart (top-right)
                  if (onToggleWishlist != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Semantics(
                        button: true,
                        label: isWishlisted
                            ? 'Remove from wishlist'
                            : 'Add to wishlist',
                        child: Tooltip(
                          message: isWishlisted
                              ? 'Remove from wishlist'
                              : 'Add to wishlist',
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
                      ),
                    ),

                  // Low stock chip (bottom-left)
                  if (product.isLowStock)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Only ${product.stock} left',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),

                  // Out of stock scrim + label
                  if (product.isOutOfStock)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.45),
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('Out of Stock',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),

                  // Bottom-right quick actions: AR preview above add-to-cart.
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onArPreview != null && !product.isOutOfStock) ...[
                          _CircleAction(
                            tooltip: 'View in AR',
                            icon: Icons.view_in_ar,
                            iconColor: AppColors.primary,
                            onTap: onArPreview,
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (onAddToCart != null && !product.isOutOfStock)
                          _CircleAction(
                            tooltip: 'Add to cart',
                            icon: Icons.add_shopping_cart,
                            iconColor: AppColors.accent,
                            onTap: onAddToCart,
                          ),
                      ],
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

                    // Rating (or "New" for unreviewed items)
                    if (!compact) ...[
                      const SizedBox(height: 3),
                      if (product.ratingCount > 0)
                        RatingStars(
                          rating: product.rating,
                          count: product.ratingCount,
                          size: 11,
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('New',
                              style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accent)),
                        ),
                    ],

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
                          Flexible(
                            child: Text(
                              Formatters.myr(product.originalPrice!),
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: compact ? 10 : 11,
                                decoration: TextDecoration.lineThrough,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                        ],
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

/// Small filled label used on the card image (discount %, eco).
class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.background,
    this.icon,
  });

  final String text;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Small circular overlay action (AR / add-to-cart) on the card image.
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.iconColor,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color iconColor;

  /// Callers guard visibility; null simply leaves the button inert.
  final VoidCallback? onTap;

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Icon(icon, size: 15, color: iconColor),
          ),
        ),
      ),
    );
  }
}
