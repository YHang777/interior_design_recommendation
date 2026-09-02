import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/product.dart';
import '../../../../models/product_category.dart';
import '../../../../models/cart_item.dart';
import '../../../../models/order.dart';
import '../../../../models/app_config_data.dart';
import '../../../../models/review.dart';
import '../../../../services/marketplace_repository.dart';
import '../../../../services/recent_searches_store.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

// ─── Repository ───────────────────────────────────────────────────────────────

final marketplaceRepositoryProvider = Provider<MarketplaceRepository>((ref) {
  return MarketplaceRepository(FirebaseFirestore.instance);
});

// ─── Categories / Styles / Config ────────────────────────────────────────────

final categoriesProvider = FutureProvider<List<ProductCategory>>((ref) async {
  final repo = ref.watch(marketplaceRepositoryProvider);
  return repo.fetchCategories();
});

final stylesProvider = FutureProvider<List<String>>((ref) async {
  final repo = ref.watch(marketplaceRepositoryProvider);
  return repo.fetchStyles();
});

final configProvider = FutureProvider<AppConfigData>((ref) async {
  final repo = ref.watch(marketplaceRepositoryProvider);
  return repo.fetchConfig();
});

/// Membership tier the signed-in customer currently holds, derived from
/// their COMPLETED-order count (delivered orders only) vs the configured
/// tier thresholds. Orders still in flight (pending/confirmed/shipped) or
/// cancelled do not count towards a tier.
/// Null while config is still loading.
final customerMembershipTierProvider = Provider<MembershipTier?>((ref) {
  final config = ref.watch(configProvider).valueOrNull;
  if (config == null) return null;
  final orders = ref.watch(customerOrdersProvider).valueOrNull;
  final deliveredCount =
      orders?.where((o) => o.status == OrderStatus.delivered).length ?? 0;
  return config.tierForOrderCount(deliveredCount);
});

// ─── Products (real-time Firestore sync) ─────────────────────────────────────

final marketplaceProductsProvider = StreamProvider<List<Product>>((ref) {
  final repo = ref.watch(marketplaceRepositoryProvider);
  return repo.watchProducts();
});

// ─── Search & Filters ─────────────────────────────────────────────────────────

enum SortOption { recommended, priceLowToHigh, priceHighToLow, newest, topRated }

extension SortOptionLabels on SortOption {
  /// Full label used in the sort sheet / menus.
  String get label => switch (this) {
        SortOption.recommended => 'Recommended',
        SortOption.newest => 'Newest',
        SortOption.priceLowToHigh => 'Price: Low to High',
        SortOption.priceHighToLow => 'Price: High to Low',
        SortOption.topRated => 'Top Rated',
      };

  /// Compact label for the active-filter chip row, e.g. "Price: Low ↑".
  String get chipLabel => switch (this) {
        SortOption.recommended => 'Recommended',
        SortOption.newest => 'Newest',
        SortOption.priceLowToHigh => 'Price: Low ↑',
        SortOption.priceHighToLow => 'Price: High ↓',
        SortOption.topRated => 'Top Rated',
      };
}

final searchQueryProvider = StateProvider<String>((ref) => '');

final selectedCategoryFilterProvider = StateProvider<String>((ref) => 'All');

final selectedStyleFilterProvider = StateProvider<String>((ref) => 'All');

final sortOptionProvider =
    StateProvider<SortOption>((ref) => SortOption.recommended);

final ecoOnlyProvider = StateProvider<bool>((ref) => false);

final inStockOnlyProvider = StateProvider<bool>((ref) => false);

/// Verified-seller gate. Defaults ON; buyers can widen to all sellers from
/// the filters sheet (the switch is now user-visible).
final verifiedOnlyProvider = StateProvider<bool>((ref) => true);

/// An inclusive [min, max] price band selected in the filters sheet.
class PriceFilter {
  const PriceFilter({required this.min, required this.max});

  final int min;
  final int max;

  bool contains(int price) => price >= min && price <= max;

  @override
  bool operator ==(Object other) =>
      other is PriceFilter && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'PriceFilter($min–$max)';
}

