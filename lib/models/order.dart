/// Order statuses following e-commerce lifecycle.
enum OrderStatus {
  pending,
  confirmed,
  shipped,
  delivered,
  cancelled;

  String get label => switch (this) {
        OrderStatus.pending => 'Pending',
        OrderStatus.confirmed => 'Confirmed',
        OrderStatus.shipped => 'Shipped',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.cancelled => 'Cancelled',
      };

  OrderStatus? get next => switch (this) {
        OrderStatus.pending => OrderStatus.confirmed,
        OrderStatus.confirmed => OrderStatus.shipped,
        OrderStatus.shipped => OrderStatus.delivered,
        _ => null,
      };

  bool get isTerminal =>
      this == OrderStatus.delivered || this == OrderStatus.cancelled;

  static OrderStatus fromString(String s) {
    return OrderStatus.values.firstWhere(
      (e) => e.name == s.toLowerCase(),
      orElse: () => OrderStatus.pending,
    );
  }
}

/// Possible refund states on an order.
enum RefundStatus {
  requested,
  approved,
  rejected,
  processed;

  String get label => switch (this) {
        RefundStatus.requested => 'Refund Requested',
        RefundStatus.approved => 'Refund Approved',
        RefundStatus.rejected => 'Refund Rejected',
        RefundStatus.processed => 'Refund Processed',
      };

  static RefundStatus? fromString(String? s) {
    if (s == null) return null;
    return RefundStatus.values.firstWhere(
      (e) => e.name == s.toLowerCase(),
      orElse: () => RefundStatus.requested,
    );
  }
}

/// Snapshot of a product at purchase time — frozen so price changes don't
/// affect historical orders.
class OrderItem {
  final String productId;
  final String name;
  final String image;
  final int unitPrice;
  final int quantity;
  final String supplierId;

  const OrderItem({
    required this.productId,
    required this.name,
    required this.image,
    required this.unitPrice,
    required this.quantity,
    required this.supplierId,
  });

  int get lineTotal => unitPrice * quantity;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      productId: json['productId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Product',
      image: json['image']?.toString() ?? '',
      unitPrice: (json['unitPrice'] as num?)?.toInt() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      supplierId: json['supplierId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'image': image,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'supplierId': supplierId,
      };
}

/// A complete order placed by a buyer, fulfilled by supplier(s).
class Order {
  final String id;
  final String orderNumber;
  final String customerId;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final String shippingAddress;
  final List<OrderItem> items;
  final OrderStatus status;
  final String paymentMethod;
  final int subtotal;
  final int shippingFee;
  final int total;

  /// Membership discount (whole ringgit) applied at checkout.
  final int discount;

  /// Sales tax (whole ringgit) applied at checkout.
  final int tax;

  /// Membership tier the customer held at purchase time (Free/Silver/Gold).
  final String membershipTier;

  /// Supplier uids fulfilled by this order. Derives from items when empty.
  final List<String> supplierIds;

  final DateTime createdAt;

  /// Timestamp per status transition — map key is the [OrderStatus] name
  /// ('pending', 'confirmed', …), value the moment the order reached it.
  /// Enables per-step dates in the buyer/supplier status timelines.
  final Map<String, DateTime> statusHistory;

  final RefundStatus? refundStatus;
  final String? refundReason;
  final int? refundAmount;

  const Order({
    required this.id,
    required this.orderNumber,
    required this.customerId,
    required this.customerName,
    required this.customerEmail,
    required this.customerPhone,
    required this.shippingAddress,
    required this.items,
    required this.status,
    required this.paymentMethod,
    required this.subtotal,
    required this.shippingFee,
    required this.total,
    required this.createdAt,
    this.discount = 0,
    this.tax = 0,
    this.membershipTier = '',
    this.supplierIds = const [],
    this.statusHistory = const {},
    this.refundStatus,
    this.refundReason,
    this.refundAmount,
  });

  String get paymentMethodLabel => switch (paymentMethod) {
        'fpx' => 'FPX Online Banking',
        'card' => 'Credit / Debit Card',
        'card_fpx' => 'Card / FPX',
        'cod' => 'Cash on Delivery',
        'ewallet' => 'E-Wallet',
        _ => paymentMethod,
      };

  /// Supplier ids, deriving from item snapshots when none were recorded.
  List<String> get resolvedSupplierIds => supplierIds.isNotEmpty
      ? supplierIds
      : items
          .map((i) => i.supplierId)
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

