import 'dart:math';

enum OrderStatus {
  pending,
  confirmed,
  waitingCollection,
  collected,
  cancelled;

  String get label => switch (this) {
        OrderStatus.pending => 'Pending',
        OrderStatus.confirmed => 'Confirmed',
        OrderStatus.waitingCollection => 'Waiting for collection',
        OrderStatus.collected => 'Collected',
        OrderStatus.cancelled => 'Cancelled',
      };

  OrderStatus? get next => switch (this) {
        OrderStatus.pending => OrderStatus.confirmed,
        OrderStatus.confirmed => OrderStatus.waitingCollection,
        OrderStatus.waitingCollection => OrderStatus.collected,
        _ => null,
      };

  bool get isTerminal =>
      this == OrderStatus.collected || this == OrderStatus.cancelled;

  static OrderStatus fromString(String s) {
    final key = s.trim().toLowerCase();
    // Legacy delivery-era statuses from old documents.
    return switch (key) {
      'shipped' => OrderStatus.waitingCollection,
      'delivered' => OrderStatus.collected,
      _ => OrderStatus.values.firstWhere(
          (e) => e.name.toLowerCase() == key,
          orElse: () => OrderStatus.pending,
        ),
    };
  }

  // ── Transition guards (pure, shared by the repository write path) ──

  static void ensureAdvance(OrderStatus from, OrderStatus to) {
    if (from.isTerminal) {
      throw StateError('Order is already ${from.label.toLowerCase()}');
    }
    if (from.next != to) {
      throw StateError(
          'Cannot move from ${from.label} to ${to.label}');
    }
  }

  static void ensureCancellable(OrderStatus from) {
    if (from.isTerminal) {
      throw StateError(
          'A ${from.label.toLowerCase()} order cannot be cancelled.');
    }
  }
}

enum PaymentStatus {
  unpaid,
  paid,
  failed,
  refunded;

  String get label => switch (this) {
        PaymentStatus.unpaid => 'Awaiting payment',
        PaymentStatus.paid => 'Paid',
        PaymentStatus.failed => 'Payment failed',
        PaymentStatus.refunded => 'Refunded',
      };

  static PaymentStatus fromString(String? s) {
    return PaymentStatus.values.firstWhere(
      (e) => e.name == (s ?? '').trim().toLowerCase(),
      orElse: () => PaymentStatus.unpaid,
    );
  }
}

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

class OrderInvoice {
  final String invoiceNumber;
  final String orderId;
  final String orderNumber;

  final String supplierId;
  final String supplierName;
  final String supplierPhone;
  final String supplierAddress;
  final String supplierEmail;
  final DateTime issuedAt;

  final List<OrderItem> items;

  final int subtotal;

  final int total;

  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final String paymentMethod;
  final DateTime orderCreatedAt;

  final int discountAllocated;
  final int taxAllocated;

  final String paymentIntentId;
  final DateTime? paidAt;

  const OrderInvoice({
    required this.invoiceNumber,
    required this.orderId,
    required this.orderNumber,
    required this.supplierId,
    required this.supplierName,
    required this.supplierPhone,
    required this.supplierAddress,
    required this.supplierEmail,
    required this.issuedAt,
    required this.items,
    required this.subtotal,
    required this.total,
    required this.customerName,
    required this.customerEmail,
    required this.customerPhone,
    required this.paymentMethod,
    required this.orderCreatedAt,
    this.discountAllocated = 0,
    this.taxAllocated = 0,
    this.paymentIntentId = '',
    this.paidAt,
  });

  int get lineCount => items.length;

  int get unitCount => items.fold(0, (sum, i) => sum + i.quantity);