/// User-selected price band; `null` = not touched (whole range shown).
final priceRangeFilterProvider = StateProvider<PriceFilter?>((ref) => null);

/// Actual min/max price across the (active) catalogue — used as the slider
/// bounds. `null` when there is nothing to range over.
final productPriceBoundsProvider = Provider<PriceFilter?>((ref) {
  final products =
      ref.watch(marketplaceProductsProvider).valueOrNull ?? const <Product>[];
  var min = 0;
  var max = 0;
  var seen = false;
  for (final p in products) {
    if (!p.isActive) continue;
    min = !seen || p.price < min ? p.price : min;
    max = !seen || p.price > max ? p.price : max;
    seen = true;
  }
  if (!seen) return null;
  return PriceFilter(min: min, max: max);
});

/// True when the stored price band actually narrows the data bounds.
bool isPriceFilterActive(PriceFilter? selected, PriceFilter? bounds) {
  if (selected == null || bounds == null) return false;
  return selected.min > bounds.min || selected.max < bounds.max;
}

/// Per-dimension activity of the marketplace search/filter UI, computed in
/// ONE place. The screen's sheet badge, chip rows and "Clear all" derive
/// from these flags so their notion of "a filter is active" can never drift
/// apart.
class MarketplaceFilterState {
  const MarketplaceFilterState({
    required this.searchActive,
    required this.sortActive,
    required this.categoryActive,
    required this.styleActive,
    required this.priceActive,
    required this.stockActive,
    required this.ecoActive,
    required this.verifiedOff,
  });

  final bool searchActive;
  final bool sortActive;
  final bool categoryActive;
  final bool styleActive;
  final bool priceActive;
  final bool stockActive;
  final bool ecoActive;
  final bool verifiedOff;

  /// Whether ANY non-default state is active.
  bool get anyActive => totalCount > 0;

  /// Count of EVERY non-default state (search + sort + filters sheet).
  /// Drives the "Clear filters" CTA and empty states.
  int get totalCount => [
        searchActive,
        sortActive,
        categoryActive,
        styleActive,
        priceActive,
        stockActive,
        ecoActive,
        verifiedOff,
      ].where((b) => b).length;

  /// Count of the FILTERS-SHEET-owned states only. Search and sort have
  /// their own chrome (search field, sort chip), so they are excluded from
  /// the sheet's badge and "Clear all".
  int get sheetCount => [
        categoryActive,
        styleActive,
        priceActive,
        stockActive,
        ecoActive,
        verifiedOff,
      ].where((b) => b).length;

  /// Whether the filters sheet alone deviates from its defaults.
  bool get sheetDirty => sheetCount > 0;
}

/// Single source of truth for "is this filter state active?" — consumed by
/// [activeFilterCountProvider], the marketplace screen's sheet badge and
/// its removable chip rows.
final marketplaceFilterStateProvider =
    Provider<MarketplaceFilterState>((ref) {
  return MarketplaceFilterState(
    searchActive: ref.watch(searchQueryProvider).trim().isNotEmpty,
    sortActive: ref.watch(sortOptionProvider) != SortOption.recommended,
    categoryActive: ref.watch(selectedCategoryFilterProvider) != 'All',
    styleActive: ref.watch(selectedStyleFilterProvider) != 'All',
    priceActive: isPriceFilterActive(ref.watch(priceRangeFilterProvider),
        ref.watch(productPriceBoundsProvider)),
    stockActive: ref.watch(inStockOnlyProvider),
    ecoActive: ref.watch(ecoOnlyProvider),
    verifiedOff: !ref.watch(verifiedOnlyProvider),
  );
});

/// Count of every non-default marketplace filter/sort/search state.
/// Drives the "Clear filters" CTA and empty states.
final activeFilterCountProvider = Provider<int>((ref) {
  return ref.watch(marketplaceFilterStateProvider).totalCount;
});

