import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../services/marketplace_service.dart';

enum MarketplaceStatus { idle, loading, loaded, error }

class MarketplaceProvider extends ChangeNotifier {
  final MarketplaceService _service = HttpMarketplaceService();

  MarketplaceStatus status = MarketplaceStatus.idle;
  List<Product> products = [];
  String? error;
  Timer? _pollTimer;

  Future<void> fetchProducts() async {
    status = MarketplaceStatus.loading;
    error = null;
    notifyListeners();
    try {
      final items = await _service.fetchProducts();
      products = items;
      status = MarketplaceStatus.loaded;
      notifyListeners();
      // Start auto-refresh once initial fetch succeeds
      if (_pollTimer == null) {
        startAutoRefresh();
      }
    } catch (e) {
      status = MarketplaceStatus.error;
      error = e.toString();
      notifyListeners();
    }
  }

  List<Product> filteredByStyle(String selected) {
    if (selected == 'All') return products;
    return products.where((p) => p.designStyle == selected).toList();
  }

  Future<void> addProduct(Product product) async {
    status = MarketplaceStatus.loading;
    error = null;
    notifyListeners();
    try {
      final created = await _service.createProduct(product);
      products = [...products, created];
      status = MarketplaceStatus.loaded;
      notifyListeners();
    } catch (e) {
      status = MarketplaceStatus.error;
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateExistingProduct(String id, Product product) async {
    status = MarketplaceStatus.loading;
    error = null;
    notifyListeners();
    try {
      final updated = await _service.updateProduct(id, product);
      products = products.map((p) => p.id == id ? updated : p).toList();
      status = MarketplaceStatus.loaded;
      notifyListeners();
    } catch (e) {
      status = MarketplaceStatus.error;
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> removeProduct(String id) async {
    status = MarketplaceStatus.loading;
    error = null;
    notifyListeners();
    try {
      await _service.deleteProduct(id);
      products = products.where((p) => p.id != id).toList();
      status = MarketplaceStatus.loaded;
      notifyListeners();
    } catch (e) {
      status = MarketplaceStatus.error;
      error = e.toString();
      notifyListeners();
    }
  }

  void startAutoRefresh({Duration interval = const Duration(seconds: 10)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) async {
      try {
        final items = await _service.fetchProducts();
        products = items;
        status = MarketplaceStatus.loaded;
        notifyListeners();
      } catch (e) {
        // Keep current view; record error without flipping status repeatedly
        error = e.toString();
      }
    });
  }

  void stopAutoRefresh() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}