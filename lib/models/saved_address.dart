class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.label,
    required this.recipientName,
    required this.phone,
    required this.address,
    this.isDefault = false,
    required this.createdAt,
  });

  final String id;
  final String label;
  final String recipientName;
  final String phone;
  final String address;
  final bool isDefault;
  final DateTime createdAt;

  SavedAddress copyWith({
    String? id,
    String? label,
    String? recipientName,
    String? phone,
    String? address,
    bool? isDefault,
    DateTime? createdAt,
  }) {
    return SavedAddress(
      id: id ?? this.id,
      label: label ?? this.label,
      recipientName: recipientName ?? this.recipientName,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'recipientName': recipientName,
        'phone': phone,
        'address': address,
        'isDefault': isDefault,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedAddress.fromJson(Map<String, dynamic> json) {
    return SavedAddress(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? 'Address',
      recipientName: json['recipientName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      address: json['address'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