/// Resets all marketplace filters back to their defaults. `includeSearch`
/// and `includeSort` let callers scope the reset (e.g. the filters sheet
/// should not touch the search field or the sort choice).
void resetMarketplaceFilters(
  WidgetRef ref, {
  bool includeSearch = true,
  bool includeSort = true,
}) {
  if (includeSearch) {
    ref.read(searchQueryProvider.notifier).state = '';
  }
  if (includeSort) {
    ref.read(sortOptionProvider.notifier).state = SortOption.recommended;
  }
  ref.read(selectedCategoryFilterProvider.notifier).state = 'All';
  ref.read(selectedStyleFilterProvider.notifier).state = 'All';
  ref.read(ecoOnlyProvider.notifier).state = false;
  ref.read(inStockOnlyProvider.notifier).state = false;
  ref.read(verifiedOnlyProvider.notifier).state = true;
  ref.read(priceRangeFilterProvider.notifier).state = null;
}

// ─── Filtered Products (derived, buyer-facing) ───────────────────────────────

/// Buyer-facing product list: applies keyword/category/style/eco/verified/
/// price/stock filters and sorting. Inactive (paused) listings are hidden.
final filteredProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(marketplaceProductsProvider).valueOrNull ?? [];
  final styleFilter = ref.watch(selectedStyleFilterProvider);
  final categoryFilter = ref.watch(selectedCategoryFilterProvider);
  final searchQuery = ref.watch(searchQueryProvider).toLowerCase().trim();
  final sort = ref.watch(sortOptionProvider);
  final ecoOnly = ref.watch(ecoOnlyProvider);
  final verifiedOnly = ref.watch(verifiedOnlyProvider);
  final inStockOnly = ref.watch(inStockOnlyProvider);
  final priceFilter = ref.watch(priceRangeFilterProvider);

  var result = products;

  // Hide paused listings from buyers.
  result = result.where((p) => p.isActive).toList();

  // Filter by verified suppliers
  if (verifiedOnly) {
    result = result.where((p) => p.supplier.isVerified).toList();
  }

  // Filter by style
  if (styleFilter != 'All') {
    result = result
        .where(
            (p) => p.designStyle.toLowerCase() == styleFilter.toLowerCase())
        .toList();
  }

  // Filter by category
  if (categoryFilter != 'All') {
    result = result
        .where((p) => p.category.toLowerCase() == categoryFilter.toLowerCase())
        .toList();
  }

  // Filter by eco-friendly
  if (ecoOnly) {
    result = result.where((p) => p.isEcoFriendly).toList();
  }

  // In stock only
  if (inStockOnly) {
    result = result.where((p) => !p.isOutOfStock).toList();
  }

  // Price band
  if (priceFilter != null) {
    result = result.where((p) => priceFilter.contains(p.price)).toList();
  }

  // Search across name, description, category, style, supplier name
  if (searchQuery.isNotEmpty) {
    result = result.where((p) {
      return p.name.toLowerCase().contains(searchQuery) ||
          p.description.toLowerCase().contains(searchQuery) ||
          p.category.toLowerCase().contains(searchQuery) ||
          p.designStyle.toLowerCase().contains(searchQuery) ||
          p.supplier.name.toLowerCase().contains(searchQuery);
    }).toList();
  }

  // Sort.
  // Recommended keeps the base stream order: the catalogue is curated
  // (seed items first by design) and stays stable as new items stream in —
  // seller publishes → the listing is visible immediately. Dedicated
  // rating/price sorts are offered as explicit choices below.
  switch (sort) {
    case SortOption.recommended:
      break; // keep base order
    case SortOption.priceLowToHigh:
      result.sort((a, b) => a.price.compareTo(b.price));
      break;
    case SortOption.priceHighToLow:
      result.sort((a, b) => b.price.compareTo(a.price));
      break;
    case SortOption.newest:
      result.sort((a, b) {
        if (a.createdAt == null && b.createdAt == null) return 0;
        if (a.createdAt == null) return 1;
        if (b.createdAt == null) return -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });
      break;
    case SortOption.topRated:
      // Aggregate rating first; review count then recency break ties.
      result.sort((a, b) {
        final byRating = b.rating.compareTo(a.rating);
        if (byRating != 0) return byRating;
        final byCount = b.ratingCount.compareTo(a.ratingCount);
        if (byCount != 0) return byCount;
        final ta = a.createdAt;
        final tb = b.createdAt;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      break;
  }

  return result;
});

