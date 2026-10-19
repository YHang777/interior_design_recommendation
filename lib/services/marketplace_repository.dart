import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../models/app_config_data.dart';
import '../models/cart_item.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/product_category.dart';
import '../models/review.dart';
import 'media/media_store.dart';
import 'model_generation/model_glb_resolver.dart';

class MarketplaceRepository {
  MarketplaceRepository(this._db, {MediaStore? mediaStore})
      : _media = mediaStore ?? MediaStore.instance;

  final FirebaseFirestore _db;
  final MediaStore _media;
  static final Random _rng = Random();

  static const String _productsCol = 'products';
  static const String _ordersCol = 'orders';
  static const String _usersCol = 'users';

  // ── Static catalogue data (admin-managed; code constants for now) ───────

  static const List<String> _styleOptions = [
    'Modern',
    'Classic',
    'Industrial',
    'Scandinavian',
    'Bohemian',
    'Minimalist',
  ];

  static const List<ProductCategory> _categoryOptions = [
    ProductCategory(id: 'cat-furniture', name: 'Furniture', icon: 'chair'),
    ProductCategory(id: 'cat-lighting', name: 'Lighting', icon: 'lightbulb'),
    ProductCategory(id: 'cat-decor', name: 'Decor', icon: 'palette'),
    ProductCategory(id: 'cat-paint', name: 'Paint', icon: 'format_paint'),
    ProductCategory(id: 'cat-flooring', name: 'Flooring', icon: 'grid_on'),
    ProductCategory(id: 'cat-textiles', name: 'Textiles', icon: 'style'),
    ProductCategory(
        id: 'cat-wall-covering', name: 'Wall Covering', icon: 'wallpaper'),
  ];

