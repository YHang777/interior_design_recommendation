import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/models/order.dart';

Order _order({
  List<String> supplierIds = const [],
  List<OrderItem>? items,
  OrderStatus status = OrderStatus.pending,
  int discount = 0,
  int tax = 0,
  PaymentStatus paymentStatus = PaymentStatus.unpaid,
  String paymentIntentId = '',
  DateTime? paidAt,
}) {
  return Order(
    id: 'o1',
    orderNumber: 'ORD-1',
    customerId: 'c1',
    customerName: 'Aina',
    customerEmail: 'aina@example.com',
    customerPhone: '0123456789',
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
    paymentStatus: paymentStatus,
    paymentIntentId: paymentIntentId,
    paidAt: paidAt,
    paymentMethod: 'card',
    subtotal: 50,
    discount: discount,
    tax: tax,
    total: 50,
    createdAt: DateTime.utc(2026, 1, 1),
    supplierIds: supplierIds,
  );
}

void main() {
  group('Order lifecycle — self-collection chain', () {
    test('legal chain pending → confirmed → waitingCollection → collected',
        () {
      expect(() => OrderStatus.ensureAdvance(
          OrderStatus.pending, OrderStatus.confirmed), returnsNormally);
      expect(() => OrderStatus.ensureAdvance(
          OrderStatus.confirmed, OrderStatus.waitingCollection),
          returnsNormally);
      expect(() => OrderStatus.ensureAdvance(
          OrderStatus.waitingCollection, OrderStatus.collected),
          returnsNormally);
    });

    test('terminal orders cannot advance', () {
      expect(
        () => OrderStatus.ensureAdvance(
            OrderStatus.collected, OrderStatus.pending),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('already collected'))),
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
            OrderStatus.pending, OrderStatus.waitingCollection),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('Cannot move'))),
      );
      expect(
        () => OrderStatus.ensureAdvance(
            OrderStatus.confirmed, OrderStatus.collected),
        throwsA(isA<StateError>()),
      );
    });

    test('backwards moves are rejected', () {
      expect(
        () => OrderStatus.ensureAdvance(
            OrderStatus.waitingCollection, OrderStatus.confirmed),
        throwsA(isA<StateError>()),
      );
      expect(
        () => OrderStatus.ensureAdvance(
            OrderStatus.collected, OrderStatus.pending),
        throwsA(isA<StateError>()),
      );
    });

    test('legal next pointers drive the guards', () {
      expect(OrderStatus.pending.next, OrderStatus.confirmed);
      expect(OrderStatus.confirmed.next, OrderStatus.waitingCollection);
      expect(OrderStatus.waitingCollection.next, OrderStatus.collected);
      expect(OrderStatus.collected.next, isNull);
      expect(OrderStatus.cancelled.next, isNull);
      expect(OrderStatus.collected.isTerminal, isTrue);
      expect(OrderStatus.cancelled.isTerminal, isTrue);
      expect(OrderStatus.waitingCollection.isTerminal, isFalse);
    });

    test('cancel allowed from every non-terminal state', () {
      expect(() => OrderStatus.ensureCancellable(OrderStatus.pending),
          returnsNormally);
      expect(() => OrderStatus.ensureCancellable(OrderStatus.confirmed),
          returnsNormally);
      expect(() => OrderStatus.ensureCancellable(OrderStatus.waitingCollection),
          returnsNormally);
    });

    test('cancel rejected for terminal states', () {
      expect(
        () => OrderStatus.ensureCancellable(OrderStatus.collected),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('cannot be cancelled'))),
      );
      expect(() => OrderStatus.ensureCancellable(OrderStatus.cancelled),
          throwsA(isA<StateError>()));
    });

    test('status labels match the buyer/supplier wording', () {
      expect(OrderStatus.pending.label, 'Pending');
      expect(OrderStatus.confirmed.label, 'Confirmed');
      expect(OrderStatus.waitingCollection.label, 'Waiting for collection');
      expect(OrderStatus.collected.label, 'Collected');
      expect(OrderStatus.cancelled.label, 'Cancelled');
    });
  });

  group('Legacy delivery-era status mapping', () {
    test("'shipped' maps to waitingCollection", () {
      expect(OrderStatus.fromString('shipped'), OrderStatus.waitingCollection);
      expect(OrderStatus.fromString('Shipped'), OrderStatus.waitingCollection);
    });

    test("'delivered' maps to collected", () {
      expect(OrderStatus.fromString('delivered'), OrderStatus.collected);
      expect(OrderStatus.fromString('Delivered'), OrderStatus.collected);
    });

    test('current names parse case-insensitively', () {
      expect(OrderStatus.fromString('waitingCollection'),
          OrderStatus.waitingCollection);
      expect(OrderStatus.fromString('WAITINGCOLLECTION'),
          OrderStatus.waitingCollection);
      expect(OrderStatus.fromString('collected'), OrderStatus.collected);
    });

    test('unknown status falls back to pending', () {
      expect(OrderStatus.fromString('nonsense'), OrderStatus.pending);
      expect(OrderStatus.fromString(''), OrderStatus.pending);
    });

    test('legacy order JSON with shipped/delivered parses to new statuses',
        () {
      final shipped = Order.fromJson(const {
        'id': 'a',
        'status': 'shipped',
        'items': [],
      });
      expect(shipped.status, OrderStatus.waitingCollection);

      final delivered = Order.fromJson(const {
        'id': 'b',
        'status': 'delivered',
        'items': [],
      });
      expect(delivered.status, OrderStatus.collected);
    });
  });

  group('Payment fields', () {
    test('constructor defaults to unpaid with no intent', () {
      final o = _order();
      expect(o.paymentStatus, PaymentStatus.unpaid);
      expect(o.paymentIntentId, '');
      expect(o.paidAt, isNull);
    });

    test('payment fields round-trip through toJson → fromJson', () {
      final paidAt = DateTime.utc(2026, 2, 1, 9);
      final o = _order(
        paymentStatus: PaymentStatus.paid,
        paymentIntentId: 'pi_123',
        paidAt: paidAt,
      );
      final json = o.toJson();
      expect(json['paymentStatus'], 'paid');
      expect(json['paymentIntentId'], 'pi_123');
      expect(json['paidAt'], '2026-02-01T09:00:00.000Z');

      final back = Order.fromJson(json);
      expect(back.paymentStatus, PaymentStatus.paid);
      expect(back.paymentIntentId, 'pi_123');
      expect(back.paidAt, paidAt);
    });

    test('legacy order JSON without paymentStatus is treated as paid', () {
      final back = Order.fromJson(const {'id': 'x', 'items': []});
      expect(back.paymentStatus, PaymentStatus.paid);
    });

    test('payment method labels cover card and FPX', () {
      expect(_order().paymentMethodLabel, 'Credit / Debit Card');
      final o = _order().copyWith(paymentMethod: 'fpx');
      expect(o.paymentMethodLabel, 'FPX Online Banking');
    });
  });

  group('OrderInvoice.issue — allocated discount/tax', () {
    OrderInvoice issueFor(String supplierId) {
      final order = _order(
        items: const [
          OrderItem(
              productId: 'a',
              name: 'A',
              image: '',
              unitPrice: 60,
              quantity: 1,
              supplierId: 's1'),
          OrderItem(
              productId: 'b',
              name: 'B',
              image: '',
              unitPrice: 40,
              quantity: 1,
              supplierId: 's2'),
        ],
        supplierIds: ['s1', 's2'],
        discount: 10,
        tax: 5,
      ).copyWith(subtotal: 100, total: 95);
      return OrderInvoice.issue(
        order: order,
        supplierId: supplierId,
        supplierName: 'Store $supplierId',
        supplierAddress: '1 Jalan Test, KL',
        invoiceNumber: 'INV-TEST',
        issuedAt: DateTime.utc(2026, 1, 2),
      );
    }

    test('discount and tax split proportionally by item subtotal', () {
      final i1 = issueFor('s1');
      expect(i1.subtotal, 60);
      expect(i1.discountAllocated, 6);
      expect(i1.taxAllocated, 3);
      expect(i1.total, 60 - 6 + 3);

      final i2 = issueFor('s2');
      expect(i2.subtotal, 40);
      expect(i2.discountAllocated, 4);
      expect(i2.taxAllocated, 2);
      expect(i2.total, 40 - 4 + 2);
    });

    test('totals equal subtotal − discountAllocated + taxAllocated', () {
      for (final id in ['s1', 's2']) {
        final inv = issueFor(id);
        expect(
            inv.total, inv.subtotal - inv.discountAllocated + inv.taxAllocated);
      }
    });

    test('keeps supplier pickup address and payment proof fields', () {
      final order = _order(
        paymentStatus: PaymentStatus.paid,
        paymentIntentId: 'pi_abc',
        paidAt: DateTime.utc(2026, 1, 3),
      );
      final inv = OrderInvoice.issue(
        order: order,
        supplierId: 's1',
        supplierName: 'Store s1',
        supplierAddress: '1 Jalan Test, KL',
        invoiceNumber: 'INV-2',
        issuedAt: DateTime.utc(2026, 1, 2),
      );
      expect(inv.supplierAddress, '1 Jalan Test, KL');
      expect(inv.paymentIntentId, 'pi_abc');
      expect(inv.paidAt, DateTime.utc(2026, 1, 3));
      expect(inv.total, inv.subtotal);
    });

    test('invoice JSON round-trips the new fields', () {
      final inv = issueFor('s1');
      final back = OrderInvoice.fromJson(inv.toJson());
      expect(back.discountAllocated, inv.discountAllocated);
      expect(back.taxAllocated, inv.taxAllocated);
      expect(back.supplierAddress, inv.supplierAddress);
      expect(back.total, inv.total);
      expect(back.toJson().containsKey('shippingFee'), isFalse);
      expect(back.toJson().containsKey('shippingAddress'), isFalse);
    });
  });

  group('Order JSON — shipping removed, payment kept', () {
    test('toJson never emits shipping keys', () {
      final json = _order().toJson();
      expect(json.containsKey('shippingAddress'), isFalse);
      expect(json.containsKey('shippingFee'), isFalse);
      expect(json.containsKey('shippingBySupplier'), isFalse);
    });

    test('legacy JSON with shipping keys still loads and drops them', () {
      final back = Order.fromJson(const {
        'id': 'o9',
        'status': 'pending',
        'items': [],
        'shippingAddress': '9 Old Road',
        'shippingFee': 25,
      });
      expect(back.subtotal, 0);
      expect(() => back.toJson(), returnsNormally);
      expect(back.toJson().containsKey('shippingAddress'), isFalse);
    });

    test('supplierIds derive from items when none were recorded', () {
      final o = _order(supplierIds: const []);
      expect(o.resolvedSupplierIds, ['s1']);
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
      final back = Order.fromJson(const {
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