// ─── Recent searches (device-persisted) ───────────────────────────────────────

final recentSearchesStoreProvider = Provider<RecentSearchesStore>((ref) {
  return RecentSearchesStore();
});

/// Most-recent-first search terms, hydrated from [RecentSearchesStore].
class RecentSearchesNotifier extends Notifier<List<String>> {
  static const int _maxEntries = RecentSearchesStore.maxEntries;

  @override
  List<String> build() {
    final store = ref.watch(recentSearchesStoreProvider);
    Future<void>.microtask(() async {
      try {
        final loaded = await store.load();
        if (loaded.isEmpty) return;
        state = loaded.take(_maxEntries).toList();
      } catch (e) {
        debugPrint('[recent-searches] load failed: $e');
      }
    });
    return const [];
  }

  Future<void> _persist(List<String> terms) async {
    try {
      await ref.read(recentSearchesStoreProvider).save(terms);
    } catch (e) {
      debugPrint('[recent-searches] save failed: $e');
    }
  }

  /// Records a submitted/used search term at the front (deduped, capped).
  void record(String term) {
    final cleaned = term.trim();
    if (cleaned.isEmpty) return;
    final next = [
      cleaned,
      ...state.where((s) => s.toLowerCase() != cleaned.toLowerCase()),
    ].take(_maxEntries).toList();
    state = next;
    unawaited(_persist(next));
  }

  void remove(String term) {
    final next = state.where((s) => s != term).toList();
    state = next;
    unawaited(_persist(next));
  }

  void clearAll() {
    state = const [];
    unawaited(_persist(const []));
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
        RecentSearchesNotifier.new);

// ─── Reviews (real-time, per product) ─────────────────────────────────────────

final productReviewsProvider =
    StreamProvider.family<List<Review>, String>((ref, productId) {
  final repo = ref.watch(marketplaceRepositoryProvider);
  return repo.watchReviews(productId);
});

// ─── Cart (local-first state, Firestore write-through + hydration) ───────────

/// True once the signed-in user's cart has emitted at least one Firestore
/// snapshot (or the watch failed) — lets the cart screen distinguish
/// "hydrating from Firestore" from a genuinely empty cart.
final cartHydratedProvider = StateProvider<bool>((ref) => false);

class CartNotifier extends Notifier<List<CartItem>> {
  StreamSubscription<List<CartItem>>? _cartSub;
  StreamSubscription<List<Product>>? _productsSub;

  /// Latest catalogue emission, used to reconcile cart rows against live
  /// stock/price data (null until the products stream first emits).
  List<Product>? _latestProducts;

  String? get _uid => ref.read(currentUserProvider)?.uid;

  @override
  List<CartItem> build() {
    final uid = ref.watch(currentUserProvider)?.uid;
    ref.onDispose(() {
      _cartSub?.cancel();
      _productsSub?.cancel();
    });
    _cartSub?.cancel();
    _productsSub?.cancel();
    _latestProducts = null;

    // A (re)build means a new user session or a fresh subscription — treat
    // the cart as hydrating until the first snapshot arrives.
    ref.read(cartHydratedProvider.notifier).state = false;

    final repo = ref.watch(marketplaceRepositoryProvider);

    // Track the live catalogue so cart rows can reconcile against it: stale
    // quantities are clamped and embedded snapshots refreshed in place
    // (persisted back so Firestore converges to the same state).
    _productsSub = repo.watchProducts().listen(
          (products) {
            _latestProducts = products;
            _reconcileAgainstLive();
          },
          onError: (Object e, StackTrace st) {
            debugPrint('[cart] products watch failed: $e');
          },
        );

    if (uid == null) return [];

    // Hydrate + stay in sync from Firestore.
    _cartSub = repo.watchCart(uid).listen(
          (items) {
            state = _clampQuantitiesToStock(items);
            ref.read(cartHydratedProvider.notifier).state = true;
          },
          onError: (Object e, StackTrace st) {
            debugPrint('[cart] watch failed: $e');
            // Mark hydrated so the UI does not sit on a skeleton forever
            // when offline — it falls back to the empty-cart state.
            ref.read(cartHydratedProvider.notifier).state = true;
          },
        );
    return [];
  }

