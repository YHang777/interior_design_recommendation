import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/product.dart';

abstract class MarketplaceService {
  Future<List<Product>> fetchProducts();
  Future<Product> createProduct(Product product);
  Future<Product> updateProduct(String id, Product product);
  Future<void> deleteProduct(String id);
}

class HttpMarketplaceService implements MarketplaceService {
  static final String _apiUrl = AppConfig.marketplaceApiUrl;

  @override
  Future<List<Product>> fetchProducts() async {
    if (_apiUrl.isEmpty) {
      // No API configured; fall back to assets
      return AssetMarketplaceService().fetchProducts();
    }
    final uri = Uri.parse(_apiUrl);
    http.Response resp;
    try {
      resp = await http.get(uri);
    } catch (_) {
      // Network/connection error: fall back to assets for seamless dev use
      return AssetMarketplaceService().fetchProducts();
    }
    if (resp.statusCode != 200) {
      // Fallback to assets if server error
      return AssetMarketplaceService().fetchProducts();
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is List) {
      return decoded.map<Product>((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (decoded is Map<String, dynamic> && decoded['items'] is List) {
      final items = decoded['items'] as List;
      return items.map<Product>((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
    }
    // Unknown shape; fallback
    return AssetMarketplaceService().fetchProducts();
  }

  @override
  Future<Product> createProduct(Product product) async {
    if (_apiUrl.isEmpty) {
      return AssetMarketplaceService().createProduct(product);
    }
    final uri = Uri.parse(_apiUrl);
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(product.toJson()),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      // Surface errors when API is configured
      throw Exception('Failed to create product (${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) {
      return Product.fromJson(decoded);
    }
    throw Exception('Unexpected response when creating product');
  }

  @override
  Future<Product> updateProduct(String id, Product product) async {
    if (_apiUrl.isEmpty) {
      return AssetMarketplaceService().updateProduct(id, product);
    }
    final uri = Uri.parse('$_apiUrl/$id');
    final resp = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(product.toJson()),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to update product (${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) {
      return Product.fromJson(decoded);
    }
    throw Exception('Unexpected response when updating product');
  }

  @override
  Future<void> deleteProduct(String id) async {
    if (_apiUrl.isEmpty) {
      return AssetMarketplaceService().deleteProduct(id);
    }
    final uri = Uri.parse('$_apiUrl/$id');
    final resp = await http.delete(uri);
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception('Failed to delete product (${resp.statusCode})');
    }
  }
}

class AssetMarketplaceService implements MarketplaceService {
  static const String _assetPath = 'assets/data/products.json';
  static List<Product>? _cache;

  Future<void> _ensureCacheLoaded() async {
    if (_cache != null) return;
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw);
    final items = decoded is List ? decoded : (decoded['items'] as List);
    _cache = items.map<Product>((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<Product>> fetchProducts() async {
    await _ensureCacheLoaded();
    return List<Product>.from(_cache!);
  }

  @override
  Future<Product> createProduct(Product product) async {
    await _ensureCacheLoaded();
    _cache!.add(product);
    return product;
  }

  @override
  Future<Product> updateProduct(String id, Product product) async {
    await _ensureCacheLoaded();
    final index = _cache!.indexWhere((p) => p.id == id);
    if (index == -1) {
      throw Exception('Product not found for update: $id');
    }
    _cache![index] = product;
    return product;
  }

  @override
  Future<void> deleteProduct(String id) async {
    await _ensureCacheLoaded();
    _cache!.removeWhere((p) => p.id == id);
  }
}