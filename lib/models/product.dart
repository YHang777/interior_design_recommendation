import 'package:flutter/foundation.dart';

class ProductDimensions {
  final double widthM;
  final double heightM;
  final double depthM;

  const ProductDimensions({
    this.widthM = 0,
    this.heightM = 0,
    this.depthM = 0,
  });

  bool get isComplete => widthM > 0 && heightM > 0 && depthM > 0;

  String get label => 'W ${_fmt(widthM)} × H ${_fmt(heightM)} × D ${_fmt(depthM)} m';

  static String _fmt(double v) {
    if (v <= 0) return '—';
    var s = v.toStringAsFixed(2);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = '${s}0';
    return s;
  }

  factory ProductDimensions.fromJson(Map<String, dynamic> json) =>
      ProductDimensions(
        widthM: (json['widthM'] is num) ? (json['widthM'] as num).toDouble() : 0,
        heightM:
            (json['heightM'] is num) ? (json['heightM'] as num).toDouble() : 0,
        depthM: (json['depthM'] is num) ? (json['depthM'] as num).toDouble() : 0,
      );

  Map<String, dynamic> toJson() =>
      {'widthM': widthM, 'heightM': heightM, 'depthM': depthM};

  @override
  bool operator ==(Object other) =>
      other is ProductDimensions &&
      other.widthM == widthM &&
      other.heightM == heightM &&
      other.depthM == depthM;

  @override
  int get hashCode => Object.hash(widthM, heightM, depthM);

  @override
  String toString() => 'ProductDimensions($label)';
}

class Ar3dInfo {
  final String status;

  final String source;

  final String url;

  final String error;

  final DateTime? generatedAt;

  final String taskId;

  final int attempts;

  final DateTime? submittedAt;

  const Ar3dInfo({
    this.status = 'none',
    this.source = '',
    this.url = '',
    this.error = '',
    this.generatedAt,
    this.taskId = '',
    this.attempts = 0,
    this.submittedAt,
  });

  bool get isReady => status == 'ready';
  bool get isNone => status == 'none';

  bool get hasTaskId => taskId.trim().isNotEmpty;

  Ar3dInfo copyWith({
    String? status,
    String? source,
    String? url,
    String? error,
    DateTime? generatedAt,
    String? taskId,
    int? attempts,
    DateTime? submittedAt,
  }) {
    return Ar3dInfo(
      status: status ?? this.status,
      source: source ?? this.source,
      url: url ?? this.url,
      error: error ?? this.error,
      generatedAt: generatedAt ?? this.generatedAt,
      taskId: taskId ?? this.taskId,
      attempts: attempts ?? this.attempts,
      submittedAt: submittedAt ?? this.submittedAt,
    );
  }

  factory Ar3dInfo.fromJson(Map<String, dynamic> json) => Ar3dInfo(
        status: json['status']?.toString() ?? 'none',
        source: json['source']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        error: json['error']?.toString() ?? '',
        generatedAt: _parseDate(json['generatedAt']),
        taskId: json['taskId']?.toString() ?? '',
        attempts: json['attempts'] is num
            ? ((json['attempts'] as num).toInt().clamp(0, 999)).toInt()
            : 0,
        submittedAt: _parseDate(json['submittedAt']),
      );

  Map<String, dynamic> toJson() => {
        'status': status,
        'source': source,
        'url': url,
        'error': error,
        'taskId': taskId,
        'attempts': attempts,
        if (generatedAt != null)
          'generatedAt': generatedAt!.toUtc().toIso8601String(),
        if (submittedAt != null)
          'submittedAt': submittedAt!.toUtc().toIso8601String(),
      };

  @override
  String toString() =>
      'Ar3dInfo(status: $status, source: $source, attempts: $attempts, '
      'taskId: "${taskId.isEmpty ? '' : taskId.substring(0, taskId.length < 8 ? taskId.length : 8)}")';
}

class ProductVision {
  final String status;

  final List<String> labels;

  final String visualCategory;

  final String visualStyle;

  final String summary;

  final bool mismatchFlagged;

  final String mismatchReason;

  final DateTime? analyzedAt;

  final String model;