  /// Reconciles the in-memory cart against the live catalogue: quantities
  /// above live stock are clamped, embedded snapshots refreshed, and only
  /// rows that actually changed are persisted — so the quantity the UI
  /// shows always matches what the create-order transaction will accept.
  /// Deleted/paused listings are left intact (removal is the buyer's
  /// explicit act); checkout gates those rows via [cartRowsProvider].
  void _reconcileAgainstLive() {
    final uid = _uid;
    if (uid == null || state.isEmpty) return;
    final products = _latestProducts;
    if (products == null) return;
    final byId = {for (final p in products) p.id: p};
    final repo = ref.read(marketplaceRepositoryProvider);

    var changed = false;
    final next = <CartItem>[];
    for (final ci in state) {
      final live = byId[ci.product.id];
      if (live == null || !live.isActive) {
        next.add(ci);
        continue;
      }
      if (live.stock <= 0) {
        // Out of stock: refresh the snapshot (price may have changed) but
        // keep the quantity — removing the row stays the buyer's act.
        if (ci.product.stock != live.stock || ci.product.price != live.price) {
          next.add(ci.copyWith(product: live));
          changed = true;
          _persist(() => repo.saveCartItem(uid, ci.copyWith(product: live)));
        } else {
          next.add(ci);
        }
        continue;
      }
      final clamped = ci.quantity.clamp(1, live.stock);
      final snapshotChanged = ci.product.stock != live.stock ||
          ci.product.price != live.price ||
          ci.product.image != live.image;
      if (clamped != ci.quantity || snapshotChanged) {
        final updated = ci.copyWith(product: live, quantity: clamped);
        next.add(updated);
        changed = true;
        _persist(() => repo.saveCartItem(uid, updated));
      } else {
        next.add(ci);
      }
    }
    if (changed) {
      state = next;
      debugPrint('[cart] reconciled against live catalogue '
          '(${next.length} rows)');
    }
  }

  /// Keeps stored quantities honest against the LIVE catalogue when it has
  /// emitted (falling back to the embedded snapshot while it has not):
  /// quantities above the recorded stock are pulled back down (the adjusted
  /// rows are persisted so Firestore converges). Rows whose product is fully
  /// out of stock are left intact — removal is the buyer's explicit act
  /// (swipe / X), and the checkout is gated meanwhile.
  List<CartItem> _clampQuantitiesToStock(List<CartItem> items) {
    final liveById = {
      for (final p in _latestProducts ?? const <Product>[]) p.id: p,
    };
    var adjusted = false;
    final repo = ref.read(marketplaceRepositoryProvider);
    final next = <CartItem>[];
    for (final ci in items) {
      final live = liveById[ci.product.id] ?? ci.product;
      if (live.stock > 0 && ci.quantity > live.stock) {
        final clamped = ci.copyWith(product: live, quantity: live.stock);
        next.add(clamped);
        adjusted = true;
        final uid = _uid;
        if (uid != null) _persist(() => repo.saveCartItem(uid, clamped));
      } else {
        next.add(ci);
      }
    }
    if (adjusted) {
      debugPrint('[cart] quantities clamped to stock: '
          '${items.map((c) => '${c.product.name}:${c.quantity}').join(', ')} '
          '→ ${next.map((c) => '${c.quantity}').join(', ')}');
    }
    return next;
  }

  void _persist(Future<void> Function() write) {
    unawaited(write().catchError((Object e, StackTrace st) {
      debugPrint('[cart] Firestore write-through failed: $e');
    }));
  }

