import 'package:flutter/foundation.dart';

class Supplier {
  final String id;
  final String name;
  final String phone;
  final String address;
  final String email;

  const Supplier({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.email,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: json['id']?.toString() ?? json['supplierId']?.toString() ?? 'unknown',
        name: json['name'] ?? json['supplierName'] ?? 'Unknown Supplier',
        phone: json['phone'] ?? '',
        address: json['address'] ?? '',
        email: json['email'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'email': email,
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
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id']?.toString() ?? json['productId']?.toString() ?? json['sku']?.toString() ?? UniqueKey().toString(),
        name: json['name'] ?? json['title'] ?? 'Unknown',
        price: (json['price'] is num) ? (json['price'] as num).round() : int.tryParse(json['price']?.toString() ?? '') ?? 0,
        stock: (json['stock'] is num) ? (json['stock'] as num).round() : int.tryParse(json['stock']?.toString() ?? '') ?? 0,
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
      };
}