import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/product.dart';
import '../../../../models/product_category.dart';
import '../../../../models/cart_item.dart';
import '../../../../models/order.dart';
import '../../../../models/app_config_data.dart';
import '../../../../services/marketplace_service.dart';

// ─── Service ──────────────────────────────────────────────────────────────────

final marketplaceServiceProvider = Provider<MarketplaceService>((ref) {
  return HttpMarketplaceService();
});

// ─── Categories (from API) ────────────────────────────────────────────────────

final categoriesProvider =
    FutureProvider<List<ProductCategory>>((ref) async {
  final service = ref.watch(marketplaceServiceProvider);
  return service.fetchCategories();
});

// ─── Styles (from API) ────────────────────────────────────────────────────────

final stylesProvider = FutureProvider<List<String>>((ref) async {
  final service = ref.watch(marketplaceServiceProvider);
  return service.fetchStyles();
});

// ─── Config (from API) ────────────────────────────────────────────────────────

final configProvider = FutureProvider<AppConfigData>((ref) async {
  final service = ref.watch(marketplaceServiceProvider);
  return service.fetchConfig();
});

// ─── Products ─────────────────────────────────────────────────────────────────

final marketplaceProductsProvider =
    FutureProvider<List<Product>>((ref) async {
  final service = ref.watch(marketplaceServiceProvider);
  return service.fetchProducts();
});

// ─── Search & Filters ─────────────────────────────────────────────────────────

enum SortOption { relevance, priceLowToHigh, priceHighToLow, newest }

final searchQueryProvider = StateProvider<String>((ref) => '');

final selectedCategoryFilterProvider = StateProvider<String>((ref) => 'All');

final selectedStyleFilterProvider = StateProvider<String>((ref) => 'All');

final sortOptionProvider =
    StateProvider<SortOption>((ref) => SortOption.relevance);

final ecoOnlyProvider = StateProvider<bool>((ref) => false);

final verifiedOnlyProvider = StateProvider<bool>((ref) => true);

// ─── Filtered Products (derived) ─────────────────────────────────────────────

final filteredProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(marketplaceProductsProvider).valueOrNull ?? [];
  final styleFilter = ref.watch(selectedStyleFilterProvider);
  final categoryFilter = ref.watch(selectedCategoryFilterProvider);
  final searchQuery = ref.watch(searchQueryProvider).toLowerCase().trim();
  final sort = ref.watch(sortOptionProvider);
  final ecoOnly = ref.watch(ecoOnlyProvider);
  final verifiedOnly = ref.watch(verifiedOnlyProvider);

  var result = products;

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

  // Sort
  switch (sort) {
    case SortOption.relevance:
      break; // keep original order
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
  }

  return result;
});

// ─── Cart ─────────────────────────────────────────────────────────────────────

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  void addItem(Product product, {int qty = 1}) {
    if (product.isOutOfStock) return;
    final existing = state.indexWhere((ci) => ci.product.id == product.id);
    if (existing >= 0) {
      final current = state[existing];
      final newQty = (current.quantity + qty).clamp(1, product.stock);
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == existing)
            current.copyWith(quantity: newQty)
          else
            state[i],
      ];
    } else {
      state = [
        ...state,
        CartItem(
            product: product, quantity: qty.clamp(1, product.stock)),
      ];
    }
  }

  void removeItem(String productId) {
    state = state.where((ci) => ci.product.id != productId).toList();
  }

  void increment(String productId) {
    final idx = state.indexWhere((ci) => ci.product.id == productId);
    if (idx < 0) return;
    final current = state[idx];
    if (current.quantity >= current.product.stock) return;
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == idx)
          current.copyWith(quantity: current.quantity + 1)
        else
          state[i],
    ];
  }

  void decrement(String productId) {
    final idx = state.indexWhere((ci) => ci.product.id == productId);
    if (idx < 0) return;
    final current = state[idx];
    if (current.quantity <= 1) {
      removeItem(productId);
      return;
    }
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == idx)
          current.copyWith(quantity: current.quantity - 1)
        else
          state[i],
    ];
  }

  void setQuantity(String productId, int qty) {
    final idx = state.indexWhere((ci) => ci.product.id == productId);
    if (idx < 0) return;
    final current = state[idx];
    final clamped = qty.clamp(1, current.product.stock);
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == idx)
          current.copyWith(quantity: clamped)
        else
          state[i],
    ];
  }

  void clear() {
    state = [];
  }
}

final cartProvider =
    NotifierProvider<CartNotifier, List<CartItem>>(CartNotifier.new);

final cartCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).fold<int>(0, (sum, ci) => sum + ci.quantity);
});

final cartTotalProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).fold<int>(0, (sum, ci) => sum + ci.lineTotal);
});

// ─── Wishlist ─────────────────────────────────────────────────────────────────

class WishlistNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void toggle(String productId) {
    if (state.contains(productId)) {
      state = state.where((id) => id != productId).toSet();
    } else {
      state = {...state, productId};
    }
  }

  bool contains(String productId) => state.contains(productId);
}

final wishlistProvider =
    NotifierProvider<WishlistNotifier, Set<String>>(WishlistNotifier.new);

final wishlistCountProvider = Provider<int>((ref) {
  return ref.watch(wishlistProvider).length;
});

// ─── Orders ───────────────────────────────────────────────────────────────────

final ordersProvider = FutureProvider<List<Order>>((ref) async {
  final service = ref.watch(marketplaceServiceProvider);
  return service.fetchOrders();
});
