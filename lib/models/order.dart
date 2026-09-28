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

  // ── Transition guards (pure, shared by the repository write path) ──
  //
  // Legal forward chain: pending → confirmed → shipped → delivered.
  // Terminal states (delivered, cancelled) are frozen. Cancellation is
  // allowed from any non-terminal state.

  /// Throws a [StateError] unless [to] is exactly the single legal next step
  /// out of [from] — rejects terminal orders ('Order is already x') and any
  /// jump/skip/backwards move ('Cannot move from A to B'). Messages match
  /// what `MarketplaceRepository.updateOrderStatus` has always thrown.
  static void ensureAdvance(OrderStatus from, OrderStatus to) {
    if (from.isTerminal) {
      throw StateError('Order is already ${from.label.toLowerCase()}');
    }
    if (from.next != to) {
      throw StateError(
          'Cannot move from ${from.label} to ${to.label}');
    }
  }

  /// Throws a [StateError] when the order is already terminal. Any
  /// non-terminal status (pending/confirmed/shipped) may be cancelled.
  /// `MarketplaceRepository.cancelOrder` short-circuits an already-cancelled
  /// order before calling this (idempotent cancel).
  static void ensureCancellable(OrderStatus from) {
    if (from.isTerminal) {
      throw StateError(
          'A ${from.label.toLowerCase()} order cannot be cancelled.');
    }
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

  /// Delivery charge each supplier earned on this order
  /// (`{supplierUid: share}`), recorded at checkout from product-level
  /// shipping settings. Shares always sum to [shippingFee] for orders
  /// placed after product-level shipping shipped. Empty on legacy orders
  /// — those fall back in [shippingShareFor].
  final Map<String, int> shippingBySupplier;

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
    this.shippingBySupplier = const {},
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

  /// [supplierId]'s portion of this order's [shippingFee] — what they
  /// earned from delivery charges, for revenue math and the detail screen.
  ///
  /// Modern orders carry [shippingBySupplier] (exact shares from checkout).
  /// Legacy orders recorded only the aggregate fee, so we fall back:
  ///   • one supplier on the order → that supplier paid the whole fee,
  ///     so the full [shippingFee] is theirs;
  ///   • several suppliers → the flat fee cannot honestly be split, so
  ///     every share reads 0 rather than inventing an attribution.
  int shippingShareFor(String supplierId) {
    final recorded = shippingBySupplier[supplierId];
    if (recorded != null) return recorded;
    if (shippingBySupplier.isNotEmpty) return 0; // known shares, none is ours
    final ids = resolvedSupplierIds;
    if (ids.length == 1 && ids.first == supplierId) return shippingFee;
    return 0;
  }

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
    Map<String, int>? shippingBySupplier,
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
      shippingBySupplier: shippingBySupplier ?? this.shippingBySupplier,
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
      shippingBySupplier: _parseShippingBySupplier(json['shippingBySupplier']),
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
        'shippingBySupplier': shippingBySupplier,
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

/// Parses `{supplierUid: shippingShare}`; malformed/negative entries are
/// dropped (missing supplier → share 0 via `Order.shippingShareFor`).
Map<String, int> _parseShippingBySupplier(dynamic raw) {
  if (raw is! Map<String, dynamic>) return const {};
  final shares = <String, int>{};
  raw.forEach((supplierId, share) {
    if (supplierId.isEmpty) return;
    if (share is! num || share < 0) return;
    shares[supplierId] = share.toInt();
  });
  return shares;
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