  /// Freshest product snapshot for [embedded] from the live products
  /// stream, when the stream has emitted; [embedded] itself otherwise.
  /// Persisted cart rows always carry current catalogue data through this.
  Product _freshSnapshot(Product embedded) {
    final live = ref
        .read(marketplaceProductsProvider)
        .valueOrNull
        ?.where((p) => p.id == embedded.id)
        .firstOrNull;
    return live ?? embedded;
  }

  /// Adds a product (merging quantity by productId, clamped to stock).
  ///
  /// The persisted row embeds the LIVE catalogue snapshot (when available)
  /// so rows keep fresh stock/price data; a listing the live catalogue
  /// reports as sold out (or gone) cannot be added.
  void addItem(Product product, {int qty = 1}) {
    if (product.isOutOfStock) return;
    final uid = _uid;
    if (uid == null) return;

    final fresh = _freshSnapshot(product);
    if (fresh.isOutOfStock) return;

    final existing = state.indexWhere((ci) => ci.product.id == product.id);
    final CartItem item;
    if (existing >= 0) {
      final current = state[existing];
      item = current.copyWith(
          product: fresh,
          quantity: (current.quantity + qty).clamp(1, fresh.stock));
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == existing) item else state[i],
      ];
    } else {
      item = CartItem(product: fresh, quantity: qty.clamp(1, fresh.stock));
      state = [...state, item];
    }
    final repo = ref.read(marketplaceRepositoryProvider);
    _persist(() => repo.saveCartItem(uid, item));
  }

  void removeItem(String productId) {
    final uid = _uid;
    if (uid == null) return;
    state = state.where((ci) => ci.product.id != productId).toList();
    final repo = ref.read(marketplaceRepositoryProvider);
    _persist(() => repo.removeCartItem(uid, productId));
  }

  /// Re-adds a previously removed item at its original quantity (the UNDO
  /// action of swipe-to-delete). Merges into an existing row of the same
  /// product, clamped to recorded stock. Returns false when the product is
  /// out of stock and nothing could be restored.
  bool restoreItem(CartItem item) {
    // Undo restores against the LIVE snapshot so a stock cut that happened
    // after the swipe is respected (and the fresh data is persisted).
    final fresh = _freshSnapshot(item.product);
    if (fresh.isOutOfStock) return false;
    final uid = _uid;
    if (uid == null) return false;
    final maxQty = fresh.stock < 1 ? item.quantity : fresh.stock;
    final idx = state.indexWhere((ci) => ci.product.id == item.product.id);
    final repo = ref.read(marketplaceRepositoryProvider);
    if (idx >= 0) {
      final merged = state[idx].copyWith(
        product: fresh,
        quantity: (state[idx].quantity + item.quantity).clamp(1, maxQty),
      );
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == idx) merged else state[i],
      ];
      _persist(() => repo.saveCartItem(uid, merged));
    } else {
      final restored = item.copyWith(
          product: fresh, quantity: item.quantity.clamp(1, maxQty));
      state = [...state, restored];
      _persist(() => repo.saveCartItem(uid, restored));
    }
    return true;
  }

  void setQuantity(String productId, int qty) {
    final idx = state.indexWhere((ci) => ci.product.id == productId);
    if (idx < 0) return;
    final current = state[idx];
    // Refresh the embedded snapshot from the live catalogue first, so the
    // persisted row carries fresh stock/price data.
    final fresh = _freshSnapshot(current.product);
    // Out-of-stock rows keep their recorded quantity — only the owner of the
    // row may remove them (swipe/X), so no quantity change can be persisted.
    final clamped = fresh.stock > 0
        ? qty.clamp(1, fresh.stock)
        : current.quantity;
    final updated = current.copyWith(product: fresh, quantity: clamped);
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == idx) updated else state[i],
    ];
    final uid = _uid;
    if (uid != null) {
      _persist(() =>
          ref.read(marketplaceRepositoryProvider).saveCartItem(uid, updated));
    }
  }

  void clear() {
    final uid = _uid;
    state = [];
    if (uid != null) {
      _persist(() => ref.read(marketplaceRepositoryProvider).clearCart(uid));
    }
  }

  /// Clears local state immediately and WAITS for the Firestore delete to
  /// finish. Used at checkout, where navigating to the confirmation screen
  /// must not race the write-through (a lost clear would resurrect the
  /// purchased rows on the next hydration). Failures are logged, never
  /// thrown — an un-cleared cart is recoverable.
  Future<void> clearAndPersist() async {
    final uid = _uid;
    state = [];
    if (uid == null) return;
    try {
      await ref.read(marketplaceRepositoryProvider).clearCart(uid);
    } catch (e) {
      debugPrint('[cart] Firestore clear failed: $e');
    }
  }
}