  factory OrderInvoice.issue({
    required Order order,
    required String supplierId,
    required String supplierName,
    String supplierPhone = '',
    String supplierAddress = '',
    String supplierEmail = '',
    DateTime? issuedAt,
    String? invoiceNumber,
  }) {
    final at = issuedAt ?? DateTime.now();
    final myItems =
        order.items.where((i) => i.supplierId == supplierId).toList();
    final mySubtotal = myItems.fold<int>(0, (sum, i) => sum + i.lineTotal);
    final orderSubtotal =
        order.items.fold<int>(0, (sum, i) => sum + i.lineTotal);
    int allocate(int whole) {
      if (orderSubtotal <= 0 || whole == 0) return 0;
      return ((whole * mySubtotal) / orderSubtotal).round();
    }

    final discountShare = allocate(order.discount);
    final taxShare = allocate(order.tax);
    return OrderInvoice(
      invoiceNumber: invoiceNumber ??
          generateInvoiceNumber(at, supplierId: supplierId),
      orderId: order.id,
      orderNumber: order.orderNumber,
      supplierId: supplierId,
      supplierName: supplierName,
      supplierPhone: supplierPhone,
      supplierAddress: supplierAddress,
      supplierEmail: supplierEmail,
      issuedAt: at,
      items: myItems,
      subtotal: mySubtotal,
      total: mySubtotal - discountShare + taxShare,
      customerName: order.customerName,
      customerEmail: order.customerEmail,
      customerPhone: order.customerPhone,
      paymentMethod: order.paymentMethod,
      orderCreatedAt: order.createdAt,
      discountAllocated: discountShare,
      taxAllocated: taxShare,
      paymentIntentId: order.paymentIntentId,
      paidAt: order.paidAt,
    );
  }

  static String generateInvoiceNumber(DateTime issuedAt, {String? supplierId, Random? random}) {
    final r = random ?? _invoiceRandom;
    final y = issuedAt.year.toString().padLeft(4, '0');
    final m = issuedAt.month.toString().padLeft(2, '0');
    final d = issuedAt.day.toString().padLeft(2, '0');
    return 'INV-$y$m$d-${r.nextInt(9000) + 1000}';
  }

