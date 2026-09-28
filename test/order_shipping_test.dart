// Tests for product-level shipping settings and order status transitions
// (the pure logic behind the supplier order management + shipping work).
//
// Pure Dart — no widgets, no Firebase, no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/models/order.dart';
import 'package:interior_design_recommendation/models/product.dart';

Product _product({
  required String id,
  required String supplierId,
  bool shippingEnabled = false,
  int shippingFee = 0,
  bool shippingLongDistanceNotice = false,
}) {
  return Product(
    id: id,
    name: 'Product $id',
    price: 100,
    stock: 3,
    image: '',
    description: '',
    designStyle: 'Modern',
    category: 'Furniture',
    supplier: Supplier(
      id: supplierId,
      name: 'Store $supplierId',
      phone: '',
      address: '',
      email: '',
    ),
    supplierId: supplierId,
    shippingEnabled: shippingEnabled,
    shippingFee: shippingFee,
    shippingLongDistanceNotice: shippingLongDistanceNotice,
  );
}

Order _order({
  int shippingFee = 0,
  List<String> supplierIds = const [],
  Map<String, int> shippingBySupplier = const {},
  List<OrderItem>? items,
  OrderStatus status = OrderStatus.pending,
}) {
  return Order(
    id: 'o1',
    orderNumber: 'ORD-1',
    customerId: 'c1',
    customerName: 'Aina',
    customerEmail: 'aina@example.com',
    customerPhone: '0123456789',
    shippingAddress: '1 Jalan Test, KL',
    items: items ??
        [
          const OrderItem(
            productId: 'p1',
            name: 'Item',
            image: '',
            unitPrice: 50,
            quantity: 1,
            supplierId: 's1',
          ),
        ],
    status: status,
    paymentMethod: 'cod',
    subtotal: 50,
    shippingFee: shippingFee,
    total: 50 + shippingFee,
    createdAt: DateTime.utc(2026, 1, 1),
    supplierIds: supplierIds,
    shippingBySupplier: shippingBySupplier,
  );
}

