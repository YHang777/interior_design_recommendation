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
  final DateTime createdAt;
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
    this.refundStatus,
    this.refundReason,
    this.refundAmount,
  });

  String get paymentMethodLabel => switch (paymentMethod) {
        'card_fpx' => 'Card / FPX',
        'cod' => 'Cash on Delivery',
        'ewallet' => 'E-Wallet',
        _ => paymentMethod,
      };

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
    DateTime? createdAt,
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
      createdAt: createdAt ?? this.createdAt,
      refundStatus: clearRefund ? null : (refundStatus ?? this.refundStatus),
      refundReason: clearRefund ? null : (refundReason ?? this.refundReason),
      refundAmount: clearRefund ? null : (refundAmount ?? this.refundAmount),
    );
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id']?.toString() ?? '',
      orderNumber: json['orderNumber']?.toString() ?? '',
      customerId: json['customerId']?.toString() ?? '',
      customerName: json['customerName']?.toString() ?? '',
      customerEmail: json['customerEmail']?.toString() ?? '',
      customerPhone: json['customerPhone']?.toString() ?? '',
      shippingAddress: json['shippingAddress']?.toString() ?? '',
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      status: OrderStatus.fromString(json['status']?.toString() ?? 'pending'),
      paymentMethod: json['paymentMethod']?.toString() ?? 'card_fpx',
      subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
      shippingFee: (json['shippingFee'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
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
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (refundStatus != null) 'refundStatus': refundStatus!.name,
        if (refundReason != null) 'refundReason': refundReason,
        if (refundAmount != null) 'refundAmount': refundAmount,
      };
}
