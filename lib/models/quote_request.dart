class QuoteRequest {
  const QuoteRequest({
    required this.id,
    required this.productId,
    required this.productName,
    this.productImage,
    required this.supplierId,
    required this.customerId,
    required this.customerName,
    required this.customerEmail,
    required this.customerPhone,
    required this.quantity,
    this.note = '',
    this.status = statusSubmitted,
    required this.createdAt,
    this.contactedAt,
  });

  static const String statusSubmitted = 'submitted';
  static const String statusContacted = 'contacted';

  final String id;
  final String productId;
  final String productName;
  final String? productImage;
  final String supplierId;
  final String customerId;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final int quantity;
  final String note;
  final String status;
  final DateTime createdAt;
  final DateTime? contactedAt;

  bool get isContacted => status == statusContacted;

  factory QuoteRequest.fromJson(Map<String, dynamic> json) {
    return QuoteRequest(
      id: json['id']?.toString() ?? '',
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? '',
      productImage: json['productImage']?.toString(),
      supplierId: json['supplierId']?.toString() ?? '',
      customerId: json['customerId']?.toString() ?? '',
      customerName: json['customerName']?.toString() ?? '',
      customerEmail: json['customerEmail']?.toString() ?? '',
      customerPhone: json['customerPhone']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      note: json['note']?.toString() ?? '',
      status: json['status']?.toString() ?? statusSubmitted,
      createdAt: json['createdAt'] != null
          ? _parseQuoteDate(json['createdAt']) ?? DateTime.now()
          : DateTime.now(),
      contactedAt: json['contactedAt'] != null
          ? _parseQuoteDate(json['contactedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'productName': productName,
        'productImage': productImage,
        'supplierId': supplierId,
        'customerId': customerId,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'customerPhone': customerPhone,
        'quantity': quantity,
        'note': note,
        'status': status,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (contactedAt != null)
          'contactedAt': contactedAt!.toUtc().toIso8601String(),
      };
}

// Firestore hands back Timestamps on reads, ISO strings on writes — accept both.
DateTime? _parseQuoteDate(dynamic value) {
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