void main() {
  group('Product shipping fields — defaults & backward compatibility', () {
    test('legacy product JSON without shipping keys loads as free shipping',
        () {
      final p = Product.fromJson(const {
        'id': 'p1',
        'name': 'Chair',
        'price': 100,
        'stock': 3,
        'image': '',
        'supplierId': 's1',
      });
      expect(p.shippingEnabled, isFalse);
      expect(p.shippingFee, 0);
      expect(p.shippingLongDistanceNotice, isFalse);
      expect(p.shippingCharge, 0);
    });

    test('shipping fields round-trip through toJson → fromJson', () {
      final p = _product(
        id: 'p1',
        supplierId: 's1',
        shippingEnabled: true,
        shippingFee: 25,
        shippingLongDistanceNotice: true,
      );
      final json = p.toJson();
      expect(json['shippingEnabled'], true);
      expect(json['shippingFee'], 25);
      expect(json['shippingLongDistanceNotice'], true);

      final back = Product.fromJson(json);
      expect(back.shippingEnabled, isTrue);
      expect(back.shippingFee, 25);
      expect(back.shippingLongDistanceNotice, isTrue);
      expect(back.shippingCharge, 25);
    });

    test('negative or malformed shippingFee clamps to 0', () {
      final negative = Product.fromJson(const {'id': 'x', 'shippingFee': -5});
      expect(negative.shippingFee, 0);

      final malformed = Product.fromJson(const {'id': 'x', 'shippingFee': 'abc'});
      expect(malformed.shippingFee, 0);
    });

    test('shippingCharge is gated by shippingEnabled (fee ignored when off)',
        () {
      final off = _product(id: 'p', supplierId: 's', shippingFee: 12);
      expect(off.shippingEnabled, isFalse);
      expect(off.shippingCharge, 0); // stored fee must never bill buyers

      final on = _product(
          id: 'p', supplierId: 's', shippingEnabled: true, shippingFee: 12);
      expect(on.shippingCharge, 12);
    });

    test('copyWith carries shipping fields', () {
      final p = _product(id: 'p', supplierId: 's')
          .copyWith(shippingEnabled: true, shippingFee: 8);
      expect(p.shippingEnabled, isTrue);
      expect(p.shippingFee, 8);
      // untouched fields survive
      final notice = p.copyWith(shippingLongDistanceNotice: true);
      expect(notice.shippingEnabled, isTrue);
      expect(notice.shippingLongDistanceNotice, isTrue);
    });
  });

  group('Product shipping math (multi-supplier rule)', () {
    test('per-supplier grouping sums each seller’s charges', () {
      final shares = shippingBySupplierFor([
        _product(id: 'a1', supplierId: 's1', shippingEnabled: true, shippingFee: 10),
        _product(id: 'a2', supplierId: 's1', shippingEnabled: true, shippingFee: 5),
        _product(id: 'b1', supplierId: 's2', shippingEnabled: true, shippingFee: 20),
        _product(id: 'f1', supplierId: 's3'), // free — no share entry
      ]);
      expect(shares, {'s1': 15, 's2': 20});
      expect(shares.containsKey('s3'), isFalse);
    });

    test('a product id appearing twice bills once (one line per product)',
        () {
      final dupe = _product(id: 'a1', supplierId: 's1',
          shippingEnabled: true, shippingFee: 10);
      final shares = shippingBySupplierFor([dupe, dupe]);
      expect(shares, {'s1': 10});
    });

    test('disabled products never contribute', () {
      final shares = shippingBySupplierFor([
        _product(id: 'a1', supplierId: 's1', shippingFee: 99), // enabled=false
      ]);
      expect(shares, isEmpty);
      expect(totalShippingFor([
        _product(id: 'a1', supplierId: 's1', shippingFee: 99),
      ]), 0);
    });

    test('totalShippingFor equals the sum of per-supplier shares', () {
      final products = [
        _product(id: 'a1', supplierId: 's1', shippingEnabled: true, shippingFee: 12),
        _product(id: 'b1', supplierId: 's2', shippingEnabled: true, shippingFee: 7),
        _product(id: 'b2', supplierId: 's2'),
      ];
      final shares = shippingBySupplierFor(products);
      expect(totalShippingFor(products), shares.values.fold(0, (s, v) => s + v));
      expect(totalShippingFor(products), 19);
    });
  });

  group('Order.shippingShareFor', () {
    test('modern order: returns the recorded share exactly', () {
      final o = _order(
        shippingFee: 30,
        supplierIds: ['s1', 's2'],
        shippingBySupplier: {'s1': 10, 's2': 20},
      );
      expect(o.shippingShareFor('s1'), 10);
      expect(o.shippingShareFor('s2'), 20);
      expect(o.shippingShareFor('stranger'), 0);
    });

    test('modern order with shares: supplier missing from the map gets 0',
        () {
      final o = _order(
        shippingFee: 20,
        supplierIds: ['s1', 's2'],
        shippingBySupplier: {'s2': 20}, // s1 charges no shipping
      );
      expect(o.shippingShareFor('s1'), 0);
      expect(o.shippingShareFor('s2'), 20);
    });

    test('legacy single-supplier order (no map): full fee attributed', () {
      final o = _order(shippingFee: 25, supplierIds: ['s1']);
      expect(o.shippingBySupplier, isEmpty);
      expect(o.shippingShareFor('s1'), 25);
      expect(o.shippingShareFor('s2'), 0);
    });

    test('legacy multi-supplier order: flat fee cannot be split → all 0',
        () {
      final o = _order(shippingFee: 25, supplierIds: ['s1', 's2']);
      expect(o.shippingShareFor('s1'), 0);
      expect(o.shippingShareFor('s2'), 0);
    });

    test('supplierIds derive from items when none were recorded', () {
      final o = _order(shippingFee: 15, supplierIds: const []);
      expect(o.resolvedSupplierIds, ['s1']);
      expect(o.shippingShareFor('s1'), 15);
    });

    test('modern zero-fee order (free shipping waived) shares are 0', () {
      final o = _order(shippingFee: 0, supplierIds: ['s1', 's2']);
      expect(o.shippingShareFor('s1'), 0);
      expect(o.shippingShareFor('s2'), 0);
    });
  });

  group('Order shippingBySupplier JSON', () {
    test('round-trips through toJson → fromJson', () {
      final o = _order(
        shippingFee: 30,
        supplierIds: ['s1', 's2'],
        shippingBySupplier: {'s1': 12, 's2': 18},
      );
      final json = o.toJson();
      expect(json['shippingBySupplier'], {'s1': 12, 's2': 18});

      final back = Order.fromJson(json);
      expect(back.shippingBySupplier, {'s1': 12, 's2': 18});
      expect(back.shippingShareFor('s1'), 12);
      expect(back.shippingShareFor('s2'), 18);
    });

    test('legacy order JSON without the key parses to an empty map', () {
      final json = _order(shippingFee: 25, supplierIds: ['s1']).toJson()
        ..remove('shippingBySupplier');
      final back = Order.fromJson(json);
      expect(back.shippingBySupplier, isEmpty);
      expect(back.shippingShareFor('s1'), 25); // legacy fallback still works
    });

    test('malformed share entries are dropped, never invented', () {
      final back = Order.fromJson({
        'id': 'o1',
        'shippingFee': 40,
        'supplierIds': ['s1', 's2'],
        'shippingBySupplier': {'s1': 40, 's2': -3, '': 5, 's3': 'NaN'},
      });
      expect(back.shippingBySupplier, {'s1': 40});
      expect(back.shippingShareFor('s2'), 0);
      expect(back.shippingShareFor('s3'), 0);
    });
  });

  group('OrderStatus transition guards', () {
    test('legal chain pending → confirmed → shipped → delivered passes', () {
      expect(() => OrderStatus.ensureAdvance(
          OrderStatus.pending, OrderStatus.confirmed), returnsNormally);
      expect(() => OrderStatus.ensureAdvance(
          OrderStatus.confirmed, OrderStatus.shipped), returnsNormally);
      expect(() => OrderStatus.ensureAdvance(
          OrderStatus.shipped, OrderStatus.delivered), returnsNormally);
    });

    test('terminal orders cannot advance (no delivered → pending)', () {
      expect(
        () => OrderStatus.ensureAdvance(
            OrderStatus.delivered, OrderStatus.pending),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('already delivered'))),
      );
      expect(
        () => OrderStatus.ensureAdvance(
            OrderStatus.cancelled, OrderStatus.confirmed),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('already cancelled'))),
      );
    });

    test('skipping steps is rejected', () {
      expect(
        () => OrderStatus.ensureAdvance(
            OrderStatus.pending, OrderStatus.shipped),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('Cannot move'))),
      );
      expect(
        () => OrderStatus.ensureAdvance(
            OrderStatus.confirmed, OrderStatus.delivered),
        throwsA(isA<StateError>()),
      );
    });

    test('backwards moves are rejected (delivered/shipped → pending)', () {
      expect(
        () => OrderStatus.ensureAdvance(
            OrderStatus.shipped, OrderStatus.confirmed),
        throwsA(isA<StateError>()),
      );
      expect(
        () => OrderStatus.ensureAdvance(
            OrderStatus.delivered, OrderStatus.pending),
        throwsA(isA<StateError>()),
      );
    });

    test('legal next pointers drive the guards', () {
      expect(OrderStatus.pending.next, OrderStatus.confirmed);
      expect(OrderStatus.confirmed.next, OrderStatus.shipped);
      expect(OrderStatus.shipped.next, OrderStatus.delivered);
      expect(OrderStatus.delivered.next, isNull);
      expect(OrderStatus.cancelled.next, isNull);
    });

    test('cancel allowed from every non-terminal state', () {
      expect(() => OrderStatus.ensureCancellable(OrderStatus.pending),
          returnsNormally);
      expect(() => OrderStatus.ensureCancellable(OrderStatus.confirmed),
          returnsNormally);
      expect(() => OrderStatus.ensureCancellable(OrderStatus.shipped),
          returnsNormally);
    });

    test('cancel rejected for terminal states', () {
      expect(
        () => OrderStatus.ensureCancellable(OrderStatus.delivered),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('cannot be cancelled'))),
      );
      expect(() => OrderStatus.ensureCancellable(OrderStatus.cancelled),
          throwsA(isA<StateError>()));
    });
  });

  group('Order.statusHistory JSON', () {
    test('serializes to UTC ISO strings and parses back to DateTime', () {
      final when = DateTime.utc(2026, 3, 5, 10, 30);
      final o = _order().copyWith(
        status: OrderStatus.confirmed,
        statusHistory: {'confirmed': when},
      );
      final json = o.toJson();
      expect(json['statusHistory'], {'confirmed': '2026-03-05T10:30:00.000Z'});

      final back = Order.fromJson(json);
      expect(back.statusHistory['confirmed'], when);
      expect(back.status, OrderStatus.confirmed);
    });

    test('unparseable history entries are dropped, never fabricated', () {
      final back = Order.fromJson({
        'id': 'o1',
        'statusHistory': {
          'confirmed': '2026-03-05T10:30:00.000Z',
          'shipped': 'not-a-date',
        },
      });
      expect(back.statusHistory.containsKey('confirmed'), isTrue);
      expect(back.statusHistory.containsKey('shipped'), isFalse);
    });
  });
}
