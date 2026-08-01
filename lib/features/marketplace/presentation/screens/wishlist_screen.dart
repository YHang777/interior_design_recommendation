import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../shared/widgets/product_card.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../providers/marketplace_providers.dart';

/// Wishlist screen — shows products the user has favorited.
class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final wishlist = ref.watch(wishlistProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Wishlist (${wishlist.length})'),
      ),
      body: productsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Failed to load products',
          actionLabel: 'Retry',
          onAction: () =>
              ref.invalidate(marketplaceProductsProvider),
        ),
        data: (products) {
          final wishlistProducts = products
              .where((p) => wishlist.contains(p.id))
              .toList();

          if (wishlistProducts.isEmpty) {
            return EmptyState(
              icon: Icons.favorite_border,
              title: 'No saved items yet',
              subtitle:
                  'Tap the heart icon on products you love',
              actionLabel: 'Discover Products',
              onAction: () => context.go('/marketplace'),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 600
                  ? 4
                  : constraints.maxWidth > 400
                      ? 3
                      : 2;
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate:
                    SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 0.68,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: wishlistProducts.length,
                itemBuilder: (context, index) {
                  final product = wishlistProducts[index];
                  return ProductCard(
                    product: product,
                    isWishlisted: true,
                    onTap: () => context.push(
                        '/marketplace/product/${product.id}'),
                    onAddToCart: () {
                      ref
                          .read(cartProvider.notifier)
                          .addItem(product);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(
                        SnackBar(
                          content: Text(
                              '${product.name} added to cart'),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    onToggleWishlist: () {
                      ref
                          .read(wishlistProvider.notifier)
                          .toggle(product.id);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(
                        const SnackBar(
                          content:
                              Text('Removed from wishlist'),
                          backgroundColor: AppColors.error,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
