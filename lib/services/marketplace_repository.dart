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

/// Firestore-backed marketplace repository — the single source of truth for
/// products, orders, carts, wishlists and reviews.
///
/// Layout:
/// - `products`        (doc id = product id; `products/{id}/reviews` nested)
/// - `orders`
/// - `users/{uid}/cart/{productId}`      → {product: Product json, quantity}
/// - `users/{uid}/wishlist/{productId}`  → {productId, addedAt}
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

  /// Real-time snapshot of all products, newest first.
  Stream<List<Product>> watchProducts() {
    return _products
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Product.fromJson(d.data())).toList());
  }

  /// Creates a product. Never leaves the id empty (F1): an id is generated
  /// when the incoming product has none. Also stamps `createdAt` (F6),
  /// resolves `supplierId` and zeroes fabricated ratings on brand-new items.
  Future<Product> createProduct(Product p) async {
    final isNew = p.id.isEmpty;
    final id = isNew ? _newId() : p.id;
    final product = p.copyWith(
      id: id,
      supplierId: p.resolvedSupplierId,
      isActive: p.isActive,
      createdAt: p.createdAt ?? DateTime.now(),
      // F6: new products start at 0.0 rating / 0 count — never fabricate.
      rating: isNew ? 0.0 : p.rating,
      ratingCount: isNew ? 0 : p.ratingCount,
    );
    await _products.doc(id).set(product.toJson());
    return product;
  }

  /// Saves a seller's edits without clobbering concurrent activity:
  ///
  /// - The seller's intended stock CHANGE (`p.stock - originalStock`) is
  ///   applied to the CURRENT document stock (read inside the transaction),
  ///   so sales that land between the form being opened and the save are
  ///   preserved instead of being overwritten.
  /// - Server-side rating/ratingCount aggregates and the original
  ///   `createdAt` are always kept — callers cannot overwrite them.
  /// - [removedImageUrls] (network blobs the seller dropped from the
  ///   gallery) are deleted from Storage best-effort AFTER the doc write.
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
        // Editing a product must never clobber its auto-3D state: ar3d is
        // owned by the generation pipeline, so the LIVE document's record
        // (which a running Tripo poll may have advanced to 'ready' between
        // the form opening and this save) always wins over the form copy.
        ar3d: existing.ar3d,
      );
      txn.set(doc, updated.toJson());
      return updated;
    });
    if (removedImageUrls.isNotEmpty) {
      await _deleteRemoteImages(removedImageUrls);
    }
    return product;
  }

  /// Deletes a product and, best-effort, the remote media blobs behind its
  /// network images plus its 3D artifacts (the published model blob and the
  /// locally cached GLB). Blob failures are logged and swallowed: the
  /// document delete is authoritative. Note: Cloudinary unsigned uploads
  /// cannot be deleted client-side, so [MediaStore.deleteByUrl] is a no-op
  /// today — orphans are reclaimable from the Cloudinary console.
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

  /// Best-effort deletion for product image blobs.
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

  Future<AppConfigData> fetchConfig() async => _config;

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

  /// Generates a deterministic order id for idempotent re-submits. Callers
  /// that may re-try a placement (e.g. after an ambiguous network failure)
  /// must generate the id ONCE and reuse it, so a retried
  /// [createOrder] sees the already-committed document and returns it
  /// instead of charging/decrementing stock a second time.
  static String newOrderId() => _newId();

  /// Creates an order atomically: validates availability/stock inside a
  /// transaction and decrements stock per item (F1/F2-safe by design).
  ///
  /// Idempotent per [Order.id]: an order carrying a non-empty `id` whose
  /// document already exists (a previous attempt committed before the
  /// client noticed) is returned as-is — stock is NOT decremented again.
  /// Orders with an empty `id` fall back to a generated id.
  Future<Order> createOrder(Order order) async {
    final id = order.id.isNotEmpty ? order.id : _newId();
    final orderNumber =
        'ORD-${_dateStamp(DateTime.now())}-${_rng.nextInt(9000) + 1000}';
    final now = DateTime.now();

    return _db.runTransaction((txn) async {
      final doc = _orders.doc(id);

      // Idempotency check first: a doc with this id already exists when a
      // previous submit committed but its response was lost. Return it
      // without touching any stock.
      final existing = await txn.get(doc);
      if (existing.exists) {
        return Order.fromJson(existing.data()!);
      }

      // Phase 1 — read product docs to validate.
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
      // Phase 2 — apply writes.
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
        // New orders always start life in the Pending step.
        statusHistory: {OrderStatus.pending.name: now},
      );
      txn.set(doc, toWrite.toJson());
      return toWrite;
    });
  }

  /// One-shot fetch of a single order document; null when it does not exist.
  Future<Order?> fetchOrder(String orderId) async {
    if (orderId.isEmpty) return null;
    final snapshot = await _orders.doc(orderId).get();
    if (!snapshot.exists) return null;
    return Order.fromJson(snapshot.data()!);
  }

  /// Real-time stream of a single order document. Emits null while the
  /// document does not exist (e.g. deleted) so UI can render a fallback.
  Stream<Order?> watchOrder(String orderId) {
    return _orders.doc(orderId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return Order.fromJson(snapshot.data()!);
    });
  }

  /// Read-modify-write of the FULL order document (F2): never a partial
  /// `{'status': ...}` overwrite.
  ///
  /// Runs inside a transaction so concurrent status changes (e.g. two
  /// suppliers acting on the same order) cannot both win, and validates the
  /// transition against the CURRENT stored status:
  /// - terminal orders (delivered/cancelled) are immutable;
  /// - the requested status must be the exact next step of the stored
  ///   status — illegal jumps are rejected with a readable StateError.
  Future<Order> updateOrderStatus(String orderId, OrderStatus status) async {
    final doc = _orders.doc(orderId);
    return _db.runTransaction((txn) async {
      final snapshot = await txn.get(doc);
      if (!snapshot.exists) {
        throw StateError('Order not found: $orderId');
      }
      final now = DateTime.now();
      final current = Order.fromJson(snapshot.data()!);
      if (current.status.isTerminal) {
        throw StateError(
            'Order is already ${current.status.label.toLowerCase()}');
      }
      final expected = current.status.next;
      if (expected == null || expected != status) {
        throw StateError('Cannot move from ${current.status.label} '
            'to ${status.label}');
      }
      final updated = current.copyWith(
        status: status,
        // Record when this step was reached so timelines can date each stage.
        statusHistory: {...current.statusHistory, status.name: now},
      );
      txn.set(doc, updated.toJson());
      return updated;
    });
  }

  /// Cancels an order and restores stock for every item, atomically.
  Future<Order> cancelOrder(String orderId) async {
    return _db.runTransaction((txn) async {
      final orderRef = _orders.doc(orderId);
      final orderSnap = await txn.get(orderRef);
      if (!orderSnap.exists) {
        throw StateError('Order not found: $orderId');
      }
      final order = Order.fromJson(orderSnap.data()!);
      if (order.status == OrderStatus.cancelled) return order;
      if (order.status.isTerminal) {
        throw StateError(
            'A ${order.status.label.toLowerCase()} order cannot be cancelled.');
      }

      final productRefs = <String, DocumentReference<Map<String, dynamic>>>{};
      for (final item in order.items) {
        productRefs[item.productId] = _products.doc(item.productId);
      }
      // Read products before writing anything.
      final productSnaps =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in productRefs.entries) {
        productSnaps[entry.key] = await txn.get(entry.value);
      }
      // Restore stock (skip items whose product has since been deleted).
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
      txn.set(orderRef, updated.toJson());
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

  /// Adds a review and updates the product's rolling rating atomically.
  ///
  /// When [Review.id] is non-empty it is used as the review DOCUMENT id —
  /// callers in the order flow set `review.id = orderId` so a buyer can
  /// review each product of an order at most once, and "has this order
  /// reviewed product X?" becomes a cheap doc read (see
  /// [fetchReviewForOrder]). Empty ids fall back to a generated id (standalone
  /// reviews not tied to an order).
  Future<void> addReview(String productId, Review review) async {
    await _db.runTransaction((txn) async {
      final productRef = _products.doc(productId);
      final productSnap = await txn.get(productRef);
      if (!productSnap.exists) {
        throw StateError('Product not found: $productId');
      }

      // Order-tied reviews use the ORDER id as their review document id. If
      // that document already exists this (product, order) pair has been
      // reviewed — abort BEFORE the aggregate update so a retried submit can
      // never double-count the rating.
      if (review.id.isNotEmpty) {
        final reviewDoc = _reviews(productId).doc(review.id);
        final reviewSnap = await txn.get(reviewDoc);
        if (reviewSnap.exists) {
          throw StateError('This order has already been reviewed.');
        }
      }

      final product = Product.fromJson(productSnap.data()!);
      final count = product.ratingCount + 1;
      final total = product.rating * product.ratingCount + review.rating;
      final newRating = (total / count * 10).roundToDouble() / 10;

      final reviewDoc =
          _reviews(productId).doc(review.id.isEmpty ? _newId() : review.id);
      txn.set(reviewDoc, review.toJson());
      txn.update(productRef, {
        'rating': newRating,
        'ratingCount': count,
      });
    });
  }

  /// Whether/how the buyer of [orderId] has reviewed [productId].
  ///
  /// Review docs written through the order flow carry the ORDER id as their
  /// document id (see [addReview]), so this is a direct document read on
  /// `products/{productId}/reviews/{orderId}` rather than a query. Returns
  /// null when the product has not been reviewed within this order yet.
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

  /// One-time bootstrap: seeds the products collection from
  /// assets/data/products.json when it is empty. Never overwrites data.
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
        rating: (json['rating'] as num?)?.toDouble() ?? 4.5,
        ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 12,
        // Stagger createdAt so "Newest" ordering is meaningful at boot.
        createdAt: now.subtract(Duration(days: 3 * i)),
      );
      batch.set(_products.doc(id), product.toJson());
    }
    await batch.commit();
  }

  /// Backfills products whose embedded `supplier.verificationStatus` is the
  /// legacy `'pending'` value (written before supplier verification existed).
  /// Such listings would otherwise stay hidden behind the buyer
  /// "Verified sellers only" filter, which defaults to ON. Promotes them to
  /// `'verified'` in one batched write; returns the number of products
  /// updated. Best-effort: requires a signed-in session (Firestore rules
  /// gate writes), so failures are the caller's to log.
  Future<int> migrateLegacyProducts() async {
    final snap = await _products
        .where('supplier.verificationStatus', isEqualTo: 'pending')
        .get();
    if (snap.docs.isEmpty) return 0;

    final batch = _db.batch();
    for (final doc in snap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      final supplier = Map<String, dynamic>.from(
          data['supplier'] as Map<String, dynamic>? ?? const {});
      supplier['verificationStatus'] = 'verified';
      batch.update(doc.reference, {'supplier': supplier});
    }
    await batch.commit();
    return snap.docs.length;
  }

  static String _dateStamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }
}
