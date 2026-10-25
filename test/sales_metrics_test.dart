import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/supplier/presentation/providers/supplier_providers.dart';
import 'package:interior_design_recommendation/models/order.dart';
import 'package:interior_design_recommendation/models/product.dart';

const String _supplier = 's1';

OrderItem _item({
  String productId = 'p1',
  String name = 'Item',
  int unitPrice = 50,
  int quantity = 1,
  String supplierId = _supplier,
}) {
  return OrderItem(
    productId: productId,
    name: name,
    image: '',
    unitPrice: unitPrice,
    quantity: quantity,
    supplierId: supplierId,
  );
}

Order _order({
  String id = 'o1',
  String customerId = 'c1',
  OrderStatus status = OrderStatus.pending,
  DateTime? createdAt,
  List<OrderItem>? items,
}) {
  final lineItems = items ?? [_item()];
  final subtotal = lineItems.fold<int>(0, (s, i) => s + i.lineTotal);
  return Order(
    id: id,
    orderNumber: 'ORD-$id',
    customerId: customerId,
    customerName: 'Customer $customerId',
    customerEmail: '$customerId@example.com',
    customerPhone: '0123456789',
    items: lineItems,
    status: status,
    paymentMethod: 'card',
    subtotal: subtotal,
    total: subtotal,
    createdAt: createdAt ?? DateTime.utc(2026, 9, 1),
  );
}

Product _product({
  String id = 'p1',
  String name = 'Product',
  double rating = 0.0,
  int ratingCount = 0,
  String supplierId = _supplier,
}) {
  return Product(
    id: id,
    name: name,
    price: 100,
    stock: 5,
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
    rating: rating,
    ratingCount: ratingCount,
  );
}

