import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/product.dart';
import '../models/product_category.dart';
import '../models/order.dart';
import '../models/app_config_data.dart';

/// Full marketplace API contract.
abstract class MarketplaceService {
  // Products
  Future<List<Product>> fetchProducts();
  Future<Product> createProduct(Product product);
  Future<Product> updateProduct(String id, Product product);
  Future<void> deleteProduct(String id);

  // Categories (admin-managed)
  Future<List<ProductCategory>> fetchCategories();

  // Styles (admin-managed)
  Future<List<String>> fetchStyles();

  // Config
  Future<AppConfigData> fetchConfig();

  // Orders
  Future<List<Order>> fetchOrders();
  Future<Order> createOrder(Order order);
  Future<Order> updateOrderStatus(String orderId, String status);
  Future<void> deleteOrder(String orderId);
}

// ─── HTTP Implementation ─────────────────────────────────────────────────────

class HttpMarketplaceService implements MarketplaceService {
  static String get _baseUrl => AppConfig.marketplaceApiUrl;

  // ── Helpers ────────────────────────────────────────────────────────────

  Future<List<dynamic>> _getList(String path) async {
    if (_baseUrl.isEmpty) return [];
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        return decoded is List ? decoded : [];
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> _post(
      String path, Map<String, dynamic> body) async {
    if (_baseUrl.isEmpty) return null;
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final resp = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _put(
      String path, Map<String, dynamic> body) async {
    if (_baseUrl.isEmpty) return null;
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final resp = await http
          .put(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _delete(String path) async {
    if (_baseUrl.isEmpty) return false;
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final resp =
          await http.delete(uri).timeout(const Duration(seconds: 5));
      return resp.statusCode == 200 || resp.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  // ── Products ────────────────────────────────────────────────────────────

  @override
  Future<List<Product>> fetchProducts() async {
    if (_baseUrl.isEmpty) {
      return AssetMarketplaceService().fetchProducts();
    }
    final items = await _getList('/products');
    if (items.isEmpty) {
      return AssetMarketplaceService().fetchProducts();
    }
    return items
        .map<Product>((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Product> createProduct(Product product) async {
    final result = await _post('/products', product.toJson());
    if (result != null) return Product.fromJson(result);
    return AssetMarketplaceService().createProduct(product);
  }

  @override
  Future<Product> updateProduct(String id, Product product) async {
    final result = await _put('/products/$id', product.toJson());
    if (result != null) return Product.fromJson(result);
    return AssetMarketplaceService().updateProduct(id, product);
  }

  @override
  Future<void> deleteProduct(String id) async {
    final ok = await _delete('/products/$id');
    if (!ok) {
      return AssetMarketplaceService().deleteProduct(id);
    }
  }

  // ── Categories ─────────────────────────────────────────────────────────

  @override
  Future<List<ProductCategory>> fetchCategories() async {
    final items = await _getList('/categories?active=true');
    if (items.isNotEmpty) {
      return items
          .map<ProductCategory>(
              (e) => ProductCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    // Fallback
    return AssetMarketplaceService().fetchCategories();
  }

  // ── Styles ─────────────────────────────────────────────────────────────

  @override
  Future<List<String>> fetchStyles() async {
    final items = await _getList('/styles?active=true');
    if (items.isNotEmpty) {
      return items.map<String>((e) {
        final m = e as Map<String, dynamic>;
        return m['name']?.toString() ?? '';
      }).where((s) => s.isNotEmpty).toList();
    }
    return AssetMarketplaceService().fetchStyles();
  }

  // ── Config ─────────────────────────────────────────────────────────────

  @override
  Future<AppConfigData> fetchConfig() async {
    if (_baseUrl.isEmpty) {
      return AssetMarketplaceService().fetchConfig();
    }
    try {
      final uri = Uri.parse('$_baseUrl/config');
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        return AppConfigData.fromJson(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return AssetMarketplaceService().fetchConfig();
  }

  // ── Orders ─────────────────────────────────────────────────────────────

  @override
  Future<List<Order>> fetchOrders() async {
    final items = await _getList('/orders');
    if (items.isNotEmpty) {
      return items
          .map<Order>((e) => Order.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return AssetMarketplaceService().fetchOrders();
  }

  @override
  Future<Order> createOrder(Order order) async {
    final result = await _post('/orders', order.toJson());
    if (result != null) return Order.fromJson(result);
    return AssetMarketplaceService().createOrder(order);
  }

  @override
  Future<Order> updateOrderStatus(String orderId, String status) async {
    final result =
        await _put('/orders/$orderId', {'status': status});
    if (result != null) return Order.fromJson(result);
    return AssetMarketplaceService().updateOrderStatus(orderId, status);
  }

  @override
  Future<void> deleteOrder(String orderId) async {
    final ok = await _delete('/orders/$orderId');
    if (!ok) {
      return AssetMarketplaceService().deleteOrder(orderId);
    }
  }
}

// ─── Asset Fallback Implementation (dev-only, no server needed) ───────────────

class AssetMarketplaceService implements MarketplaceService {
  static const String _productsPath = 'assets/data/products.json';
  static List<Product>? _productsCache;
  static List<Order>? _ordersCache;
  static List<ProductCategory>? _categoriesCache;

  Future<void> _ensureProductsLoaded() async {
    if (_productsCache != null) return;
    final raw = await rootBundle.loadString(_productsPath);
    final decoded = jsonDecode(raw);
    final items =
        decoded is List ? decoded : (decoded['items'] as List);
    _productsCache = items
        .map<Product>((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _ensureOrdersSeeded() {
    _ordersCache ??= [];
  }

  void _ensureCategoriesSeeded() {
    _categoriesCache ??= [
      const ProductCategory(
          id: 'cat-furniture', name: 'Furniture', icon: 'chair'),
      const ProductCategory(
          id: 'cat-lighting', name: 'Lighting', icon: 'lightbulb'),
      const ProductCategory(
          id: 'cat-decor', name: 'Decor', icon: 'palette'),
      const ProductCategory(
          id: 'cat-paint', name: 'Paint', icon: 'format_paint'),
      const ProductCategory(
          id: 'cat-flooring', name: 'Flooring', icon: 'grid_on'),
      const ProductCategory(
          id: 'cat-textiles', name: 'Textiles', icon: 'style'),
      const ProductCategory(
          id: 'cat-wall-covering',
          name: 'Wall Covering',
          icon: 'wallpaper'),
    ];
  }

  // ── Products ────────────────────────────────────────────────────────────

  @override
  Future<List<Product>> fetchProducts() async {
    await _ensureProductsLoaded();
    return List<Product>.from(_productsCache!);
  }

  @override
  Future<Product> createProduct(Product product) async {
    await _ensureProductsLoaded();
    _productsCache!.add(product);
    return product;
  }

  @override
  Future<Product> updateProduct(String id, Product product) async {
    await _ensureProductsLoaded();
    final index = _productsCache!.indexWhere((p) => p.id == id);
    if (index == -1) throw Exception('Product not found: $id');
    _productsCache![index] = product;
    return product;
  }

  @override
  Future<void> deleteProduct(String id) async {
    await _ensureProductsLoaded();
    _productsCache!.removeWhere((p) => p.id == id);
  }

  // ── Categories ─────────────────────────────────────────────────────────

  @override
  Future<List<ProductCategory>> fetchCategories() async {
    _ensureCategoriesSeeded();
    return List<ProductCategory>.from(_categoriesCache!);
  }

  // ── Styles ─────────────────────────────────────────────────────────────

  @override
  Future<List<String>> fetchStyles() async {
    return ['Modern', 'Classic', 'Industrial', 'Scandinavian', 'Bohemian',
      'Minimalist'];
  }

  // ── Config ─────────────────────────────────────────────────────────────

  @override
  Future<AppConfigData> fetchConfig() async {
    return const AppConfigData(
      shippingFee: 25,
      freeShippingThreshold: 500,
      currency: 'MYR',
      taxRate: 0.06,
      membershipTiers: [
        MembershipTier(name: 'Free', discountPercent: 0, minOrders: 0),
        MembershipTier(name: 'Silver', discountPercent: 5, minOrders: 5),
        MembershipTier(name: 'Gold', discountPercent: 10, minOrders: 15),
      ],
    );
  }

  // ── Orders ─────────────────────────────────────────────────────────────

  @override
  Future<List<Order>> fetchOrders() async {
    _ensureOrdersSeeded();
    return List<Order>.from(_ordersCache!);
  }

  @override
  Future<Order> createOrder(Order order) async {
    _ensureOrdersSeeded();
    final id = order.id.isNotEmpty
        ? order.id
        : 'ord-${DateTime.now().millisecondsSinceEpoch}';
    final created = order.copyWith(id: id);
    _ordersCache!.insert(0, created);
    return created;
  }

  @override
  Future<Order> updateOrderStatus(String orderId, String status) async {
    _ensureOrdersSeeded();
    final index = _ordersCache!.indexWhere((o) => o.id == orderId);
    if (index == -1) throw Exception('Order not found: $orderId');
    final updated = _ordersCache![index].copyWith(
        status: OrderStatus.fromString(status));
    _ordersCache![index] = updated;
    return updated;
  }

  @override
  Future<void> deleteOrder(String orderId) async {
    _ensureOrdersSeeded();
    _ordersCache!.removeWhere((o) => o.id == orderId);
  }
}