  static const AppConfigData _config = AppConfigData(
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

  // ── Helpers ─────────────────────────────────────────────────────────────

  static String _newId() =>
      '${Timestamp.now().millisecondsSinceEpoch}${_rng.nextInt(99999)}';

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection(_productsCol);
  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection(_ordersCol);
  CollectionReference<Map<String, dynamic>> _userDocs(String uid) =>
      _db.collection(_usersCol).doc(uid).collection('cart');
  CollectionReference<Map<String, dynamic>> _userWishlist(String uid) =>
      _db.collection(_usersCol).doc(uid).collection('wishlist');
  CollectionReference<Map<String, dynamic>> _reviews(String productId) =>
      _products.doc(productId).collection('reviews');

  static String _isoNow() => DateTime.now().toUtc().toIso8601String();

  // ── Products ────────────────────────────────────────────────────────────

  Stream<List<Product>> watchProducts() {
    return _products.snapshots().map((snap) {
      final products = <Product>[];
      for (final doc in snap.docs) {
        try {
          products.add(Product.fromJson(doc.data()));
        } catch (e) {
          debugPrint('[products] skipped unparsable doc ${doc.id}: $e');
        }
      }
      products.sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));
      return products;
    });
  }

  Future<Product> createProduct(Product p) async {
    final isNew = p.id.isEmpty;
    final id = isNew ? _newId() : p.id;
    final product = p.copyWith(
      id: id,
      supplierId: p.resolvedSupplierId,
      isActive: p.isActive,
      createdAt: p.createdAt ?? DateTime.now(),
      rating: isNew ? 0.0 : p.rating,
      ratingCount: isNew ? 0 : p.ratingCount,
    );
    await _products.doc(id).set(product.toJson());
    return product;
  }

  Future<Product> updateProduct(
    Product p, {
    required int originalStock,
    List<String> removedImageUrls = const [],
  }) async {
    if (p.id.isEmpty) {
      throw StateError('Cannot update a product without an id.');
    }
    final doc = _products.doc(p.id);
    final product = await _db.runTransaction((txn) async {
      final snapshot = await txn.get(doc);
      if (!snapshot.exists) {
        throw StateError('Product not found: ${p.id}');
      }
      final existing = Product.fromJson(snapshot.data()!);
      final stockDelta = p.stock - originalStock;
      final updated = p.copyWith(
        stock: max(0, existing.stock + stockDelta),
        rating: existing.rating,
        ratingCount: existing.ratingCount,
        supplierId: p.resolvedSupplierId,
        createdAt: p.createdAt ?? existing.createdAt,
        ar3d: existing.ar3d,
      );
      txn.set(doc, preserveStoredVision(updated.toJson(), snapshot.data()));
      return updated;
    });
    if (removedImageUrls.isNotEmpty) {
      await _deleteRemoteImages(removedImageUrls);
    }
    return product;
  }

  Future<void> deleteProduct(String id) async {
    final snapshot = await _products.doc(id).get();
    if (snapshot.exists) {
      final product = Product.fromJson(snapshot.data()!);
      final networkImages = product.resolvedImages
          .where((url) => url.startsWith('http'))
          .toList();
      final modelUrl = product.ar3d?.url ?? '';
      await _products.doc(id).delete();
      if (networkImages.isNotEmpty) {
        await _deleteRemoteImages(networkImages);
      }
      if (modelUrl.isNotEmpty) {
        await _deleteRemoteBlob(modelUrl);
      }
    }
    await ModelGlbResolver.pruneCacheForProduct(id);
  }

  Future<void> _deleteRemoteImages(List<String> urls) async {
    for (final url in urls) {
      await _deleteRemoteBlob(url);
    }
  }

  Future<void> _deleteRemoteBlob(String url) async {
    try {
      await _media.deleteByUrl(url);
    } catch (e) {
      debugPrint('[media] could not delete $url: $e');
    }
  }

  Future<void> setProductActive(String id, bool active) async {
    await _products.doc(id).update({'isActive': active});
  }

  // ── Static catalogue ────────────────────────────────────────────────────

  Future<List<String>> fetchStyles() async => List.of(_styleOptions);

  Future<List<ProductCategory>> fetchCategories() async =>
      List.of(_categoryOptions);

  Future<AppConfigData> fetchConfig() async {
    try {
      final snap = await _db.collection('appConfig').doc('marketplace').get();
      final rate = snap.data()?['taxRate'];
      if (rate is num && rate >= 0 && rate <= 1) {
        return _config.copyWith(taxRate: rate.toDouble());
      }
    } catch (_) {
      // Offline, rules-denied or missing doc → hardcoded defaults.
    }
    return _config;
  }

  // ── Orders ──────────────────────────────────────────────────────────────

  Stream<List<Order>> watchCustomerOrders(String uid) {
    return _orders
        .where('customerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Order.fromJson(d.data())).toList());
  }

  Stream<List<Order>> watchSupplierOrders(String supplierId) {
    return _orders
        .where('supplierIds', arrayContains: supplierId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Order.fromJson(d.data())).toList());
  }

  static String newOrderId() => _newId();

  Future<Order> createOrder(Order order) async {
    final id = order.id.isNotEmpty ? order.id : _newId();
    final orderNumber =
        'ORD-${_dateStamp(DateTime.now())}-${_rng.nextInt(9000) + 1000}';
    final now = DateTime.now();

    return _db.runTransaction((txn) async {
      final doc = _orders.doc(id);

      final existing = await txn.get(doc);
      if (existing.exists) {
        return Order.fromJson(existing.data()!);
      }

      final productDocs = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final item in order.items) {
        final ref = _products.doc(item.productId);
        final snapshot = await txn.get(ref);
        productDocs[item.productId] = snapshot;
        if (!snapshot.exists) {
          throw StateError('"${item.name}" is no longer available.');
        }
        final product = Product.fromJson(snapshot.data()!);
        if (!product.isActive) {
          throw StateError('"${product.name}" is no longer on sale.');
        }
        if (product.stock < item.quantity) {
          throw StateError(
              'Insufficient stock for "${product.name}" '
              '(only ${product.stock} left).');
        }
      }
      productDocs.forEach((productId, snapshot) {
        final product = Product.fromJson(snapshot.data()!);
        final item = order.items.firstWhere((i) => i.productId == productId);
        txn.update(
            _products.doc(productId), {'stock': product.stock - item.quantity});
      });

      final toWrite = order.copyWith(
        id: id,
        orderNumber: orderNumber,
        createdAt: now,
        statusHistory: {OrderStatus.pending.name: now},
      );
      txn.set(doc, toWrite.toJson());
      return toWrite;
    });
  }

  Future<Order?> fetchOrder(String orderId) async {
    if (orderId.isEmpty) return null;
    final snapshot = await _orders.doc(orderId).get();
    if (!snapshot.exists) return null;
    return Order.fromJson(snapshot.data()!);
  }

  Stream<Order?> watchOrder(String orderId) {
    return _orders.doc(orderId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return Order.fromJson(snapshot.data()!);
    });
  }

  Future<Order> updateOrderStatus(String orderId, OrderStatus status) async {
    final doc = _orders.doc(orderId);
    return _db.runTransaction((txn) async {
      final snapshot = await txn.get(doc);
      if (!snapshot.exists) {
        throw StateError('Order not found: $orderId');
      }
      final now = DateTime.now();
      final current = Order.fromJson(snapshot.data()!);
      OrderStatus.ensureAdvance(current.status, status);
      final updated = current.copyWith(
        status: status,
        statusHistory: {...current.statusHistory, status.name: now},
      );
      txn.set(doc, preserveStoredInvoices(updated.toJson(), snapshot.data()!));
      return updated;
    });
  }

  Future<OrderInvoice> acceptOrderAndIssueInvoice({
    required String orderId,
    required String supplierId,
    required String supplierName,
    String supplierPhone = '',
    String supplierAddress = '',
    String supplierEmail = '',
  }) async {
    final doc = _orders.doc(orderId);
    return _db.runTransaction((txn) async {
      final snapshot = await txn.get(doc);
      if (!snapshot.exists) {
        throw StateError('Order not found');
      }
      final now = DateTime.now();
      final order = Order.fromJson(snapshot.data()!);

      final existing = order.invoiceFor(supplierId);
      if (existing != null) return existing;

      if (order.status.isTerminal) {
        throw StateError(
            'A ${order.status.label.toLowerCase()} order cannot be accepted.');
      }

      final invoice = OrderInvoice.issue(
        order: order,
        supplierId: supplierId,
        supplierName: supplierName,
        supplierPhone: supplierPhone,
        supplierAddress: supplierAddress,
        supplierEmail: supplierEmail,
      );

      final accepts = order.status == OrderStatus.pending;
      final invoices = {...order.invoices, supplierId: invoice};
      final updated = accepts
          ? order.copyWith(
              status: OrderStatus.confirmed,
              statusHistory:
                  {...order.statusHistory, OrderStatus.confirmed.name: now},
              invoices: invoices,
            )
          : order.copyWith(invoices: invoices);
      txn.set(doc, updated.toJson());
      return invoice;
    });
  }

  Future<Order> cancelOrder(String orderId) async {
    return _db.runTransaction((txn) async {
      final orderRef = _orders.doc(orderId);
      final orderSnap = await txn.get(orderRef);
      if (!orderSnap.exists) {
        throw StateError('Order not found: $orderId');
      }
      final order = Order.fromJson(orderSnap.data()!);
      if (order.status == OrderStatus.cancelled) return order;
      OrderStatus.ensureCancellable(order.status);

      final productRefs = <String, DocumentReference<Map<String, dynamic>>>{};
      for (final item in order.items) {
        productRefs[item.productId] = _products.doc(item.productId);
      }
      final productSnaps =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in productRefs.entries) {
        productSnaps[entry.key] = await txn.get(entry.value);
      }
      for (final entry in productSnaps.entries) {
        final snap = entry.value;
        if (!snap.exists) continue;
        final product = Product.fromJson(snap.data()!);
        final item = order.items.firstWhere((i) => i.productId == entry.key);
        txn.update(entry.value.reference,
            {'stock': product.stock + item.quantity});
      }

      final now = DateTime.now();
      final updated = order.copyWith(
        status: OrderStatus.cancelled,
        statusHistory: {...order.statusHistory, OrderStatus.cancelled.name: now},
      );
      txn.set(orderRef, preserveStoredInvoices(updated.toJson(), orderSnap.data()!));
      return updated;
    });
  }

  // ── Cart ────────────────────────────────────────────────────────────────

  Stream<List<CartItem>> watchCart(String uid) {
    return _userDocs(uid).snapshots().map((snap) => snap.docs
        .map((d) => CartItem.fromJson(d.data()))
        .toList());
  }

  Future<void> saveCartItem(String uid, CartItem item) async {
    await _userDocs(uid).doc(item.product.id).set(item.toJson());
  }

  Future<void> removeCartItem(String uid, String productId) async {
    await _userDocs(uid).doc(productId).delete();
  }

  Future<void> clearCart(String uid) async {
    final snap = await _userDocs(uid).get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  // ── Wishlist ────────────────────────────────────────────────────────────

  Stream<List<String>> watchWishlistIds(String uid) {
    return _userWishlist(uid)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toList());
  }

  Future<void> addToWishlist(String uid, String productId) async {
    await _userWishlist(uid).doc(productId).set({
      'productId': productId,
      'addedAt': _isoNow(),
    });
  }

  Future<void> removeFromWishlist(String uid, String productId) async {
    await _userWishlist(uid).doc(productId).delete();
  }

  // ── Reviews ─────────────────────────────────────────────────────────────

  Stream<List<Review>> watchReviews(String productId) {
    return _reviews(productId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Review.fromJson(d.data())).toList());
  }

  Future<void> addReview(String productId, Review review) async {
    await _db.runTransaction((txn) async {
      final productRef = _products.doc(productId);
      final productSnap = await txn.get(productRef);
      if (!productSnap.exists) {
        throw StateError('Product not found: $productId');
      }

      if (review.id.isNotEmpty) {
        final reviewDoc = _reviews(productId).doc(review.id);
        final reviewSnap = await txn.get(reviewDoc);
        if (reviewSnap.exists) {
          throw StateError('This order has already been reviewed.');
        }
      }

      final product = Product.fromJson(productSnap.data()!);
      final count = product.ratingCount + 1;
      final newRating = rollingRating(
        ratingCount: product.ratingCount,
        rating: product.rating,
        added: review.rating,
      );

      final reviewDoc =
          _reviews(productId).doc(review.id.isEmpty ? _newId() : review.id);
      txn.set(reviewDoc, review.toJson());
      txn.update(productRef, {
        'rating': newRating,
        'ratingCount': count,
      });
    });
  }

  Future<Review?> fetchReviewForOrder(String productId, String orderId) async {
    if (productId.isEmpty || orderId.isEmpty) return null;
    final snapshot = await _reviews(productId).doc(orderId).get();
    if (!snapshot.exists) return null;
    return Review.fromJson(snapshot.data()!);
  }

  // ── Seeding ─────────────────────────────────────────────────────────────

  Future<int> getProductCount() async {
    final snap = await _products.count().get();
    return snap.count ?? 0;
  }

  Future<void> seedMarketplaceIfEmpty() async {
    final count = await getProductCount();
    if (count > 0) return;

    final raw = await rootBundle.loadString('assets/data/products.json');
    final decoded = jsonDecode(raw);
    final items =
        decoded is List ? decoded : (decoded['items'] as List<dynamic>);
    final now = DateTime.now().toUtc();

    final batch = _db.batch();
    for (var i = 0; i < items.length; i++) {
      final json = items[i] as Map<String, dynamic>;
      final existingId = json['id']?.toString() ?? '';
      final id = existingId.isNotEmpty ? existingId : _newId();
      final product = Product.fromJson(json).copyWith(
        id: id,
        supplierId: (json['supplier'] as Map<String, dynamic>?)?['id']
                ?.toString() ??
            '',
        images: [json['image']?.toString() ?? ''],
        isActive: true,
        rating: 0.0,
        ratingCount: 0,
        createdAt: now.subtract(Duration(days: 3 * i)),
      );
      batch.set(_products.doc(id), product.toJson());
    }
    await batch.commit();
  }

  Future<int> backfillRatingsFromReviews() async {
    final products = await _products.get();
    var batch = _db.batch();
    var staged = 0;
    var repaired = 0;
    for (final doc in products.docs) {
      final stored = doc.data();
      final reviews = await _reviews(doc.id).get();
      final target = aggregateForRatings([
        for (final review in reviews.docs) Review.fromJson(review.data()).rating,
      ]);
      final currentRating = (stored['rating'] as num?)?.toDouble() ?? 0.0;
      final currentCount = (stored['ratingCount'] as num?)?.toInt() ?? 0;
      if (currentRating == target.rating &&
          currentCount == target.ratingCount) {
        continue;
      }
      batch.update(doc.reference, {
        'rating': target.rating,
        'ratingCount': target.ratingCount,
      });
      repaired++;
      staged++;
      if (staged == 400) {
        await batch.commit();
        batch = _db.batch();
        staged = 0;
      }
    }
    if (staged > 0) await batch.commit();
    return repaired;
  }

  static String _dateStamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }
}
