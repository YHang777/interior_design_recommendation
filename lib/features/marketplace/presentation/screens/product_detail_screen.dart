import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/product.dart';
import '../../../../models/review.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/product_card.dart';
import '../../../../shared/widgets/product_image.dart';
import '../../../../shared/widgets/quantity_stepper.dart';
import '../../../../shared/widgets/rating_stars.dart';
import '../../../../shared/widgets/section_header.dart';

import '../providers/marketplace_providers.dart';

/// Full-screen product detail page: hero gallery with animated dots, real
/// rating/stock state, quantity stepper, seller card with contact actions,
/// live reviews and same-category related products.
class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  final PageController _pageCtrl = PageController();
  int _page = 0;
  int _qty = 1;
  bool _descExpanded = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _launchExternal(String url, String unsupportedMessage) async {
    final uri = Uri.parse(url);
    final can = await canLaunchUrl(uri);
    if (!can) {
      if (mounted) showAppSnackbar(context, unsupportedMessage);
      return;
    }
    final ok = await launchUrl(uri);
    if (!ok && mounted) showAppSnackbar(context, unsupportedMessage);
  }

  /// Live-stock-capped quantity: if stock dropped while the screen was open
  /// the stepper and snackbar copy never overstate what was actually added.
  int _clampedQty(Product product) =>
      product.stock > 0 ? _qty.clamp(1, product.stock) : 1;

  void _addToCart(Product product) {
    final qty = _clampedQty(product);
    ref.read(cartProvider.notifier).addItem(product, qty: qty);
    final message = qty > 1
        ? '${product.name} × $qty added to cart'
        : '${product.name} added to cart';
    showAddedToCartSnack(
      context,
      message,
      onViewCart: () => context.pushNamed(RouteNames.homeownerCart),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final isWishlisted =
        ref.watch(wishlistProvider).contains(widget.productId);

    return productsAsync.when(
      loading: () => const _DetailSkeleton(),
      error: (_, __) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: EmptyState(
            icon: Icons.error_outline,
            title: "Couldn't load product",
            subtitle: 'Check your connection and try again',
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(marketplaceProductsProvider),
          ),
        ),
      ),
      data: (products) {
        final product = products
            .where((p) => p.id == widget.productId)
            .firstOrNull;
        if (product == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: EmptyState(
                icon: Icons.help_outline,
                title: 'Product not found',
                subtitle: 'It may have been removed or is no longer on sale',
                actionLabel: 'Go Back',
                onAction: () => context.pop(),
              ),
            ),
          );
        }

        return _buildDetail(product, isWishlisted);
      },
    );
  }

  Widget _buildDetail(Product product, bool isWishlisted) {
    final images = product.resolvedImages;
    final buyable = product.isActive && !product.isOutOfStock;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── Gallery ──
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 4 / 3,
                      child: PageView.builder(
                        controller: _pageCtrl,
                        itemCount: images.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (_, index) {
                          // Hero lives on the current page only so it pairs
                          // with the grid card's `product-{id}` tag.
                          final tag = index == _page
                              ? 'product-${product.id}'
                              : 'product-${product.id}-g$index';
                          return Hero(
                            tag: tag,
                            child: ProductImage(
                              imageUrl: images[index],
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorIconSize: 56,
                            ),
                          );
                        },
                      ),
                    ),
                    // Animated dot indicator
                    if (images.length > 1)
                      Positioned(
                        bottom: 14,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < images.length; i++)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOut,
                                    width: i == _page ? 20 : 7,
                                    height: 7,
                                    margin:
                                        const EdgeInsets.symmetric(horizontal: 2),
                                    decoration: BoxDecoration(
                                      color: i == _page
                                          ? Colors.white
                                          : Colors.white54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Info sections ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBadgeRow(product),
                      const SizedBox(height: 12),
                      Text(product.name,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 6),
                      _buildRatingLine(product),
                      const SizedBox(height: 12),
                      _buildPriceRow(product),
                      const SizedBox(height: 8),
                      _buildStockLine(product),
                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 10),
                      _buildQuantityRow(product),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),

              // Description
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'About this item'),
                      Text(
                        product.description,
                        maxLines: _descExpanded ? null : 5,
                        overflow:
                            _descExpanded ? null : TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            height: 1.5),
                      ),
                      if (product.description.length > 160)
                        GestureDetector(
                          onTap: () =>
                              setState(() => _descExpanded = !_descExpanded),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              _descExpanded ? 'Read less' : 'Read more',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accent),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Supplier card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Seller'),
                      _buildSellerCard(product),
                    ],
                  ),
                ),
              ),

              // Reviews
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _ReviewsSection(productId: product.id),
                ),
              ),

              // Related products
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Related Products'),
                      _buildRelatedRail(product),
                    ],
                  ),
                ),
              ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 28)),
            ],
          ),

          // ── Floating controls ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _FloatButton(
                    icon: Icons.arrow_back,
                    iconColor: Colors.white,
                    background: Colors.black.withValues(alpha: 0.35),
                    tooltip: 'Back',
                    onTap: () => context.pop(),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FloatButton(
                        icon: Icons.view_in_ar,
                        iconColor: Colors.white,
                        background: Colors.black.withValues(alpha: 0.35),
                        tooltip: 'View in AR',
                        onTap: () => context.pushNamed(
                          RouteNames.arViewer,
                          extra: product,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _FloatButton(
                        icon: isWishlisted
                            ? Icons.favorite
                            : Icons.favorite_border,
                        iconColor: isWishlisted
                            ? AppColors.error
                            : Colors.white,
                        background: isWishlisted
                            ? Colors.white
                            : Colors.black.withValues(alpha: 0.35),
                        tooltip:
                            isWishlisted ? 'Remove from wishlist' : 'Wishlist',
                        onTap: () {
                          ref
                              .read(wishlistProvider.notifier)
                              .toggle(product.id);
                          showAppSnackbar(
                            context,
                            ref
                                    .read(wishlistProvider)
                                    .contains(product.id)
                                ? 'Added to wishlist'
                                : 'Removed from wishlist',
                            color: AppColors.accent,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // ── Bottom action bar ──
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: buyable
                        ? () => _addToCart(product)
                        : null,
                    icon: const Icon(Icons.add_shopping_cart, size: 20),
                    label: const Text('Add to Cart'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    // Buy Now is a SINGLE-ITEM checkout: the cart is not
                    // touched — checkout receives the product + quantity as
                    // the route extra instead.
                    onPressed: buyable
                        ? () => context.pushNamed(
                              RouteNames.homeownerCheckout,
                              extra: BuyNowRequest(
                                product: product,
                                quantity: _clampedQty(product),
                              ),
                            )
                        : null,
                    icon: const Icon(Icons.bolt, size: 20),
                    label: Text(product.isOutOfStock
                        ? 'Out of Stock'
                        : 'Buy Now'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Info blocks ─────────────────────────────────────────────────────────

  Widget _buildBadgeRow(Product product) {
    return Row(
      children: [
        if (product.isEcoFriendly) ...[
          _ChipBadge(
              text: 'Eco-Friendly',
              background: AppColors.success.withValues(alpha: 0.1),
              color: AppColors.success,
              icon: Icons.eco),
          const SizedBox(width: 8),
        ],
        _ChipBadge(
            text: product.category,
            background: AppColors.accent.withValues(alpha: 0.1),
            color: AppColors.accent),
        const SizedBox(width: 8),
        _ChipBadge(
            text: product.designStyle,
            background: AppColors.primary.withValues(alpha: 0.08),
            color: AppColors.primary),
        if (product.ratingCount == 0) ...[
          const SizedBox(width: 8),
          _ChipBadge(
              text: 'New',
              background: AppColors.secondaryAccent.withValues(alpha: 0.1),
              color: AppColors.secondaryAccent),
        ],
      ],
    );
  }

  Widget _buildRatingLine(Product product) {
    if (product.ratingCount <= 0) return const SizedBox.shrink();
    return Row(
      children: [
        RatingStars(rating: product.rating, size: 16),
        const SizedBox(width: 8),
        Text('${product.rating.toStringAsFixed(1)} (${product.ratingCount})',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
    );
  }

  Widget _buildPriceRow(Product product) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(Formatters.myr(product.price),
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.accent)),
        if (product.originalPrice != null) ...[
          const SizedBox(width: 8),
          Text(Formatters.myr(product.originalPrice!),
              style: const TextStyle(
                  fontSize: 16,
                  decoration: TextDecoration.lineThrough,
                  color: AppColors.textHint)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('-${product.discountPercent}%',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error)),
          ),
        ],
      ],
    );
  }

  Widget _buildStockLine(Product product) {
    final (icon, color, label) = product.isOutOfStock
        ? (Icons.cancel, AppColors.error, 'Out of stock')
        : product.isLowStock
            ? (Icons.warning_amber_rounded, AppColors.warning,
                'Only ${product.stock} left — order soon')
            : (Icons.check_circle, AppColors.success, 'In stock');
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color)),
      ],
    );
  }

  Widget _buildQuantityRow(Product product) {
    if (product.isOutOfStock) return const SizedBox.shrink();
    return Row(
      children: [
        const Text('Quantity',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const Spacer(),
        QuantityStepper(
          value: _clampedQty(product),
          min: 1,
          max: product.stock,
          label: 'of ${product.stock}',
          onChanged: (v) => setState(() => _qty = v),
          onBlockedTap: () => showAppSnackbar(
            context,
            _qty >= product.stock
                ? 'Only ${product.stock} available — that\'s the maximum'
                : 'Minimum quantity is 1',
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildSellerCard(Product product) {
    final supplier = product.supplier;
    final initial = supplier.name.trim().isNotEmpty
        ? supplier.name.trim()[0].toUpperCase()
        : '?';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                child: Text(initial,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(supplier.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        ),
                        if (supplier.isVerified) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.verified,
                              size: 16, color: AppColors.accent),
                        ],
                      ],
                    ),
                    if (supplier.address.isNotEmpty)
                      Text(supplier.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textHint)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: supplier.phone.isNotEmpty
                      ? () => _launchExternal(
                          'tel:${supplier.phone.replaceAll(RegExp(r'[^\d+]'), '')}',
                          'Phone calls aren\'t supported on this device')
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: const TextStyle(fontSize: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.phone, size: 16),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: supplier.email.isNotEmpty
                      ? () => _launchExternal(
                          'mailto:${supplier.email}',
                          'Email isn\'t supported on this device')
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: const TextStyle(fontSize: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.email_outlined, size: 16),
                  label: const Text('Email'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedRail(Product product) {
    final products =
        ref.watch(marketplaceProductsProvider).valueOrNull ?? const [];
    final related = products
        .where((p) =>
            p.isActive &&
            p.id != product.id &&
            p.category.toLowerCase() == product.category.toLowerCase())
        .take(8)
        .toList();

    if (related.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: related.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, index) {
          final item = related[index];
          return SizedBox(
            width: 150,
            child: ProductCard(
              product: item,
              compact: true,
              isWishlisted:
                  ref.watch(wishlistProvider).contains(item.id),
              onTap: () => context.pushNamed(
                RouteNames.homeownerProductDetail,
                pathParameters: {'id': item.id},
              ),
              onAddToCart: () {
                ref.read(cartProvider.notifier).addItem(item);
                showAddedToCartSnack(
                  context,
                  '${item.name} added to cart',
                  onViewCart: () => context.pushNamed(RouteNames.homeownerCart),
                );
              },
              onToggleWishlist: () {
                final was = ref
                    .read(wishlistProvider)
                    .contains(item.id);
                ref.read(wishlistProvider.notifier).toggle(item.id);
                showAppSnackbar(
                  context,
                  was ? 'Removed from wishlist' : 'Added to wishlist',
                  color: AppColors.accent,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ── Small building blocks ────────────────────────────────────────────────────

/// Round translucent overlay button used for back / wishlist / AR actions.
class _FloatButton extends StatelessWidget {
  const _FloatButton({
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color iconColor;
  final Color background;
  final VoidCallback onTap;
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, size: 21, color: iconColor),
          ),
        ),
      ),
    );
  }
}

class _ChipBadge extends StatelessWidget {
  const _ChipBadge({
    required this.text,
    required this.background,
    required this.color,
    this.icon,
  });

  final String text;
  final Color background;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

// ── Reviews section (live) ───────────────────────────────────────────────────

class _ReviewsSection extends ConsumerWidget {
  const _ReviewsSection({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(productReviewsProvider(productId));

    return reviewsAsync.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Reviews'),
          for (var i = 0; i < 2; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              width: 110, height: 10,
                              decoration: BoxDecoration(
                                  color: AppColors.border,
                                  borderRadius: BorderRadius.circular(4))),
                          const SizedBox(height: 6),
                          Container(
                              width: 60, height: 8,
                              decoration: BoxDecoration(
                                  color: AppColors.divider,
                                  borderRadius: BorderRadius.circular(4))),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                      width: double.infinity, height: 10,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(4))),
                ],
              ),
            ),
        ],
      ),
      error: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Reviews'),
          Row(
            children: [
              const Expanded(
                child: Text("Couldn't load reviews",
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: () =>
                    ref.invalidate(productReviewsProvider(productId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
      data: (reviews) {
        final count = reviews.length;
        final average = count > 0
            ? (reviews.fold<int>(0, (sum, r) => sum + r.rating) /
                    count)
                .toStringAsFixed(1)
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Reviews${count > 0 ? ' ($count)' : ''}',
              trailingLabel: average == null ? null : '$average avg',
            ),
            if (count == 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                    Icon(Icons.rate_review_outlined,
                        size: 28,
                        color: AppColors.textHint.withValues(alpha: 0.7)),
                    const SizedBox(height: 8),
                    const Text(
                      'No reviews yet — be the first after your order arrives.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.4),
                    ),
                  ],
                ),
              )
            else
              for (final review in reviews)
                _ReviewTile(review: review),
          ],
        );
      },
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  String get _initial => review.userName.trim().isNotEmpty
      ? review.userName.trim()[0].toUpperCase()
      : '?';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                child: Text(_initial,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    Text(Formatters.shortDate(review.createdAt),
                        style: const TextStyle(
                            fontSize: 10.5, color: AppColors.textHint)),
                  ],
                ),
              ),
              RatingStars(rating: review.rating.toDouble(), size: 13),
            ],
          ),
          const SizedBox(height: 8),
          if (review.comment.trim().isNotEmpty)
            _ExpandableComment(text: review.comment),
        ],
      ),
    );
  }
}

/// Comment clamped to 3 lines with a "more/less" toggle when it overflows.
class _ExpandableComment extends StatefulWidget {
  const _ExpandableComment({required this.text});

  final String text;

  @override
  State<_ExpandableComment> createState() => _ExpandableCommentState();
}

class _ExpandableCommentState extends State<_ExpandableComment> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = const TextStyle(
          fontSize: 12.5,
          color: AppColors.textSecondary,
          height: 1.45,
        );
        // Cheap overflow probe (3 lines).
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 3,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: style,
            ),
            if (overflows)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    _expanded ? 'Show less' : 'Read more',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Loading skeleton ─────────────────────────────────────────────────────────

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Container(
            height: MediaQuery.of(context).size.width * 3 / 4,
            color: AppColors.surface,
            alignment: Alignment.center,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(width: 200, height: 18),
                const SizedBox(height: 12),
                _bar(width: 120, height: 12),
                const SizedBox(height: 12),
                _bar(width: 90, height: 20),
                const SizedBox(height: 16),
                _bar(width: double.infinity, height: 12),
                const SizedBox(height: 8),
                _bar(width: double.infinity, height: 12),
                const SizedBox(height: 8),
                _bar(width: 180, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
