import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/rating_stars.dart';
import '../../../../../shared/widgets/section_header.dart';
import '../../../../../shared/widgets/product_card.dart';
import '../providers/marketplace_providers.dart';
import '../../../ar/data/furniture_model_library.dart';

/// Full-screen product detail page with hero image, qty selector, supplier info,
/// and related products.
class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _qty = 1;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final isWishlisted =
        ref.watch(wishlistProvider).contains(widget.productId);

    return productsAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Loading…')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Error')),
        body: EmptyState(
          icon: Icons.error_outline,
          title: 'Failed to load product',
          actionLabel: 'Go Back',
          onAction: () => context.pop(),
        ),
      ),
      data: (products) {
        final product = products.where((p) => p.id == widget.productId).firstOrNull;
        if (product == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(title: const Text('Not Found')),
            body: EmptyState(
              icon: Icons.help_outline,
              title: 'Product not found',
              subtitle: 'It may have been removed',
              actionLabel: 'Go Back',
              onAction: () => context.pop(),
            ),
          );
        }

        final related = products
            .where((p) =>
                p.category == product.category && p.id != product.id)
            .take(8)
            .toList();

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(product.name,
                style: const TextStyle(fontSize: 16)),
            actions: [
              IconButton(
                icon: const Icon(Icons.view_in_ar,
                    color: AppColors.textOnDark),
                tooltip: 'View in AR',
                onPressed: () => context.push(
                  '/ar-viewer',
                  extra: ArFurnitureLibrary.fromCategory(
                      product.category),
                ),
              ),
              IconButton(
                icon: Icon(
                  isWishlisted
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: isWishlisted
                      ? AppColors.error
                      : AppColors.textOnDark,
                ),
                onPressed: () {
                  ref.read(wishlistProvider.notifier).toggle(product.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isWishlisted
                          ? 'Removed from wishlist'
                          : 'Added to wishlist'),
                      backgroundColor: AppColors.accent,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined,
                    color: AppColors.textOnDark),
                onPressed: () => context.push('/marketplace/cart'),
              ),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              // ── Product Image ──
              SliverToBoxAdapter(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.asset(
                    product.image,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.divider,
                      child: const Icon(Icons.image,
                          size: 48, color: AppColors.textHint),
                    ),
                  ),
                ),
              ),

              // ── Product Info ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Eco + Category badges
                      Row(
                        children: [
                          if (product.isEcoFriendly)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: AppColors.success
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.eco,
                                      size: 12,
                                      color: AppColors.success),
                                  SizedBox(width: 4),
                                  Text('Eco-Friendly',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.success)),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.accent
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(product.category,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.accent)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(product.designStyle,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Name
                      Text(product.name,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 6),

                      // Rating
                      RatingStars(
                          rating: product.rating,
                          count: product.ratingCount,
                          size: 16),
                      const SizedBox(height: 12),

                      // Price
                      Row(
                        children: [
                          Text(Formatters.myr(product.price),
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accent)),
                          if (product.originalPrice != null) ...[
                            const SizedBox(width: 8),
                            Text(
                                Formatters.myr(
                                    product.originalPrice!),
                                style: const TextStyle(
                                    fontSize: 16,
                                    decoration:
                                        TextDecoration.lineThrough,
                                    color: AppColors.textHint)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.error
                                    .withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              child: Text(
                                  '-${product.discountPercent}%',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.error)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Stock
                      Row(
                        children: [
                          Icon(
                            product.isOutOfStock
                                ? Icons.cancel
                                : product.isLowStock
                                    ? Icons.warning_amber
                                    : Icons.check_circle,
                            size: 16,
                            color: product.isOutOfStock
                                ? AppColors.error
                                : product.isLowStock
                                    ? AppColors.warning
                                    : AppColors.success,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            product.isOutOfStock
                                ? 'Out of Stock'
                                : product.isLowStock
                                    ? 'Only ${product.stock} left in stock'
                                    : 'In Stock (${product.stock} available)',
                            style: TextStyle(
                                fontSize: 13,
                                color: product.isOutOfStock
                                    ? AppColors.error
                                    : product.isLowStock
                                        ? AppColors.warning
                                        : AppColors
                                            .textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Quantity selector
                      Row(
                        children: [
                          const Text('Quantity',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          const Spacer(),
                          _QtyButton(
                            icon: Icons.remove,
                            onTap: _qty > 1
                                ? () => setState(() => _qty--)
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            child: Text('$_qty',
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600)),
                          ),
                          _QtyButton(
                            icon: Icons.add,
                            onTap: _qty < product.stock
                                ? () => setState(() => _qty++)
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Description
                      const SectionHeader(title: 'About this item'),
                      Text(product.description,
                          style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              height: 1.5)),

                      // Supplier info
                      const SizedBox(height: 20),
                      const SectionHeader(title: 'Supplier'),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            _InfoRow(Icons.business,
                                product.supplier.name),
                            _InfoRow(Icons.phone,
                                product.supplier.phone),
                            _InfoRow(Icons.email,
                                product.supplier.email),
                            _InfoRow(Icons.location_on,
                                product.supplier.address),
                            if (!product.supplier.isVerified) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.warning
                                      .withValues(alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: const Text(
                                    'Unverified Supplier',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.warning)),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Related products
                      if (related.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const SectionHeader(title: 'Related Products'),
                        SizedBox(
                          height: 220,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: related.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (_, i) => SizedBox(
                              width: 160,
                              child: ProductCard(
                                product: related[i],
                                compact: true,
                                isWishlisted: ref
                                    .watch(wishlistProvider)
                                    .contains(related[i].id),
                                onTap: () =>
                                    context.pushReplacement(
                                        '/marketplace/product/${related[i].id}'),
                                onAddToCart: () {
                                  ref
                                      .read(cartProvider.notifier)
                                      .addItem(related[i]);
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${related[i].name} added to cart'),
                                      backgroundColor:
                                          AppColors.success,
                                      behavior:
                                          SnackBarBehavior
                                              .floating,
                                    ),
                                  );
                                },
                                onToggleWishlist: () => ref
                                    .read(wishlistProvider
                                        .notifier)
                                    .toggle(related[i].id),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // ── Bottom action bar ──
          bottomNavigationBar: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: product.isOutOfStock
                          ? null
                          : () {
                              ref
                                  .read(cartProvider.notifier)
                                  .addItem(product, qty: _qty);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${product.name} × $_qty added to cart'),
                                  backgroundColor:
                                      AppColors.success,
                                  behavior:
                                      SnackBarBehavior.floating,
                                ),
                              );
                            },
                      icon: const Icon(Icons.add_shopping_cart,
                          size: 20),
                      label: const Text('Add to Cart'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: product.isOutOfStock
                          ? null
                          : () {
                              ref
                                  .read(cartProvider.notifier)
                                  .addItem(product, qty: _qty);
                              context.push('/marketplace/cart');
                            },
                      icon: const Icon(Icons.bolt, size: 20),
                      label: const Text('Buy Now'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              size: 18,
              color: onTap != null
                  ? AppColors.textPrimary
                  : AppColors.textHint),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon,
              size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
