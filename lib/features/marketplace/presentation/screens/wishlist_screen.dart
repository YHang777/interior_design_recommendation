import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/product.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/product_image.dart';
import '../../../../shared/widgets/rating_stars.dart';
import '../providers/marketplace_providers.dart';

/// Wishlist — favorite products in list rows with move-to-cart.
///
/// Sources from the same real-time product stream as the marketplace, so a
/// product a seller deletes disappears here too; dangling ids (no longer in
/// the stream) are pruned from the wishlist automatically.
class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  void _moveToCart(
      WidgetRef ref, BuildContext context, Product product) {
    ref.read(cartProvider.notifier).addItem(product);
    ref.read(wishlistProvider.notifier).remove(product.id);
    showAddedToCartSnack(
      context,
      '${product.name} moved to cart',
      onViewCart: () => context.pushNamed(RouteNames.homeownerCart),
    );
  }

  void _addAllToCart(
      WidgetRef ref, BuildContext context, List<Product> items) {
    final addable = items.where((p) => !p.isOutOfStock).toList();
    final skipped = items.length - addable.length;

    for (final product in addable) {
      ref.read(cartProvider.notifier).addItem(product);
    }
    // Drop everything that went into the cart; out-of-stock favorites stay.
    ref
        .read(wishlistProvider.notifier)
        .removeAll(addable.map((p) => p.id).toList());

    if (addable.isEmpty) return; // guarded by disabled button; no-op safety.
    final message = skipped == 0
        ? '${addable.length} item${addable.length == 1 ? '' : 's'} added to cart'
        : '${addable.length} item${addable.length == 1 ? '' : 's'} added to cart · '
            '$skipped skipped — out of stock';
    showAddedToCartSnack(
      context,
      message,
      onViewCart: () => context.pushNamed(RouteNames.homeownerCart),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final wishlist = ref.watch(wishlistProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('Wishlist (${wishlist.length})'),
        centerTitle: false,
      ),
      body: productsAsync.when(
        loading: () => ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: 5,
          itemBuilder: (_, __) => _RowSkeleton(),
        ),
        error: (_, __) => EmptyState(
          icon: Icons.error_outline,
          title: "Couldn't load your wishlist",
          subtitle: 'Check your connection and try again',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(marketplaceProductsProvider),
        ),
        data: (products) {
          final byId = {for (final p in products) p.id: p};

          // Prune ids that no longer exist in the catalogue (fire-and-forget).
          final missing =
              wishlist.where((id) => !byId.containsKey(id)).toList();
          if (missing.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(wishlistProvider.notifier).removeAll(missing);
            });
          }

          final items = [
            for (final id in wishlist)
              if (byId[id] != null) byId[id]!,
          ];

          if (items.isEmpty) {
            // Wishlist ids hydrate from Firestore asynchronously — wait a
            // beat before declaring the screen empty to avoid a flash.
            return const _DeferredEmpty();
          }

          final addableCount = items.where((p) => !p.isOutOfStock).length;
          final skippedCount = items.length - addableCount;

          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final product = items[index];
                    return _WishlistRow(
                      product: product,
                      onTap: () => context.pushNamed(
                        RouteNames.homeownerProductDetail,
                        pathParameters: {'id': product.id},
                      ),
                      onMoveToCart: !product.isOutOfStock
                          ? () => _moveToCart(ref, context, product)
                          : null,
                      onRemove: () {
                        ref
                            .read(wishlistProvider.notifier)
                            .remove(product.id);
                        showAppSnackbar(
                          context,
                          'Removed from wishlist',
                          color: AppColors.textSecondary,
                        );
                      },
                    );
                  },
                ),
              ),
              // Pinned "add all" bar
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (skippedCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '$skippedCount out of stock — they\'ll stay in '
                            'your wishlist',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: addableCount == 0
                              ? null
                              : () =>
                                  _addAllToCart(ref, context, items),
                          icon: const Icon(Icons.shopping_cart_outlined,
                              size: 20),
                          label: Text(addableCount == 0
                              ? 'Nothing in stock'
                              : addableCount == items.length
                                  ? 'Add all to cart ($addableCount)'
                                  : 'Add in-stock to cart ($addableCount)'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Waits a short moment for the wishlist ids to hydrate from Firestore,
/// then shows the real empty state. Replaced instantly if items stream in.
class _DeferredEmpty extends StatefulWidget {
  const _DeferredEmpty();

  @override
  State<_DeferredEmpty> createState() => _DeferredEmptyState();
}

class _DeferredEmptyState extends State<_DeferredEmpty> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.expand();
    return EmptyState(
      icon: Icons.favorite_border,
      title: 'Your wishlist is empty',
      subtitle: 'Tap the heart on any product you love to save it here',
      actionLabel: 'Browse the store',
      onAction: () => context.goNamed(RouteNames.homeownerMarketplace),
    );
  }
}

/// One wishlist row: image, name, rating, price + move-to-cart / remove.
class _WishlistRow extends StatelessWidget {
  const _WishlistRow({
    required this.product,
    required this.onTap,
    required this.onMoveToCart,
    required this.onRemove,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onMoveToCart;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image (no hero — this route lives on the root navigator
              // while the grid lives in the shell; cross-navigator flights
              // don't animate, so a plain image keeps things predictable).
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ProductImage(
                  product: product,
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  errorIconSize: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed: onRemove,
                          tooltip: 'Remove from wishlist',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close,
                              size: 18, color: AppColors.textHint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (product.ratingCount > 0)
                      RatingStars(rating: product.rating, size: 11)
                    else
                      const Text('New',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          Formatters.myr(product.price),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accent,
                          ),
                        ),
                        if (product.originalPrice != null) ...[
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              Formatters.myr(product.originalPrice!),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                decoration: TextDecoration.lineThrough,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (product.isLowStock)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Only ${product.stock} left',
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.warning)),
                      ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 30,
                      child: OutlinedButton.icon(
                        onPressed: onMoveToCart,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10),
                          textStyle: const TextStyle(fontSize: 11.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.add_shopping_cart, size: 14),
                        label: Text(product.isOutOfStock
                            ? 'Out of stock'
                            : 'Move to cart'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grey placeholder row shown while the stream first loads.
class _RowSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    width: 150,
                    height: 11,
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                Container(
                    width: 90,
                    height: 9,
                    decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                Container(
                    width: 60,
                    height: 13,
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 10),
                Container(
                    width: 120,
                    height: 26,
                    decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
