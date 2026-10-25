import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/models/order.dart';

Order _order({
  List<OrderItem> items = const [],
  List<String> supplierIds = const [],
  int discount = 0,
  int tax = 0,
  int subtotal = 0,
  int total = 0,
  OrderStatus status = OrderStatus.pending,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  String paymentMethod = 'fpx',
  String paymentIntentId = '',
  DateTime? paidAt,
  Map<String, OrderInvoice> invoices = const {},
}) {
  return Order(
    id: 'o1',
    orderNumber: 'ORD-20260929-1234',
    customerId: 'c1',
    customerName: 'Aina',
    customerEmail: 'aina@example.com',
    customerPhone: '0123456789',
    items: items,
    status: status,
    paymentStatus: paymentStatus,
    paymentMethod: paymentMethod,
    paymentIntentId: paymentIntentId,
    paidAt: paidAt,
    subtotal: subtotal,
    total: total,
    discount: discount,
    tax: tax,
    supplierIds: supplierIds,
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
        total: 320,
      );

      final inv = _issue(order);

      expect(inv.items.map((i) => i.productId), ['p1', 'p2']);
      expect(inv.lineCount, 2);
      expect(inv.unitCount, 3);
    });

    test('total is this supplier’s subtotal with nothing else added', () {
      final order = _order(
        items: [
          _item(unitPrice: 100, quantity: 2, supplierId: 's1'),
          _item(id: 'p2', unitPrice: 50, quantity: 1, supplierId: 's2'),
        ],
        supplierIds: ['s1', 's2'],
        subtotal: 250,
        total: 250,
      );

      final inv = _issue(order);

      expect(inv.subtotal, 200);
      expect(inv.discountAllocated, 0);
      expect(inv.taxAllocated, 0);
      expect(inv.total, 200);
    });

    test('allocates order discount proportionally to the item subtotal', () {
      // s1 holds 200 of a 250 order → 4/5 of the RM10 discount.
      final order = _order(
        items: [
          _item(unitPrice: 100, quantity: 2, supplierId: 's1'),
          _item(id: 'p2', unitPrice: 50, quantity: 1, supplierId: 's2'),
        ],
        supplierIds: ['s1', 's2'],
        discount: 10,
        subtotal: 250,
        total: 244,
      );

      final inv = _issue(order);

      expect(inv.subtotal, 200);
      expect(inv.discountAllocated, 8);
      expect(inv.taxAllocated, 0);
      expect(inv.total, 192);
    });

    test('allocates order tax proportionally too', () {
      final order = _order(
        items: [
          _item(unitPrice: 100, quantity: 2, supplierId: 's1'),
          _item(id: 'p2', unitPrice: 50, quantity: 1, supplierId: 's2'),
        ],
        supplierIds: ['s1', 's2'],
        tax: 15,
        subtotal: 250,
        total: 265,
      );

      final inv = _issue(order);

      expect(inv.taxAllocated, 12);
      expect(inv.total, 212);
    });

    test('a single-supplier order carries the whole discount and tax', () {
      final order = _order(
        items: [_item(unitPrice: 100)],
        discount: 10,
        tax: 6,
        subtotal: 100,
        total: 96,
      );

      final inv = _issue(order);

      expect(inv.discountAllocated, 10);
      expect(inv.taxAllocated, 6);
      expect(inv.total, 96);
    });

    test('zero-subtotal orders never divide by zero', () {
      final order = _order(
        items: [_item(unitPrice: 0)],
        discount: 10,
        tax: 6,
        subtotal: 0,
        total: 0,
      );

      final inv = _issue(order);

      expect(inv.discountAllocated, 0);
      expect(inv.taxAllocated, 0);
      expect(inv.total, 0);
    });

    test('freezes the from/to blocks, payment ref and order reference', () {
      final order = _order(
        items: [_item()],
        subtotal: 100,
        total: 100,
        paymentIntentId: 'pi_3ABC',
        paidAt: DateTime.utc(2026, 9, 29, 6, 0),
      );

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
      expect(inv.customerPhone, '0123456789');
      expect(inv.paymentMethod, 'fpx');
      expect(inv.paymentIntentId, 'pi_3ABC');
      expect(inv.paidAt, DateTime.utc(2026, 9, 29, 6, 0));
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
        supplierIds: ['s1', 's2'],
        discount: 10,
        tax: 6,
        subtotal: 240,
        total: 236,
        paymentIntentId: 'pi_3ABC',
        paidAt: DateTime.utc(2026, 9, 29, 6, 0),
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
      expect(back.total, inv.total);
      expect(back.customerName, inv.customerName);
      expect(back.customerPhone, inv.customerPhone);
      expect(back.paymentMethod, inv.paymentMethod);
      expect(back.discountAllocated, inv.discountAllocated);
      expect(back.taxAllocated, inv.taxAllocated);
      expect(back.paymentIntentId, inv.paymentIntentId);
      expect(back.paidAt?.toUtc(), inv.paidAt?.toUtc());
      expect(back.issuedAt.toUtc(), inv.issuedAt.toUtc());
      expect(back.orderCreatedAt.toUtc(), inv.orderCreatedAt.toUtc());
    });

    test('Order.invoices survives an Order JSON round-trip', () {
      final inv = _issue(
        _order(items: [_item()], subtotal: 100, total: 100),
        invoiceNumber: 'INV-20260929-3333',
      );
      final order = _order(
        items: [_item()],
        subtotal: 100,
        total: 100,
        status: OrderStatus.confirmed,
        invoices: {'s1': inv},
      );

      final back = Order.fromJson(order.toJson());

      expect(back.invoices.keys, ['s1']);
      expect(back.invoiceFor('s1')!.invoiceNumber, 'INV-20260929-3333');
    });

    test('an order without invoices round-trips to an empty map', () {
      final back = Order.fromJson(
          _order(items: [_item()], subtotal: 100, total: 100).toJson());

      expect(back.invoices, isEmpty);
      expect(back.invoiceFor('s1'), isNull);
    });

    test('malformed invoice entries are dropped, not fatal', () {
      final back = Order.fromJson({
        ..._order(items: [_item()], subtotal: 100, total: 100).toJson(),
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
      final inv = _issue(
        _order(items: [_item()], subtotal: 100, total: 100),
        invoiceNumber: 'INV-20260929-5555',
      );
      final order = _order(
        items: [_item()],
        subtotal: 100,
        total: 100,
        status: OrderStatus.pending,
        invoices: {'s1': inv},
      );

      final advanced = order.copyWith(status: OrderStatus.confirmed);

      expect(advanced.invoices.keys, ['s1']);
      expect(advanced.invoiceFor('s1')!.invoiceNumber, 'INV-20260929-5555');
    });
  });

  group('invoices stay invisible to the order rules', () {
    test('an invoice survives a byte-identical JSON round-trip', () {
      final inv = _issue(
        _order(items: [_item()], subtotal: 100, total: 100),
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
        total: 100,
        status: OrderStatus.confirmed,
        invoices: {
          's1': _issue(
            _order(items: [_item()], subtotal: 100, total: 100),
            invoiceNumber: 'INV-20260929-7777',
          ),
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
        'status': 'waitingCollection',
        'invoices': {
          's1': <String, dynamic>{'invoiceNumber': 'INV-NEW', 'total': 1},
        },
      };

      final out = preserveStoredInvoices(payload, stored);

      expect(out['status'], 'waitingCollection');
      expect(out['invoices'], same(stored['invoices']));
      expect((out['invoices'] as Map)['s1']['invoiceNumber'], 'INV-OLD');
    });

    test('preserveStoredInvoices drops the key when the store never had one',
        () {
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