  Order copyWith({
    String? id,
    String? orderNumber,
    String? customerId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? shippingAddress,
    List<OrderItem>? items,
    OrderStatus? status,
    String? paymentMethod,
    int? subtotal,
    int? shippingFee,
    int? total,
    int? discount,
    int? tax,
    String? membershipTier,
    List<String>? supplierIds,
    DateTime? createdAt,
    Map<String, DateTime>? statusHistory,
    RefundStatus? refundStatus,
    String? refundReason,
    int? refundAmount,
    bool clearRefund = false,
  }) {
    return Order(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerEmail: customerEmail ?? this.customerEmail,
      customerPhone: customerPhone ?? this.customerPhone,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      items: items ?? this.items,
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      subtotal: subtotal ?? this.subtotal,
      shippingFee: shippingFee ?? this.shippingFee,
      total: total ?? this.total,
      discount: discount ?? this.discount,
      tax: tax ?? this.tax,
      membershipTier: membershipTier ?? this.membershipTier,
      supplierIds: supplierIds ?? this.supplierIds,
      createdAt: createdAt ?? this.createdAt,
      statusHistory: statusHistory ?? this.statusHistory,
      refundStatus: clearRefund ? null : (refundStatus ?? this.refundStatus),
      refundReason: clearRefund ? null : (refundReason ?? this.refundReason),
      refundAmount: clearRefund ? null : (refundAmount ?? this.refundAmount),
    );
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>?)
            ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return Order(
      id: json['id']?.toString() ?? '',
      orderNumber: json['orderNumber']?.toString() ?? '',
      customerId: json['customerId']?.toString() ?? '',
      customerName: json['customerName']?.toString() ?? '',
      customerEmail: json['customerEmail']?.toString() ?? '',
      customerPhone: json['customerPhone']?.toString() ?? '',
      shippingAddress: json['shippingAddress']?.toString() ?? '',
      items: items,
      status: OrderStatus.fromString(json['status']?.toString() ?? 'pending'),
      paymentMethod: json['paymentMethod']?.toString() ?? 'card_fpx',
      subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
      shippingFee: (json['shippingFee'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      discount: (json['discount'] as num?)?.toInt() ?? 0,
      tax: (json['tax'] as num?)?.toInt() ?? 0,
      membershipTier: json['membershipTier']?.toString() ?? '',
      supplierIds: (json['supplierIds'] as List<dynamic>?)
              ?.map((e) => e?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      createdAt: json['createdAt'] != null
          ? _parseOrderDate(json['createdAt']) ?? DateTime.now()
          : DateTime.now(),
      statusHistory: _parseStatusHistory(json['statusHistory']),
      refundStatus: RefundStatus.fromString(json['refundStatus']?.toString()),
      refundReason: json['refundReason']?.toString(),
      refundAmount: (json['refundAmount'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderNumber': orderNumber,
        'customerId': customerId,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'customerPhone': customerPhone,
        'shippingAddress': shippingAddress,
        'items': items.map((i) => i.toJson()).toList(),
        'status': status.name,
        'paymentMethod': paymentMethod,
        'subtotal': subtotal,
        'shippingFee': shippingFee,
        'total': total,
        'discount': discount,
        'tax': tax,
        'membershipTier': membershipTier,
        'supplierIds': resolvedSupplierIds,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'statusHistory': statusHistory.map(
            (status, when) => MapEntry(status, when.toUtc().toIso8601String())),
        if (refundStatus != null) 'refundStatus': refundStatus!.name,
        if (refundReason != null) 'refundReason': refundReason,
        if (refundAmount != null) 'refundAmount': refundAmount,
      };
}

/// Parses the stored status→timestamp map (values may be ISO strings or
/// Firestore Timestamps). Unparseable entries are dropped, never fabricated.
Map<String, DateTime> _parseStatusHistory(dynamic raw) {
  if (raw is! Map<String, dynamic>) return {};
  final history = <String, DateTime>{};
  raw.forEach((status, when) {
    if (when == null) return;
    final parsed = _parseOrderDate(when);
    if (parsed != null) history[status] = parsed;
  });
  return history;
}

/// Parses a date that may be an ISO-8601 string or a Firestore Timestamp.
DateTime? _parseOrderDate(dynamic value) {
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
