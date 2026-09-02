import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/product.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/search_bar.dart' as sw;
import '../../../../shared/widgets/filter_chip_bar.dart';
import '../../../../shared/widgets/product_card.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/skeleton_loader.dart';

import '../providers/marketplace_providers.dart';

/// Marketplace — browse, search, sort/filter, and shop products.
///
/// Products stream live from Firestore (seller publishes → buyer sees it);
/// pull-to-refresh forces a re-read on top of the stream. Search remembers
/// recent terms on-device and offers live product-name suggestions.
class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool get _searchFocused => _searchFocus.hasFocus;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _searchFocus.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});
  void _onSearchFocusChanged() => setState(() {});

  // ── Helpers ────────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    ref.invalidate(marketplaceProductsProvider);
    try {
      await ref.read(marketplaceProductsProvider.future);
    } catch (_) {
      // Failures surface via the productsAsync error branch.
    }
  }

  void _applySearch(String query) {
    ref.read(searchQueryProvider.notifier).state = query;
  }

  void _recordSearch(String query) {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return;
    ref.read(recentSearchesProvider.notifier).record(cleaned);
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _applySearch('');
    setState(() {});
  }

  void _openProduct(Product product) {
    FocusManager.instance.primaryFocus?.unfocus();
    context.pushNamed(
      RouteNames.homeownerProductDetail,
      pathParameters: {'id': product.id},
    );
  }

  void _addToCart(Product product) {
    ref.read(cartProvider.notifier).addItem(product);
    showAddedToCartSnack(
      context,
      '${product.name} added to cart',
      onViewCart: () => context.pushNamed(RouteNames.homeownerCart),
    );
  }

  void _toggleWishlist(Product product) {
    final notifier = ref.read(wishlistProvider.notifier);
    final wasWishlisted = notifier.contains(product.id);
    notifier.toggle(product.id);
    showAppSnackbar(
      context,
      wasWishlisted ? 'Removed from wishlist' : 'Added to wishlist',
      color: AppColors.accent,
    );
  }

  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _SortSheet(),
    );
  }

  void _showFiltersSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _FiltersSheet(),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final filtered = ref.watch(filteredProductsProvider);
    final cartCount = ref.watch(cartCountProvider);
    final wishlistCount = ref.watch(wishlistCountProvider);
    final ordersAsync = ref.watch(customerOrdersProvider);
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
                    fontSize: 11,
                    color: AppColors.textOnDark.withValues(alpha: 0.7))),
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
            onPressed: () => context.pushNamed(RouteNames.homeownerWishlist),
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
            onPressed: () =>
                context.pushNamed(RouteNames.homeownerOrderHistory),
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
            onPressed: () => context.pushNamed(RouteNames.homeownerCart),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            // ── Search + filters header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchArea(),
                    const SizedBox(height: 10),
                    if (_chipRowEntries().isNotEmpty || _sortChipVisible())
                      _buildActiveChipRow(),
                    if (_chipRowEntries().isNotEmpty || _sortChipVisible())
                      const SizedBox(height: 8),
                    _buildToolbarRow(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── Product grid ──
            productsAsync.when(
              skipLoadingOnRefresh: true,
              loading: () => const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(child: SkeletonLoader(count: 6)),
              ),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.error_outline,
                  title: "Couldn't load products",
                  subtitle: 'Check your connection and try again',
                  actionLabel: 'Retry',
                  onAction: _refresh,
                ),
              ),
              data: (_) {
                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
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
                            return ProductCard(
                              product: product,
                              isWishlisted: ref
                                  .watch(wishlistProvider)
                                  .contains(product.id),
                              onTap: () => _openProduct(product),
                              onArPreview: () => context.pushNamed(
                                RouteNames.arViewer,
                                extra: product,
                              ),
                              onAddToCart: () => _addToCart(product),
                              onToggleWishlist: () =>
                                  _toggleWishlist(product),
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
      ),
    );
  }

  // ── Header building blocks ─────────────────────────────────────────────

  Widget _buildSearchArea() {
    final query = _searchCtrl.text.trim();
    final hasFocus = _searchFocused;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sw.SearchBar(
          hintText: 'Search sofas, lamps, paint…',
          debounceMs: 300,
          controller: _searchCtrl,
          focusNode: _searchFocus,
          onChanged: _applySearch,
          onSubmitted: (q) {
            _applySearch(q);
            _recordSearch(q);
          },
          onFocusChanged: (_) => setState(() {}),
        ),
        // Focus panels: recents when empty, live suggestions while typing.
        if (hasFocus && query.isEmpty)
          _buildRecentSearches(),
        if (hasFocus && query.isNotEmpty)
          _buildSuggestions(query),
        // Category chips stay available above the grid.
        _buildCategoryChips(),
      ],
    );
  }

  Widget _buildCategoryChips() {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selectedCategory = ref.watch(selectedCategoryFilterProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: categoriesAsync.when(
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
    );
  }

  Widget _buildRecentSearches() {
    final recents = ref.watch(recentSearchesProvider);
    if (recents.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Recent searches',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary.withValues(alpha: 0.9))),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  ref.read(recentSearchesProvider.notifier).clearAll();
                },
                child: Text('Clear all',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recents.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final term = recents[index];
                void removeTerm() {
                  ref
                      .read(recentSearchesProvider.notifier)
                      .remove(term);
                }

                // GestureDetector adds long-press-to-remove on top of the
                // chip's tap-to-apply and X-to-delete affordances.
                return GestureDetector(
                  onLongPress: removeTerm,
                  child: InputChip(
                    label: Text(term,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textPrimary)),
                    backgroundColor: AppColors.background,
                    selectedColor: AppColors.background,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    deleteIcon: const Icon(Icons.close,
                        size: 14, color: AppColors.textHint),
                    onPressed: () {
                      _searchCtrl.text = term;
                      _searchCtrl.selection =
                          TextSelection.collapsed(offset: term.length);
                      _applySearch(term);
                    },
                    onDeleted: removeTerm,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions(String query) {
    final products =
        ref.watch(marketplaceProductsProvider).valueOrNull ?? const [];
    final q = query.toLowerCase();
    final matches = products.where((p) {
      if (!p.isActive) return false;
      final name = p.name.toLowerCase();
      return name.contains(q);
    }).toList()
      ..sort((a, b) {
        final aStarts = a.name.toLowerCase().startsWith(q) ? 0 : 1;
        final bStarts = b.name.toLowerCase().startsWith(q) ? 0 : 1;
        if (aStarts != bStarts) return aStarts - bStarts;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final top = matches.take(6).toList();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.search_off,
                      size: 16, color: AppColors.textHint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('No products match "$query"',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textHint)),
                  ),
                ],
              ),
            )
          else
            for (final product in top) ...[
              InkWell(
                onTap: () {
                  _recordSearch(product.name);
                  _openProduct(product);
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.search,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary)),
                      ),
                      Text(product.category,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textHint)),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right,
                          size: 16, color: AppColors.textHint),
                    ],
                  ),
                ),
              ),
              if (product != top.last)
                const Divider(height: 1, indent: 40),
            ],
        ],
      ),
    );
  }

  Widget _buildToolbarRow() {
    final filtered = ref.watch(filteredProductsProvider);
    final ecoOnly = ref.watch(ecoOnlyProvider);
    final sortOption = ref.watch(sortOptionProvider);
    final sheetFilterCount =
        ref.watch(marketplaceFilterStateProvider).sheetCount;

    return Row(
      children: [
        Text(
          '${filtered.length} item${filtered.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const Spacer(),
        // Eco quick toggle
        GestureDetector(
          onTap: () => ref.read(ecoOnlyProvider.notifier).state = !ecoOnly,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: ecoOnly
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: ecoOnly ? AppColors.success : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.eco,
                    size: 14,
                    color: ecoOnly ? AppColors.success : AppColors.textHint),
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
        GestureDetector(
          onTap: _showSortSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_vert,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Sort · ${sortOption.label}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Filters
        GestureDetector(
          onTap: _showFiltersSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: sheetFilterCount > 0
                  ? AppColors.accent.withValues(alpha: 0.1)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: sheetFilterCount > 0
                    ? AppColors.accent
                    : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune,
                    size: 14,
                    color: sheetFilterCount > 0
                        ? AppColors.accent
                        : AppColors.textSecondary),
                const SizedBox(width: 4),
                Text('Filters',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: sheetFilterCount > 0
                            ? AppColors.accent
                            : AppColors.textSecondary)),
                if (sheetFilterCount > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$sheetFilterCount',
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveChipRow() {
    final sortOption = ref.watch(sortOptionProvider);

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _chipRowEntries().length + (_sortChipVisible() ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          if (_sortChipVisible() && index == _chipRowEntries().length) {
            return ActionChip(
              avatar: const Icon(Icons.swap_vert,
                  size: 13, color: AppColors.textSecondary),
              label: Text('Sort: ${sortOption.chipLabel}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textPrimary)),
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onPressed: _showSortSheet,
            );
          }
          final entry = _chipRowEntries()[index];
          return InputChip(
            label: Text(entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
            backgroundColor: AppColors.surface,
            side: BorderSide(
                color: entry.isAccent ? AppColors.accent : AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            deleteIcon: const Icon(Icons.close, size: 13),
            onDeleted: entry.onClear,
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasActiveFilters = ref.watch(activeFilterCountProvider) > 0;
    return EmptyState(
      icon: hasActiveFilters ? Icons.search_off : Icons.store,
      title: hasActiveFilters
          ? 'No products match your filters'
          : 'No products available',
      subtitle: hasActiveFilters
          ? 'Try adjusting your search or filters'
          : 'Check back later for new arrivals',
      actionLabel: hasActiveFilters ? 'Clear Filters' : null,
      onAction: hasActiveFilters
          ? () {
              FocusManager.instance.primaryFocus?.unfocus();
              _searchCtrl.clear();
              resetMarketplaceFilters(ref);
              setState(() {});
            }
          : null,
    );
  }

  // ── Filter bookkeeping ─────────────────────────────────────────────────

  bool _sortChipVisible() =>
      ref.read(sortOptionProvider) != SortOption.recommended;

  /// Removable filter chips (search term, category, style, price, stock,
  /// eco, verified-off) shown above the grid. WHICH chips appear is decided
  /// by the shared [MarketplaceFilterState] so this list can never disagree
  /// with the Filters badge or the "Clear filters" CTA; the provider reads
  /// below only supply labels for dims that state already flagged active.
  List<_RemovableChip> _chipRowEntries() {
    final state = ref.read(marketplaceFilterStateProvider);
    final entries = <_RemovableChip>[];

    if (state.searchActive) {
      final search = ref.read(searchQueryProvider).trim();
      entries.add(_RemovableChip(
          label: '"$search"', onClear: _clearSearch));
    }
    if (state.categoryActive) {
      final category = ref.read(selectedCategoryFilterProvider);
      entries.add(_RemovableChip(
          label: category,
          onClear: () =>
              ref.read(selectedCategoryFilterProvider.notifier).state = 'All'));
    }
    if (state.styleActive) {
      final style = ref.read(selectedStyleFilterProvider);
      entries.add(_RemovableChip(
          label: style,
          onClear: () =>
              ref.read(selectedStyleFilterProvider.notifier).state = 'All'));
    }
    if (state.priceActive) {
      final price = ref.read(priceRangeFilterProvider)!;
      entries.add(_RemovableChip(
        label: '${Formatters.myr(price.min)} – ${Formatters.myr(price.max)}',
        isAccent: true,
        onClear: () => ref.read(priceRangeFilterProvider.notifier).state = null,
      ));
    }
    if (state.stockActive) {
      entries.add(_RemovableChip(
          label: 'In stock',
          onClear: () => ref.read(inStockOnlyProvider.notifier).state = false));
    }
    if (state.ecoActive) {
      entries.add(_RemovableChip(
          label: 'Eco-friendly',
          isAccent: true,
          onClear: () => ref.read(ecoOnlyProvider.notifier).state = false));
    }
    if (state.verifiedOff) {
      entries.add(_RemovableChip(
          label: 'All sellers',
          onClear: () => ref.read(verifiedOnlyProvider.notifier).state = true));
    }
    return entries;
  }
}

class _RemovableChip {
  const _RemovableChip({required this.label, required this.onClear, this.isAccent = false});

  final String label;
  final VoidCallback onClear;
  final bool isAccent;
}

// ── Sort sheet ───────────────────────────────────────────────────────────────

class _SortSheet extends ConsumerWidget {
  const _SortSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(sortOptionProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Sort by',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
            for (final option in SortOption.values)
              InkWell(
                onTap: () {
                  ref.read(sortOptionProvider.notifier).state = option;
                  Navigator.pop(context);
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      Icon(
                        current == option
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 18,
                        color: current == option
                            ? AppColors.accent
                            : AppColors.textHint,
                      ),
                      const SizedBox(width: 12),
                      Text(option.label,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: current == option
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: current == option
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary)),
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

// ── Filters sheet ────────────────────────────────────────────────────────────

class _FiltersSheet extends ConsumerWidget {
  const _FiltersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveCount = ref.watch(filteredProductsProvider).length;
    // "Has anything deviated from default?" comes from the shared filter
    // state so the sheet's Clear-all and the toolbar badge always agree.
    final sheetDirty = ref.watch(marketplaceFilterStateProvider).sheetDirty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('Filters',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$liveCount item${liveCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ),
                    if (sheetDirty)
                      TextButton(
                        onPressed: () => resetMarketplaceFilters(
                          ref,
                          includeSearch: false,
                          includeSort: false,
                        ),
                        child: const Text('Clear all'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                // ── Category ──
                const _SheetLabel('Category'),
                ref.watch(categoriesProvider).when(
                      data: (cats) => _chipWrap(
                        context,
                        options: ['All', ...cats.map((c) => c.name)],
                        selected: ref.watch(selectedCategoryFilterProvider),
                        onSelected: (v) => ref
                            .read(selectedCategoryFilterProvider.notifier)
                            .state = v,
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),

                // ── Style ──
                const _SheetLabel('Style'),
                ref.watch(stylesProvider).when(
                      data: (styles) => _chipWrap(
                        context,
                        options: ['All', ...styles],
                        selected: ref.watch(selectedStyleFilterProvider),
                        onSelected: (v) => ref
                            .read(selectedStyleFilterProvider.notifier)
                            .state = v,
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),

                // ── Price range ──
                _buildPriceSection(ref),

                // ── Toggles ──
                _buildToggleRow(
                  ref,
                  icon: Icons.inventory_2_outlined,
                  title: 'In stock only',
                  value: ref.watch(inStockOnlyProvider),
                  onChanged: (v) =>
                      ref.read(inStockOnlyProvider.notifier).state = v,
                ),
                _buildToggleRow(
                  ref,
                  icon: Icons.eco,
                  title: 'Eco-friendly',
                  value: ref.watch(ecoOnlyProvider),
                  onChanged: (v) =>
                      ref.read(ecoOnlyProvider.notifier).state = v,
                ),
                _buildToggleRow(
                  ref,
                  icon: Icons.verified_outlined,
                  title: 'Verified sellers only',
                  subtitle: 'Trusted, vetted suppliers',
                  value: ref.watch(verifiedOnlyProvider),
                  onChanged: (v) =>
                      ref.read(verifiedOnlyProvider.notifier).state = v,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipWrap(
    BuildContext context, {
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(
              option,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: option == selected
                    ? Colors.white
                    : AppColors.textSecondary,
              ),
            ),
            selected: option == selected,
            onSelected: (_) => onSelected(option),
            selectedColor: AppColors.accent,
            backgroundColor: AppColors.background,
            side: BorderSide(
              color: option == selected ? AppColors.accent : AppColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }

  Widget _buildPriceSection(WidgetRef ref) {
    final bounds = ref.watch(productPriceBoundsProvider);
    final selected = ref.watch(priceRangeFilterProvider);

    if (bounds == null) return const SizedBox.shrink();

    // Apply the user's last band when it is still inside the current bounds.
    var start = (selected?.min ?? bounds.min)
        .clamp(bounds.min, bounds.max)
        .toDouble();
    var end = (selected?.max ?? bounds.max)
        .clamp(bounds.min, bounds.max)
        .toDouble();
    if (end < start) end = start;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SheetLabel('Price range'),
        if (bounds.max <= bounds.min)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('All items are ${Formatters.myr(bounds.min)}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textHint)),
          )
        else ...[
          RangeSlider(
            values: RangeValues(start, end),
            min: bounds.min.toDouble(),
            max: bounds.max.toDouble(),
            divisions: 100,
            labels: RangeLabels(
              Formatters.myr(start.round()),
              Formatters.myr(end.round()),
            ),
            activeColor: AppColors.accent,
            inactiveColor: AppColors.divider,
            onChanged: (values) {
              ref.read(priceRangeFilterProvider.notifier).state =
                  PriceFilter(
                min: values.start.round(),
                max: values.end.round(),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              '${Formatters.myr(start.round())} – ${Formatters.myr(end.round())}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildToggleRow(
    WidgetRef ref, {
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                if (subtitle != null)
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textHint)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Text(label,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary)),
    );
  }
}
