// Tests for supplier invoices — the document issued the moment a supplier
// accepts an order.
//
// Pure Dart — no widgets, no Firebase, no network.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/models/order.dart';

Order _order({
  List<OrderItem> items = const [],
  int shippingFee = 0,
  Map<String, int> shippingBySupplier = const {},
  List<String> supplierIds = const [],
  int discount = 0,
  int tax = 0,
  int subtotal = 0,
  OrderStatus status = OrderStatus.pending,
  Map<String, OrderInvoice> invoices = const {},
}) {
  return Order(
    id: 'o1',
    orderNumber: 'ORD-20260929-1234',
    customerId: 'c1',
    customerName: 'Aina',
    customerEmail: 'aina@example.com',
    customerPhone: '0123456789',
    shippingAddress: '1 Jalan Test, Kuala Lumpur',
    items: items,
    status: status,
    paymentMethod: 'fpx',
    subtotal: subtotal,
    shippingFee: shippingFee,
    total: subtotal + shippingFee,
    discount: discount,
    tax: tax,
    supplierIds: supplierIds,
    shippingBySupplier: shippingBySupplier,
    createdAt: DateTime(2026, 9, 29, 10, 30),
    invoices: invoices,
  );
}

OrderItem _item({
  String id = 'p1',
  String name = 'Nordic Sofa',
  int unitPrice = 100,
  int quantity = 1,
  String supplierId = 's1',
}) {
  return OrderItem(
    productId: id,
    name: name,
    image: '',
    unitPrice: unitPrice,
    quantity: quantity,
    supplierId: supplierId,
  );
}

OrderInvoice _issue(
  Order order, {
  String supplierId = 's1',
  String supplierName = 'Studio Kayu',
  DateTime? issuedAt,
  String? invoiceNumber,
}) {
  return OrderInvoice.issue(
    order: order,
    supplierId: supplierId,
    supplierName: supplierName,
    supplierPhone: '0129998888',
    supplierAddress: '2 Jalan Supplier, PJ',
    supplierEmail: 'shop@example.com',
    issuedAt: issuedAt,
    invoiceNumber: invoiceNumber,
  );
}