  const ProductVision({
    this.status = 'failed',
    this.labels = const [],
    this.visualCategory = '',
    this.visualStyle = '',
    this.summary = '',
    this.mismatchFlagged = false,
    this.mismatchReason = '',
    this.analyzedAt,
    this.model = '',
  });

  bool get isOk => status == 'ok';

  factory ProductVision.fromJson(Map<String, dynamic> json) {
    final mismatch = json['mismatch'];
    return ProductVision(
      status: json['status']?.toString() ?? 'failed',
      labels: (json['labels'] as List<dynamic>?)
              ?.whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      visualCategory: json['visualCategory']?.toString() ?? '',
      visualStyle: json['visualStyle']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      mismatchFlagged: mismatch is Map && mismatch['flagged'] == true,
      mismatchReason:
          mismatch is Map ? mismatch['reason']?.toString() ?? '' : '',
      analyzedAt: _parseDate(json['analyzedAt']),
      model: json['model']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'labels': labels,
        'visualCategory': visualCategory,
        'visualStyle': visualStyle,
        'summary': summary,
        'mismatch': {'flagged': mismatchFlagged, 'reason': mismatchReason},
        if (analyzedAt != null) 'analyzedAt': analyzedAt!.toUtc().toIso8601String(),
        'model': model,
      };

  @override
  String toString() =>
      'ProductVision(status: $status, category: $visualCategory, '
      'mismatch: $mismatchFlagged)';
}

class Supplier {
  final String id;
  final String name;
  final String phone;
  final String address;
  final String email;
  final String verificationStatus;

  const Supplier({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.email,
    this.verificationStatus = 'none',
  });

  bool get isVerified => verificationStatus == 'verified';

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: json['id']?.toString() ??
            json['supplierId']?.toString() ??
            'unknown',
        name: json['name'] ?? json['supplierName'] ?? 'Unknown Supplier',
        phone: json['phone'] ?? '',
        address: json['address'] ?? '',
        email: json['email'] ?? '',
        verificationStatus: json['verificationStatus']?.toString() ??
            json['isVerified']?.toString() ??
            'none',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'email': email,
        'verificationStatus': verificationStatus,
      };
}

class Product {
  final String id;
  final String name;
  final int price;
  final int stock;
  final String image;
  final String description;
  final String designStyle;
  final String category;
  final Supplier supplier;

  final String supplierId;

  final List<String> images;

  final bool isActive;

  // ── Optional fields (defaults for backward compatibility) ──
  final double rating;
  final int ratingCount;
  final bool isEcoFriendly;
  final int? originalPrice;

  final DateTime? createdAt;

  final ProductDimensions? dimensions;

  final Ar3dInfo? ar3d;

