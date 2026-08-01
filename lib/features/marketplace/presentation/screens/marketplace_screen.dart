import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../shared/widgets/search_bar.dart' as sw;
import '../../../../../shared/widgets/filter_chip_bar.dart';
import '../../../../../shared/widgets/product_card.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/skeleton_loader.dart';

import '../providers/marketplace_providers.dart';

/// Marketplace — browse, search, filter, and shop products.
class MarketplaceScreen extends ConsumerWidget {
  const MarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final filtered = ref.watch(filteredProductsProvider);
    final cartCount = ref.watch(cartCountProvider);
    final wishlistCount = ref.watch(wishlistCountProvider);
    final ordersAsync = ref.watch(ordersProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final stylesAsync = ref.watch(stylesProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final selectedCategory = ref.watch(selectedCategoryFilterProvider);
    final selectedStyle = ref.watch(selectedStyleFilterProvider);
    final sortOption = ref.watch(sortOptionProvider);
    final ecoOnly = ref.watch(ecoOnlyProvider);

    final orderCount = ordersAsync.whenOrNull(data: (o) => o.length) ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Marketplace',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textOnDark)),
            Text('Furniture & materials for your space',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textOnDark.withValues(alpha: 0.7))),
          ],
        ),
        actions: [
          // Wishlist
          IconButton(
            icon: Badge(
              isLabelVisible: wishlistCount > 0,
              label: Text('$wishlistCount',
                  style: const TextStyle(fontSize: 10, color: Colors.white)),
              child: const Icon(Icons.favorite_outline,
                  color: AppColors.textOnDark),
            ),
            onPressed: () => context.push('/marketplace/wishlist'),
          ),
          // Order history
          IconButton(
            icon: Badge(
              isLabelVisible: orderCount > 0,
              label: Text('$orderCount',
                  style: const TextStyle(fontSize: 10, color: Colors.white)),
              child: const Icon(Icons.receipt_long_outlined,
                  color: AppColors.textOnDark),
            ),
            onPressed: () => context.push('/marketplace/orders'),
          ),
          // Cart
          IconButton(
            icon: Badge(
              isLabelVisible: cartCount > 0,
              label: Text(
                  cartCount > 99 ? '99+' : '$cartCount',
                  style: const TextStyle(fontSize: 10, color: Colors.white)),
              child: const Icon(Icons.shopping_cart_outlined,
                  color: AppColors.textOnDark),
            ),
            onPressed: () => context.push('/marketplace/cart'),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // ── Search + Filters ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search bar
                  sw.SearchBar(
                    hintText: 'Search sofas, lamps, paint…',
                    onChanged: (q) =>
                        ref.read(searchQueryProvider.notifier).state = q,
                  ),
                  const SizedBox(height: 12),

                  // Category filter (from API)
                  categoriesAsync.when(
                    data: (cats) => FilterChipBar<String>(
                      options: ['All', ...cats.map((c) => c.name)],
                      selected: selectedCategory,
                      onSelected: (v) => ref
                          .read(selectedCategoryFilterProvider.notifier)
                          .state = v,
                    ),
                    loading: () => const SizedBox(height: 40),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 8),

                  // Style filter (from API)
                  stylesAsync.when(
                    data: (styles) => FilterChipBar<String>(
                      options: ['All', ...styles],
                      selected: selectedStyle,
                      onSelected: (v) => ref
                          .read(selectedStyleFilterProvider.notifier)
                          .state = v,
                    ),
                    loading: () => const SizedBox(height: 40),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 8),

                  // Result count + sort + eco
                  Row(
                    children: [
                      Text(
                        '${filtered.length} item${filtered.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      // Eco toggle
                      GestureDetector(
                        onTap: () => ref
                            .read(ecoOnlyProvider.notifier)
                            .state = !ecoOnly,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: ecoOnly
                                ? AppColors.success.withValues(alpha: 0.12)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: ecoOnly
                                  ? AppColors.success
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.eco,
                                  size: 14,
                                  color: ecoOnly
                                      ? AppColors.success
                                      : AppColors.textHint),
                              const SizedBox(width: 4),
                              Text('Eco',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: ecoOnly
                                          ? AppColors.success
                                          : AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Sort
                      PopupMenuButton<SortOption>(
                        initialValue: sortOption,
                        onSelected: (v) =>
                            ref.read(sortOptionProvider.notifier).state = v,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border:
                                Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.swap_vert,
                                  size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                _sortLabel(sortOption),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        itemBuilder: (_) => SortOption.values
                            .map((o) => PopupMenuItem(
                                  value: o,
                                  child: Text(_sortLabel(o)),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ── Product Grid ──
          productsAsync.when(
            loading: () => const SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                  child: SkeletonLoader(count: 6)),
            ),
            error: (e, _) => SliverFillRemaining(
              child: EmptyState(
                icon: Icons.error_outline,
                title: "Couldn't load products",
                subtitle: 'Check your connection and try again',
                actionLabel: 'Retry',
                onAction: () =>
                    ref.invalidate(marketplaceProductsProvider),
              ),
            ),
            data: (_) {
              if (filtered.isEmpty) {
                final hasActiveFilters =
                    searchQuery.isNotEmpty || selectedCategory != 'All' ||
                        selectedStyle != 'All' || ecoOnly;
                return SliverFillRemaining(
                  child: EmptyState(
                    icon: hasActiveFilters
                        ? Icons.search_off
                        : Icons.store,
                    title: hasActiveFilters
                        ? 'No products match your filters'
                        : 'No products available',
                    subtitle: hasActiveFilters
                        ? 'Try adjusting your search or filters'
                        : 'Check back later for new arrivals',
                    actionLabel:
                        hasActiveFilters ? 'Clear Filters' : null,
                    onAction: hasActiveFilters
                        ? () {
                            ref
                                .read(searchQueryProvider.notifier)
                                .state = '';
                            ref
                                .read(selectedCategoryFilterProvider
                                    .notifier)
                                .state = 'All';
                            ref
                                .read(selectedStyleFilterProvider
                                    .notifier)
                                .state = 'All';
                            ref
                                .read(ecoOnlyProvider.notifier)
                                .state = false;
                          }
                        : null,
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final crossAxisCount = width > 600
                        ? 4
                        : width > 400
                            ? 3
                            : 2;
                    return SliverGrid(
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 0.68,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final product = filtered[index];
                          final isWishlisted = ref
                              .watch(wishlistProvider)
                              .contains(product.id);
                          return ProductCard(
                            product: product,
                            isWishlisted: isWishlisted,
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
                                  duration:
                                      const Duration(seconds: 1),
                                ),
                              );
                            },
                            onToggleWishlist: () {
                              ref
                                  .read(wishlistProvider.notifier)
                                  .toggle(product.id);
                              final nowWishlisted = ref
                                  .read(wishlistProvider)
                                  .contains(product.id);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(nowWishlisted
                                      ? 'Added to wishlist'
                                      : 'Removed from wishlist'),
                                  backgroundColor: AppColors.accent,
                                  behavior: SnackBarBehavior.floating,
                                  duration:
                                      const Duration(seconds: 1),
                                ),
                              );
                            },
                          );
                        },
                        childCount: filtered.length,
                      ),
                    );
                  },
                ),
              );
            },
          ),

          // Bottom padding
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}

String _sortLabel(SortOption option) => switch (option) {
      SortOption.relevance => 'Relevance',
      SortOption.priceLowToHigh => 'Price: Low → High',
      SortOption.priceHighToLow => 'Price: High → Low',
      SortOption.newest => 'Newest',
    };