final cartProvider =
    NotifierProvider<CartNotifier, List<CartItem>>(CartNotifier.new);

final cartCountProvider = Provider<int>((ref) {
  return ref
      .watch(cartRowsProvider)
      .fold<int>(0, (total, row) => total + row.effectiveQty);
});

final cartTotalProvider = Provider<int>((ref) {
  return ref.watch(cartRowsProvider).fold<int>(
      0, (total, row) => total + row.live.price * row.effectiveQty);
});

/// One cart line reconciliated against the LIVE catalogue.
///
/// [live] carries the freshest product data: the matching catalogue product
/// once the products stream has emitted, the embedded snapshot otherwise
/// (so rows still render while the catalogue is loading/unavailable).
/// [missing] marks products that no longer exist in the catalogue and
/// [inactive] marks listings the seller has paused — both make the row
/// uncheckoutable ([unavailable]) with copy that says so.
class CartRow {
  const CartRow({
    required this.item,
    required this.live,
    required this.missing,
    required this.inactive,
  });

  final CartItem item;

  /// Product to render/price against (live when resolvable, embedded
  /// otherwise).
  final Product live;

  /// Whether the product has been deleted from the live catalogue.
  final bool missing;

  /// Whether the listing is paused (`isActive == false`).
  final bool inactive;

  /// Current stock from the live catalogue.
  int get liveStock => live.stock;

  /// Whether this row can take part in a checkout.
  bool get unavailable => missing || inactive || live.stock <= 0;

  /// Quantity this row bills at: the stored quantity capped to the live
  /// stock (so the money shown always matches what the create-order
  /// transaction will accept), floored at 1 while the row is purchasable.
  /// Unavailable rows (deleted/paused/sold out) keep their stored quantity
  /// since they are excluded from checkout anyway.
  int get effectiveQty {
    if (missing || inactive) return item.quantity;
    return live.stock > 0 ? item.quantity.clamp(1, live.stock) : item.quantity;
  }
}

/// Payload for a Buy-Now checkout (passed as the route extra to the
/// checkout screen): the order contains ONLY [product] at [quantity], and
/// the buyer's cart is left untouched on success.
class BuyNowRequest {
  const BuyNowRequest({required this.product, required this.quantity});

  final Product product;
  final int quantity;
}

/// The cart reconciled against the live product stream — the single source
/// the cart and checkout screens should render from.
final cartRowsProvider = Provider<List<CartRow>>((ref) {
  final cart = ref.watch(cartProvider);
  if (cart.isEmpty) return const [];

  final liveProducts = ref.watch(marketplaceProductsProvider).valueOrNull;
  // The catalogue has not emitted yet: we cannot judge availability. Treat
  // every row as fine — the create-order transaction is the backstop.
  if (liveProducts == null) {
    return [
      for (final ci in cart)
        CartRow(item: ci, live: ci.product, missing: false, inactive: false),
    ];
  }

  final byId = {for (final p in liveProducts) p.id: p};
  return [
    for (final ci in cart)
      () {
        final live = byId[ci.product.id];
        if (live == null) {
          return CartRow(
            item: ci,
            live: ci.product,
            missing: true,
            inactive: false,
          );
        }
        return CartRow(
          item: ci,
          live: live,
          missing: false,
          inactive: !live.isActive,
        );
      }(),
  ];
});

// ─── Wishlist (local-first state, Firestore write-through + hydration) ───────

class WishlistNotifier extends Notifier<Set<String>> {
  StreamSubscription<List<String>>? _wishSub;

  String? get _uid => ref.read(currentUserProvider)?.uid;

