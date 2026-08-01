/// A product category managed by admin via the server API.
class ProductCategory {
  final String id;
  final String name;
  final String icon;
  final bool active;

  const ProductCategory({
    required this.id,
    required this.name,
    required this.icon,
    this.active = true,
  });

  factory ProductCategory.fromJson(Map<String, dynamic> json) {
    return ProductCategory(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      icon: json['icon']?.toString() ?? 'category',
      active: json['active'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'active': active,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ProductCategory && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