  factory OrderInvoice.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>?)
            ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return OrderInvoice(
      invoiceNumber: json['invoiceNumber']?.toString() ?? '',
      orderId: json['orderId']?.toString() ?? '',
      orderNumber: json['orderNumber']?.toString() ?? '',
      supplierId: json['supplierId']?.toString() ?? '',
      supplierName: json['supplierName']?.toString() ?? '',
      supplierPhone: json['supplierPhone']?.toString() ?? '',
      supplierAddress: json['supplierAddress']?.toString() ?? '',
      supplierEmail: json['supplierEmail']?.toString() ?? '',
      issuedAt: _parseOrderDate(json['issuedAt']) ?? DateTime.now(),
      items: items,
      subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      customerName: json['customerName']?.toString() ?? '',
      customerEmail: json['customerEmail']?.toString() ?? '',
      customerPhone: json['customerPhone']?.toString() ?? '',
      paymentMethod: json['paymentMethod']?.toString() ?? '',
      orderCreatedAt: _parseOrderDate(json['orderCreatedAt']) ?? DateTime.now(),
      discountAllocated: (json['discountAllocated'] as num?)?.toInt() ?? 0,
      taxAllocated: (json['taxAllocated'] as num?)?.toInt() ?? 0,
      paymentIntentId: json['paymentIntentId']?.toString() ?? '',
      paidAt: _parseOrderDate(json['paidAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'invoiceNumber': invoiceNumber,
        'orderId': orderId,
        'orderNumber': orderNumber,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'supplierPhone': supplierPhone,
        'supplierAddress': supplierAddress,
        'supplierEmail': supplierEmail,
        'issuedAt': issuedAt.toUtc().toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
        'subtotal': subtotal,
        'total': total,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'customerPhone': customerPhone,
        'paymentMethod': paymentMethod,
        'orderCreatedAt': orderCreatedAt.toUtc().toIso8601String(),
        'discountAllocated': discountAllocated,
        'taxAllocated': taxAllocated,
        'paymentIntentId': paymentIntentId,
        if (paidAt != null) 'paidAt': paidAt!.toUtc().toIso8601String(),
      };
}

final Random _invoiceRandom = Random();

class Order {
  final String id;
  final String orderNumber;
  final String customerId;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final List<OrderItem> items;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final String paymentMethod;
  final String paymentIntentId;
  final DateTime? paidAt;
  final int subtotal;
  final int total;

  final int discount;

  final int tax;

  final String membershipTier;

  final List<String> supplierIds;

  final DateTime createdAt;

  final Map<String, DateTime> statusHistory;

  final Map<String, OrderInvoice> invoices;

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
    required this.items,
    required this.status,
    required this.paymentMethod,
    required this.subtotal,
    required this.total,
    required this.createdAt,
    this.paymentStatus = PaymentStatus.unpaid,
    this.paymentIntentId = '',
    this.paidAt,
    this.discount = 0,
    this.tax = 0,
    this.membershipTier = '',
    this.supplierIds = const [],
    this.statusHistory = const {},
    this.invoices = const {},
    this.refundStatus,
    this.refundReason,
    this.refundAmount,
  });

  String get paymentMethodLabel => switch (paymentMethod) {
        'fpx' => 'FPX Online Banking',
        'card' => 'Credit / Debit Card',
        'card_fpx' => 'Card / FPX',
        'ewallet' => 'E-Wallet',
        _ => paymentMethod,
      };

  List<String> get resolvedSupplierIds => supplierIds.isNotEmpty
      ? supplierIds
      : items
          .map((i) => i.supplierId)
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

  List<String> get supplierIdsInItemOrder =>
      items.map((i) => i.supplierId).where((s) => s.isNotEmpty).toSet().toList();

  OrderInvoice? invoiceFor(String supplierId) => invoices[supplierId];

  Order copyWith({
    String? id,
    String? orderNumber,
    String? customerId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    List<OrderItem>? items,
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    String? paymentMethod,
    String? paymentIntentId,
    DateTime? paidAt,
    int? subtotal,
    int? total,
    int? discount,
    int? tax,
    String? membershipTier,
    List<String>? supplierIds,
    DateTime? createdAt,
    Map<String, DateTime>? statusHistory,
    Map<String, OrderInvoice>? invoices,
    RefundStatus? refundStatus,
    String? refundReason,
    int? refundAmount,
    bool clearRefund = false,
    bool clearPaidAt = false,
  }) {
    return Order(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerEmail: customerEmail ?? this.customerEmail,
      customerPhone: customerPhone ?? this.customerPhone,
      items: items ?? this.items,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentIntentId: paymentIntentId ?? this.paymentIntentId,
      paidAt: clearPaidAt ? null : (paidAt ?? this.paidAt),
      subtotal: subtotal ?? this.subtotal,
      total: total ?? this.total,
      discount: discount ?? this.discount,
      tax: tax ?? this.tax,
      membershipTier: membershipTier ?? this.membershipTier,
      supplierIds: supplierIds ?? this.supplierIds,
      createdAt: createdAt ?? this.createdAt,
      statusHistory: statusHistory ?? this.statusHistory,
      invoices: invoices ?? this.invoices,
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
      items: items,
      status: OrderStatus.fromString(json['status']?.toString() ?? 'pending'),
      // Orders written before the payment pipeline existed are treated as paid.
      paymentStatus: json.containsKey('paymentStatus')
          ? PaymentStatus.fromString(json['paymentStatus']?.toString())
          : PaymentStatus.paid,
      paymentMethod: json['paymentMethod']?.toString() ?? 'card',
      paymentIntentId: json['paymentIntentId']?.toString() ?? '',
      paidAt: _parseOrderDate(json['paidAt']),
      subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
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
      invoices: _parseInvoices(json['invoices']),
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
        'items': items.map((i) => i.toJson()).toList(),
        'status': status.name,
        'paymentStatus': paymentStatus.name,
        'paymentMethod': paymentMethod,
        if (paymentIntentId.isNotEmpty) 'paymentIntentId': paymentIntentId,
        if (paidAt != null) 'paidAt': paidAt!.toUtc().toIso8601String(),
        'subtotal': subtotal,
        'total': total,
        'discount': discount,
        'tax': tax,
        'membershipTier': membershipTier,
        'supplierIds': resolvedSupplierIds,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'statusHistory': statusHistory.map(
            (status, when) => MapEntry(status, when.toUtc().toIso8601String())),
        'invoices': invoices.map((id, inv) => MapEntry(id, inv.toJson())),
        if (refundStatus != null) 'refundStatus': refundStatus!.name,
        if (refundReason != null) 'refundReason': refundReason,
        if (refundAmount != null) 'refundAmount': refundAmount,
      };
}

Map<String, OrderInvoice> _parseInvoices(dynamic raw) {
  if (raw is! Map<String, dynamic>) return const {};
  final out = <String, OrderInvoice>{};
  raw.forEach((supplierId, value) {
    if (supplierId.isEmpty || value is! Map<String, dynamic>) return;
    out[supplierId] = OrderInvoice.fromJson(value);
  });
  return out;
}

Map<String, dynamic> preserveStoredInvoices(
  Map<String, dynamic> payload,
  Map<String, dynamic> stored,
) {
  if (stored.containsKey('invoices')) {
    return {...payload, 'invoices': stored['invoices']};
  }
  return {...payload}..remove('invoices');
}

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