  @override
  Set<String> build() {
    final uid = ref.watch(currentUserProvider)?.uid;
    ref.onDispose(() => _wishSub?.cancel());
    _wishSub?.cancel();

    if (uid == null) return {};

    final repo = ref.watch(marketplaceRepositoryProvider);
    _wishSub = repo.watchWishlistIds(uid).listen(
          (ids) => state = ids.toSet(),
          onError: (Object e, StackTrace st) =>
              debugPrint('[wishlist] watch failed: $e'),
        );
    return {};
  }

  void _persist(Future<void> Function() write) {
    unawaited(write().catchError((Object e, StackTrace st) {
      debugPrint('[wishlist] Firestore write-through failed: $e');
    }));
  }

  void toggle(String productId) {
    if (state.contains(productId)) {
      remove(productId);
    } else {
      add(productId);
    }
  }

  void add(String productId) {
    final uid = _uid;
    if (uid == null) return;
    state = {...state, productId};
    _persist(
        () => ref.read(marketplaceRepositoryProvider).addToWishlist(
            uid, productId));
  }

  void remove(String productId) {
    final uid = _uid;
    if (uid == null) return;
    state = state.where((id) => id != productId).toSet();
    _persist(() =>
        ref.read(marketplaceRepositoryProvider).removeFromWishlist(
            uid, productId));
  }

  /// Removes several ids at once (used by stale-id pruning and "add all
  /// to cart", where per-item snackbars would be noise).
  void removeAll(Iterable<String> productIds) {
    final ids = productIds.toSet();
    if (ids.isEmpty) return;
    final uid = _uid;
    if (uid == null) return;
    state = state.where((id) => !ids.contains(id)).toSet();
    final repo = ref.read(marketplaceRepositoryProvider);
    for (final id in ids) {
      _persist(() => repo.removeFromWishlist(uid, id));
    }
  }

  bool contains(String productId) => state.contains(productId);
}

final wishlistProvider =
    NotifierProvider<WishlistNotifier, Set<String>>(WishlistNotifier.new);

final wishlistCountProvider = Provider<int>((ref) {
  return ref.watch(wishlistProvider).length;
});

// ─── Orders (real-time, role-scoped) ─────────────────────────────────────────

/// Orders placed by the signed-in customer.
final customerOrdersProvider = StreamProvider<List<Order>>((ref) {
  final repo = ref.watch(marketplaceRepositoryProvider);
  final uid = ref.watch(currentUserProvider)?.uid ?? '';
  if (uid.isEmpty) return Stream.value(const []);
  return repo.watchCustomerOrders(uid);
});

/// Orders containing at least one line item from the given supplier.
final supplierOrdersProvider =
    StreamProvider.family<List<Order>, String>((ref, supplierId) {
  final repo = ref.watch(marketplaceRepositoryProvider);
  if (supplierId.isEmpty) return Stream.value(const []);
  return repo.watchSupplierOrders(supplierId);
});

// ─── Single-order detail + per-order reviews ─────────────────────────────────

/// One-shot fetch of one order; null when the document does not exist.
/// Used by the order-confirmation screen right after checkout.
final orderFetchProvider = FutureProvider.family<Order?, String>((ref, id) {
  final repo = ref.watch(marketplaceRepositoryProvider);
  return repo.fetchOrder(id);
});

/// Live stream of one order document (null while it does not exist) — the
/// buyer order detail watches this so supplier status changes appear in
/// real time without manual refresh.
final orderDetailProvider = StreamProvider.family<Order?, String>((ref, id) {
  final repo = ref.watch(marketplaceRepositoryProvider);
  return repo.watchOrder(id);
});

/// Review the signed-in buyer left for a product within an order, or null
/// when that (product, order) pair has not been reviewed yet. One review
/// per order per product by construction (doc id = orderId).
final orderReviewProvider = FutureProvider.family<
    Review?, ({String productId, String orderId})>((ref, key) {
  final repo = ref.watch(marketplaceRepositoryProvider);
  return repo.fetchReviewForOrder(key.productId, key.orderId);
});
