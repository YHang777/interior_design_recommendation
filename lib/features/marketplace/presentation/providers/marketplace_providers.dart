import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/product.dart';
import '../../../../services/marketplace_service.dart';

/// Provides the marketplace service instance.
final marketplaceServiceProvider = Provider<MarketplaceService>((ref) {
  return HttpMarketplaceService();
});

/// Async product list from the service.
final marketplaceProductsProvider =
    FutureProvider<List<Product>>((ref) async {
  final service = ref.watch(marketplaceServiceProvider);
  return service.fetchProducts();
});

/// Currently selected design style filter.
final selectedStyleFilterProvider = StateProvider<String>((ref) => 'All');

/// Cart state — local, not persisted.
final cartProvider = StateProvider<List<Product>>((ref) => []);

/// Filtered products based on selected style.
final filteredProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(marketplaceProductsProvider).valueOrNull ?? [];
  final filter = ref.watch(selectedStyleFilterProvider);

  if (filter == 'All') return products;
  return products
      .where((p) => p.designStyle.toLowerCase() == filter.toLowerCase())
      .toList();
});