void main() {
  group('OrderInvoice.issue', () {
    test('covers only the accepting supplier’s items', () {
      final order = _order(
        items: [
          _item(id: 'p1', name: 'Sofa', unitPrice: 100, quantity: 2, supplierId: 's1'),
          _item(id: 'p2', name: 'Lamp', unitPrice: 40, quantity: 1, supplierId: 's1'),
          _item(id: 'p3', name: 'Rug', unitPrice: 80, quantity: 1, supplierId: 's2'),
        ],
        supplierIds: ['s1', 's2'],
        subtotal: 320,
      );

      final inv = _issue(order);

      expect(inv.items.map((i) => i.productId), ['p1', 'p2']);
      expect(inv.lineCount, 2);
      expect(inv.unitCount, 3);
    });

    test('total is this supplier’s subtotal plus their shipping share', () {
      final order = _order(
        items: [
          _item(unitPrice: 100, quantity: 2, supplierId: 's1'),
          _item(id: 'p2', unitPrice: 50, quantity: 1, supplierId: 's2'),
        ],
        supplierIds: ['s1', 's2'],
        shippingFee: 25,
        shippingBySupplier: {'s1': 15, 's2': 10},
        subtotal: 250,
      );

      final inv = _issue(order);

      expect(inv.subtotal, 200);
      expect(inv.shippingFee, 15);
      expect(inv.total, 215);
    });

    test('legacy single-supplier order bills the whole shipping fee', () {
      final order = _order(
        items: [_item(unitPrice: 100, quantity: 1)],
        shippingFee: 25,
        subtotal: 100,
      );

      final inv = _issue(order);

      expect(inv.shippingFee, 25);
      expect(inv.total, 125);
    });

    test('unattributed multi-seller shipping is never invented', () {
      // No per-supplier shares recorded, several sellers → shippingShareFor
      // returns 0 rather than guessing a split. The invoice must not silently
      // bill a share the order never recorded.
      final order = _order(
        items: [
          _item(unitPrice: 100, supplierId: 's1'),
          _item(id: 'p2', unitPrice: 50, supplierId: 's2'),
        ],
        supplierIds: ['s1', 's2'],
        shippingFee: 25,
        subtotal: 150,
      );

      final inv = _issue(order);

      expect(inv.shippingFee, 0);
      expect(inv.total, 100);
    });

    test('carries order-level discount and tax as reference only', () {
      final order = _order(
        items: [_item(unitPrice: 100)],
        discount: 10,
        tax: 6,
        subtotal: 100,
      );

      final inv = _issue(order);

      expect(inv.orderDiscount, 10);
      expect(inv.orderTax, 6);
      // Never folded into the supplier's charge.
      expect(inv.total, 100);
    });

    test('freezes the from/to blocks and order reference', () {
      final order = _order(items: [_item()], subtotal: 100);

      final inv = _issue(
        order,
        issuedAt: DateTime(2026, 9, 29, 14, 5),
        invoiceNumber: 'INV-20260929-1111',
      );

      expect(inv.invoiceNumber, 'INV-20260929-1111');
      expect(inv.orderNumber, 'ORD-20260929-1234');
      expect(inv.orderId, 'o1');
      expect(inv.supplierName, 'Studio Kayu');
      expect(inv.customerName, 'Aina');
      expect(inv.shippingAddress, '1 Jalan Test, Kuala Lumpur');
      expect(inv.paymentMethod, 'fpx');
      expect(inv.orderCreatedAt, DateTime(2026, 9, 29, 10, 30));
    });
  });

  group('invoice numbers', () {
    test('follow INV-YYYYMMDD-NNNN', () {
      final n = OrderInvoice.generateInvoiceNumber(
        DateTime(2026, 9, 29),
        random: Random(7),
      );

      expect(n, matches(RegExp(r'^INV-20260929-\d{4}$')));
    });

    test('zero-pads month and day', () {
      final n = OrderInvoice.generateInvoiceNumber(
        DateTime(2026, 1, 5),
        random: Random(7),
      );

      expect(n, startsWith('INV-20260105-'));
    });

    test('is reproducible under a seeded Random', () {
      final a = OrderInvoice.generateInvoiceNumber(DateTime(2026, 9, 29), random: Random(42));
      final b = OrderInvoice.generateInvoiceNumber(DateTime(2026, 9, 29), random: Random(42));

      expect(a, b);
    });
  });

  group('serialization', () {
    test('OrderInvoice round-trips through JSON', () {
      final order = _order(
        items: [
          _item(unitPrice: 100, quantity: 2),
          _item(id: 'p2', name: 'Lamp', unitPrice: 40, supplierId: 's2'),
        ],
        shippingFee: 25,
        shippingBySupplier: {'s1': 15, 's2': 10},
        supplierIds: ['s1', 's2'],
        discount: 10,
        tax: 6,
        subtotal: 240,
      );
      final inv = _issue(order, invoiceNumber: 'INV-20260929-2222');

      final back = OrderInvoice.fromJson(inv.toJson());

      expect(back.invoiceNumber, 'INV-20260929-2222');
      expect(back.orderId, inv.orderId);
      expect(back.orderNumber, inv.orderNumber);
      expect(back.supplierId, inv.supplierId);
      expect(back.supplierName, inv.supplierName);
      expect(back.supplierPhone, inv.supplierPhone);
      expect(back.supplierAddress, inv.supplierAddress);
      expect(back.supplierEmail, inv.supplierEmail);
      expect(back.items.length, 1);
      expect(back.items.first.name, 'Nordic Sofa');
      expect(back.subtotal, inv.subtotal);
      expect(back.shippingFee, inv.shippingFee);
      expect(back.total, inv.total);
      expect(back.customerName, inv.customerName);
      expect(back.shippingAddress, inv.shippingAddress);
      expect(back.paymentMethod, inv.paymentMethod);
      expect(back.orderDiscount, 10);
      expect(back.orderTax, 6);
      expect(back.issuedAt.toUtc(), inv.issuedAt.toUtc());
      expect(back.orderCreatedAt.toUtc(), inv.orderCreatedAt.toUtc());
    });

    test('Order.invoices survives an Order JSON round-trip', () {
      final inv = _issue(_order(items: [_item()], subtotal: 100),
          invoiceNumber: 'INV-20260929-3333');
      final order = _order(
        items: [_item()],
        subtotal: 100,
        status: OrderStatus.confirmed,
        invoices: {'s1': inv},
      );

      final back = Order.fromJson(order.toJson());

      expect(back.invoices.keys, ['s1']);
      expect(back.invoiceFor('s1')!.invoiceNumber, 'INV-20260929-3333');
    });

    test('an order without invoices round-trips to an empty map', () {
      final back = Order.fromJson(_order(items: [_item()], subtotal: 100).toJson());

      expect(back.invoices, isEmpty);
      expect(back.invoiceFor('s1'), isNull);
    });

    test('malformed invoice entries are dropped, not fatal', () {
      final back = Order.fromJson({
        ..._order(items: [_item()], subtotal: 100).toJson(),
        'invoices': {
          's1': 'not-a-map',
          's2': <String, dynamic>{'invoiceNumber': 'INV-20260929-4444'},
        },
      });

      expect(back.invoices.keys, ['s2']);
      expect(back.invoiceFor('s2')!.invoiceNumber, 'INV-20260929-4444');
      expect(back.invoiceFor('s1'), isNull);
    });

    test('copyWith preserves invoices unless replaced', () {
      final inv = _issue(_order(items: [_item()], subtotal: 100),
          invoiceNumber: 'INV-20260929-5555');
      final order = _order(
        items: [_item()],
        subtotal: 100,
        status: OrderStatus.pending,
        invoices: {'s1': inv},
      );

      final advanced = order.copyWith(status: OrderStatus.confirmed);

      expect(advanced.invoices.keys, ['s1']);
      expect(advanced.invoiceFor('s1')!.invoiceNumber, 'INV-20260929-5555');
    });
  });

  // These are not style checks — `firestore.rules` lets a CUSTOMER update an
  // order only while the `invoices` value is byte-identical
  // (`diff().affectedKeys()` must not name it). Every full-document write in
  // `MarketplaceRepository` that is NOT an invoice write routes through
  // [preserveStoredInvoices], and these tests pin the two failure modes it
  // exists to prevent: a parse → serialise drift, and `Order.toJson` adding an
  // `invoices: {}` key to a document that never had one.
  group('invoices stay invisible to the order rules', () {
    test('an invoice survives a byte-identical JSON round-trip', () {
      final inv = _issue(
        _order(items: [_item()], subtotal: 100),
        invoiceNumber: 'INV-20260929-6666',
        issuedAt: DateTime.utc(2026, 9, 29, 6, 5, 0, 123),
      );

      final once = inv.toJson();
      final twice = OrderInvoice.fromJson(once).toJson();

      expect(twice, equals(once),
          reason: 'a drifted date would make the rules see an edit that '
              'never happened and lock the buyer out of cancelling');
    });

    test('an Order’s invoices map survives a byte-identical JSON round-trip',
        () {
      final order = _order(
        items: [_item()],
        subtotal: 100,
        status: OrderStatus.confirmed,
        invoices: {
          's1': _issue(_order(items: [_item()], subtotal: 100),
              invoiceNumber: 'INV-20260929-7777'),
        },
      );

      final once = order.toJson();
      final twice = Order.fromJson(once).toJson();

      expect(twice['invoices'], equals(once['invoices']));
    });

    test('preserveStoredInvoices writes the stored map back verbatim', () {
      final stored = <String, dynamic>{
        'status': 'confirmed',
        'invoices': {
          's1': <String, dynamic>{'invoiceNumber': 'INV-OLD', 'total': 999},
        },
      };
      final payload = <String, dynamic>{
        'status': 'shipped',
        'invoices': {
          's1': <String, dynamic>{'invoiceNumber': 'INV-NEW', 'total': 1},
        },
      };

      final out = preserveStoredInvoices(payload, stored);

      expect(out['status'], 'shipped');
      expect(out['invoices'], same(stored['invoices']));
      expect((out['invoices'] as Map)['s1']['invoiceNumber'], 'INV-OLD');
    });

    test('preserveStoredInvoices drops the key when the store never had one',
        () {
      // Order.toJson always emits `invoices: {}`. On a legacy order that
      // predates the feature that would read as an ADD to the rules — and the
      // customer's Cancel button would fail with permission-denied.
      final payload = <String, dynamic>{
        'status': 'cancelled',
        'invoices': <String, dynamic>{},
      };

      final out = preserveStoredInvoices(payload, <String, dynamic>{
        'status': 'confirmed',
      });

      expect(out.containsKey('invoices'), isFalse);
      expect(out['status'], 'cancelled');
    });

    test('preserveStoredInvoices leaves every other field alone', () {
      final stored = <String, dynamic>{
        'status': 'pending',
        'invoices': <String, dynamic>{'s1': <String, dynamic>{'total': 1}},
      };
      final payload = <String, dynamic>{
        'id': 'o1',
        'status': 'cancelled',
        'statusHistory': <String, dynamic>{'cancelled': '2026-09-29T00:00:00Z'},
        'invoices': <String, dynamic>{},
      };

      final out = preserveStoredInvoices(payload, stored);

      expect(out.keys.toSet(), {'id', 'status', 'statusHistory', 'invoices'});
      expect(out['id'], 'o1');
      expect(out['statusHistory'], isNotEmpty);
    });
  });
}