  final ProductVision? vision;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    required this.image,
    required this.description,
    required this.designStyle,
    required this.category,
    required this.supplier,
    this.supplierId = '',
    this.images = const [],
    this.isActive = true,
    this.rating = 0.0,
    this.ratingCount = 0,
    this.isEcoFriendly = false,
    this.originalPrice,
    this.createdAt,
    this.dimensions,
    this.ar3d,
    this.vision,
  });

  // ─── Computed ──────────────────────────────────────────────────────────

  bool get isOutOfStock => stock <= 0;
  bool get isLowStock => stock > 0 && stock < 5;

  String get resolvedSupplierId =>
      supplierId.isNotEmpty ? supplierId : supplier.id;

  bool get hasNetworkImage => image.startsWith('http');

  List<String> get resolvedImages =>
      images.isNotEmpty ? images : [image];

  int? get discountPercent {
    if (originalPrice == null || originalPrice! <= price) return null;
    return ((originalPrice! - price) / originalPrice! * 100).round();
  }

  // ─── copyWith ──────────────────────────────────────────────────────────

  Product copyWith({
    String? id,
    String? name,
    int? price,
    int? stock,
    String? image,
    String? description,
    String? designStyle,
    String? category,
    Supplier? supplier,
    String? supplierId,
    List<String>? images,
    bool? isActive,
    double? rating,
    int? ratingCount,
    bool? isEcoFriendly,
    int? originalPrice,
    DateTime? createdAt,
    ProductDimensions? dimensions,
    Ar3dInfo? ar3d,
    ProductVision? vision,
    bool clearOriginalPrice = false,
    bool clearDimensions = false,
    bool clearAr3d = false,
    bool clearVision = false,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      image: image ?? this.image,
      description: description ?? this.description,
      designStyle: designStyle ?? this.designStyle,
      category: category ?? this.category,
      supplier: supplier ?? this.supplier,
      supplierId: supplierId ?? this.supplierId,
      images: images ?? this.images,
      isActive: isActive ?? this.isActive,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      isEcoFriendly: isEcoFriendly ?? this.isEcoFriendly,
      originalPrice:
          clearOriginalPrice ? null : (originalPrice ?? this.originalPrice),
      createdAt: createdAt ?? this.createdAt,
      dimensions:
          clearDimensions ? null : (dimensions ?? this.dimensions),
      ar3d: clearAr3d ? null : (ar3d ?? this.ar3d),
      vision: clearVision ? null : (vision ?? this.vision),
    );
  }

  // ─── JSON ──────────────────────────────────────────────────────────────

  factory Product.fromJson(Map<String, dynamic> json) {
    final supplier = json['supplier'] is Map<String, dynamic>
        ? Supplier.fromJson(json['supplier'] as Map<String, dynamic>)
        : Supplier(
            id: json['supplierId']?.toString() ?? 'unknown',
            name: json['supplierName'] ?? 'Unknown Supplier',
            phone: json['supplierPhone'] ?? '',
            address: json['supplierAddress'] ?? '',
            email: json['supplierEmail'] ?? '',
          );
    return Product(
      id: json['id']?.toString() ??
          json['productId']?.toString() ??
          json['sku']?.toString() ??
          UniqueKey().toString(),
      name: json['name'] ?? json['title'] ?? 'Unknown',
      price: (json['price'] is num)
          ? (json['price'] as num).round()
          : int.tryParse(json['price']?.toString() ?? '') ?? 0,
      stock: (json['stock'] is num)
          ? (json['stock'] as num).round()
          : int.tryParse(json['stock']?.toString() ?? '') ?? 0,
      image: json['image'] ?? json['imageUrl'] ?? '',
      description: json['description'] ?? '',
      designStyle: json['designStyle'] ?? json['style'] ?? 'Modern',
      category: json['category'] ?? 'Furniture',
      supplier: supplier,
      supplierId: json['supplierId']?.toString() ?? '',
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => e?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      isActive: json['isActive'] != false,
      rating: (json['rating'] is num)
          ? (json['rating'] as num).toDouble()
          : 0.0,
      ratingCount: (json['ratingCount'] is num)
          ? (json['ratingCount'] as num).round()
          : 0,
      isEcoFriendly: json['isEcoFriendly'] == true,
      originalPrice: (json['originalPrice'] is num)
          ? (json['originalPrice'] as num).round()
          : null,
      createdAt: _parseDate(json['createdAt']),
      dimensions: json['dimensions'] is Map<String, dynamic>
          ? ProductDimensions.fromJson(json['dimensions'] as Map<String, dynamic>)
          : null,
      ar3d: json['ar3d'] is Map<String, dynamic>
          ? Ar3dInfo.fromJson(json['ar3d'] as Map<String, dynamic>)
          : null,
      vision: json['vision'] is Map<String, dynamic>
          ? ProductVision.fromJson(json['vision'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'stock': stock,
        'image': image,
        'images': resolvedImages,
        'description': description,
        'designStyle': designStyle,
        'category': category,
        'supplier': supplier.toJson(),
        'supplierId': resolvedSupplierId,
        'isActive': isActive,
        'rating': rating,
        'ratingCount': ratingCount,
        'isEcoFriendly': isEcoFriendly,
        if (originalPrice != null) 'originalPrice': originalPrice,
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
        if (dimensions != null) 'dimensions': dimensions!.toJson(),
        if (ar3d != null) 'ar3d': ar3d!.toJson(),
      };
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  try {
    final toDate = value.toDate;
    if (toDate is Function) {
      final parsed = value.toDate();
      if (parsed is DateTime) return parsed;
    }
  } catch (_) {}
  return DateTime.tryParse(value.toString());
}

Map<String, dynamic> preserveStoredVision(
  Map<String, dynamic> json,
  Map<String, dynamic>? stored,
) {
  if (stored == null || stored['vision'] == null) return json;
  return {...json, 'vision': stored['vision']};
}