void main() {
  group('topProductsByUnits', () {
    test('sorts by units desc, then revenue desc, and applies the limit', () {
      final orders = [
        _order(id: 'o1', items: [
          _item(productId: 'p1', name: 'Chair', unitPrice: 50, quantity: 2),
        ]),
        _order(id: 'o2', items: [
          _item(productId: 'p2', name: 'Lamp', unitPrice: 20, quantity: 5),
        ]),
        _order(id: 'o3', items: [
          _item(productId: 'p3', name: 'Sofa', unitPrice: 300, quantity: 1),
        ]),
        _order(id: 'o4', items: [
          _item(productId: 'p4', name: 'Mat', unitPrice: 30, quantity: 1),
        ]),
      ];

      final top = topProductsByUnits(orders, _supplier, limit: 3);

      expect(top, hasLength(3));
      expect(top.map((t) => t.productId).toList(), ['p2', 'p1', 'p3']);
      expect(top[0].units, 5);
      expect(top[0].revenue, 100);
      expect(top[1].units, 2);
      expect(top[1].revenue, 100);
      expect(top[2].units, 1);
      expect(top[2].revenue, 300);
    });

    test('aggregates the same product across orders and keeps its name', () {
      final orders = [
        _order(id: 'o1', items: [
          _item(productId: 'p1', name: 'Chair', quantity: 2),
        ]),
        _order(id: 'o2', items: [
          _item(productId: 'p1', name: 'Chair', quantity: 3),
        ]),
      ];

      final top = topProductsByUnits(orders, _supplier);

      expect(top, hasLength(1));
      expect(top.single.productId, 'p1');
      expect(top.single.name, 'Chair');
      expect(top.single.units, 5);
      expect(top.single.revenue, 5 * 50);
    });

    test('cancelled orders never count', () {
      final orders = [
        _order(id: 'o1', items: [
          _item(productId: 'p1', quantity: 1),
        ]),
        _order(id: 'o2', status: OrderStatus.cancelled, items: [
          _item(productId: 'p1', quantity: 10),
        ]),
      ];

      final top = topProductsByUnits(orders, _supplier);

      expect(top.single.units, 1);
      expect(top.single.revenue, 50);
    });

    test('no sales → empty list', () {
      expect(topProductsByUnits(const [], _supplier), isEmpty);
    });
  });

  group('customerInsights', () {
    test('no orders → zeros and null rates (never a fake 0%)', () {
      final insights = customerInsights(const [], _supplier);

      expect(insights.uniqueCustomers, 0);
      expect(insights.repeatCustomers, 0);
      expect(insights.newCustomers, 0);
      expect(insights.retentionRate, isNull);
      expect(insights.repeatPurchaseRate, isNull);
      expect(insights.avgOrderValue, isNull);
    });

    test('single order → 1 customer, retention 0, repeat 0', () {
      final insights = customerInsights(
        [_order(id: 'o1', customerId: 'c1')],
        _supplier,
        now: DateTime.utc(2026, 9, 5),
      );

      expect(insights.uniqueCustomers, 1);
      expect(insights.repeatCustomers, 0);
      expect(insights.retentionRate, 0);
      expect(insights.repeatPurchaseRate, 0);
      expect(insights.avgOrderValue, 50);
      expect(insights.newCustomers, 1);
    });

    test('two orders, same customer → retention 1.0 and repeat 1.0', () {
      final insights = customerInsights(
        [
          _order(id: 'o1', customerId: 'c1'),
          _order(id: 'o2', customerId: 'c1'),
        ],
        _supplier,
        now: DateTime.utc(2026, 9, 5),
      );

      expect(insights.uniqueCustomers, 1);
      expect(insights.repeatCustomers, 1);
      expect(insights.retentionRate, 1.0);
      expect(insights.repeatPurchaseRate, 1.0);
      expect(insights.avgOrderValue, 50);
    });

    test('mixed: repeat rate weights orders, not customers', () {
      final insights = customerInsights(
        [
          _order(id: 'o1', customerId: 'c1'),
          _order(id: 'o2', customerId: 'c1'),
          _order(id: 'o3', customerId: 'c2'),
        ],
        _supplier,
        now: DateTime.utc(2026, 9, 5),
      );

      expect(insights.uniqueCustomers, 2);
      expect(insights.repeatCustomers, 1);
      expect(insights.retentionRate, closeTo(0.5, 1e-9));
      expect(insights.repeatPurchaseRate, closeTo(2 / 3, 1e-9));
    });

    test('new-customer window: last 6 calendar months from now', () {
      final now = DateTime.utc(2026, 9, 5);
      final orders = [
        _order(
          id: 'oNew',
          customerId: 'cNew',
          createdAt: DateTime.utc(2026, 4, 1),
        ),
        _order(
          id: 'oOld',
          customerId: 'cOld',
          createdAt: DateTime.utc(2026, 3, 31),
        ),
      ];

      final insights = customerInsights(orders, _supplier, now: now);

      expect(insights.newCustomers, 1);
    });

    test('customer counts as new only from their FIRST order', () {
      final now = DateTime.utc(2026, 9, 5);
      final orders = [
        _order(
          id: 'oOld',
          customerId: 'c1',
          createdAt: DateTime.utc(2025, 12, 1),
        ),
        _order(
          id: 'oNew',
          customerId: 'c1',
          createdAt: DateTime.utc(2026, 8, 1),
        ),
      ];

      final insights = customerInsights(orders, _supplier, now: now);

      expect(insights.newCustomers, 0);
      expect(insights.uniqueCustomers, 1);
    });

    test('cancelled orders are excluded entirely', () {
      final insights = customerInsights(
        [
          _order(id: 'o1', customerId: 'c1'),
          _order(id: 'o2', customerId: 'c1', status: OrderStatus.cancelled),
        ],
        _supplier,
        now: DateTime.utc(2026, 9, 5),
      );

      expect(insights.uniqueCustomers, 1);
      expect(insights.repeatCustomers, 0);
      expect(insights.retentionRate, 0);
      expect(insights.repeatPurchaseRate, 0);
    });
  });

  group('averageProductRating', () {
    test('weights by ratingCount: 4.0×1 and 5.0×3 → 4.75', () {
      final avg = averageProductRating([
        _product(id: 'p1', rating: 4.0, ratingCount: 1),
        _product(id: 'p2', rating: 5.0, ratingCount: 3),
      ], _supplier);

      expect(avg, closeTo(4.75, 1e-9));
    });

    test('null when nothing has been rated (never 0.0)', () {
      expect(
        averageProductRating([
          _product(id: 'p1', rating: 0.0, ratingCount: 0),
          _product(id: 'p2', rating: 4.5, ratingCount: 0),
        ], _supplier),
        isNull,
      );
      expect(averageProductRating(const [], _supplier), isNull);
    });

    test('only counts this supplier’s products', () {
      final avg = averageProductRating([
        _product(id: 'p1', rating: 5.0, ratingCount: 1),
        _product(
          id: 'p2',
          rating: 1.0,
          ratingCount: 9,
          supplierId: 'other',
        ),
      ], _supplier);

      expect(avg, 5.0);
    });
  });

  group('conversionRate', () {
    test('collected ÷ all orders; cancelled stays in the denominator', () {
      final orders = [
        _order(id: 'o1', status: OrderStatus.collected),
        _order(id: 'o2', status: OrderStatus.collected),
        _order(id: 'o3', status: OrderStatus.cancelled),
      ];

      final rate = conversionRate(orders, _supplier);

      expect(rate, closeTo(2 / 3, 1e-9));
      expect(collectedCount(orders, _supplier), 2);
    });

    test('null when the supplier has no orders', () {
      expect(conversionRate(const [], _supplier), isNull);
      expect(collectedCount(const [], _supplier), 0);
    });

    test('ignores orders that don\'t involve this supplier', () {
      final orders = [
        _order(id: 'o1', status: OrderStatus.collected),
        _order(
          id: 'o2',
          status: OrderStatus.pending,
          items: [_item(supplierId: 'someone-else')],
        ),
      ];

      expect(conversionRate(orders, _supplier), 1.0);
      expect(collectedCount(orders, _supplier), 1);
    });
  });
}
