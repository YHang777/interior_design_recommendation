import 'package:flutter/foundation.dart';

class Supplier {
  final String id;
  final String name;
  final String phone;
  final String address;
  final String email;
  final String verificationStatus; // 'verified', 'pending', 'rejected'

  const Supplier({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.email,
    this.verificationStatus = 'verified',
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
            'verified',
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

  // ── New optional fields (all have defaults for backward compatibility) ──
  final double rating;
  final int ratingCount;
  final bool isEcoFriendly;
  final int? originalPrice;
  final DateTime? createdAt;

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
    this.rating = 4.5,
    this.ratingCount = 12,
    this.isEcoFriendly = false,
    this.originalPrice,
    this.createdAt,
  });

  // ─── Computed ──────────────────────────────────────────────────────────

  bool get isOutOfStock => stock <= 0;
  bool get isLowStock => stock > 0 && stock < 5;

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
    double? rating,
    int? ratingCount,
    bool? isEcoFriendly,
    int? originalPrice,
    DateTime? createdAt,
    bool clearOriginalPrice = false,
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
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      isEcoFriendly: isEcoFriendly ?? this.isEcoFriendly,
      originalPrice:
          clearOriginalPrice ? null : (originalPrice ?? this.originalPrice),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ─── JSON ──────────────────────────────────────────────────────────────

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id']?.toString() ??
            json['productId']?.toString() ??
            json['sku']?.toString() ??
            UniqueKey().toString(),
        name:
            json['name'] ?? json['title'] ?? 'Unknown',
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
        supplier: json['supplier'] is Map<String, dynamic>
            ? Supplier.fromJson(json['supplier'] as Map<String, dynamic>)
            : Supplier(
                id: json['supplierId']?.toString() ?? 'unknown',
                name: json['supplierName'] ?? 'Unknown Supplier',
                phone: json['supplierPhone'] ?? '',
                address: json['supplierAddress'] ?? '',
                email: json['supplierEmail'] ?? '',
              ),
        rating: (json['rating'] is num)
            ? (json['rating'] as num).toDouble()
            : 4.5,
        ratingCount: (json['ratingCount'] is num)
            ? (json['ratingCount'] as num).round()
            : 12,
        isEcoFriendly: json['isEcoFriendly'] == true,
        originalPrice: (json['originalPrice'] is num)
            ? (json['originalPrice'] as num).round()
            : null,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString())
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'stock': stock,
        'image': image,
        'description': description,
        'designStyle': designStyle,
        'category': category,
        'supplier': supplier.toJson(),
        'rating': rating,
        'ratingCount': ratingCount,
        'isEcoFriendly': isEcoFriendly,
        if (originalPrice != null) 'originalPrice': originalPrice,
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
      };
}
