// Tests for the customer dashboard stats layer (pure functions + model).
//
// Pure Dart — no widgets, no Firebase, no network.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_plan.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/stats/customer_stats.dart';
import 'package:interior_design_recommendation/models/order.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

Order _order({
  String id = 'o1',
  String orderNumber = 'ORD-1',
  OrderStatus status = OrderStatus.pending,
  DateTime? createdAt,
  Map<String, DateTime> statusHistory = const {},
  int total = 100,
  int itemCount = 1,
}) {
  return Order(
    id: id,
    orderNumber: orderNumber,
    customerId: 'c1',
    customerName: 'Aina',
    customerEmail: 'aina@example.com',
    customerPhone: '0123456789',
    shippingAddress: '1 Jalan Test, KL',
    items: [
      for (var i = 0; i < itemCount; i++)
        OrderItem(
          productId: 'p$i',
          name: 'Item $i',
          image: '',
          unitPrice: 50,
          quantity: 1,
          supplierId: 's1',
        ),
    ],
    status: status,
    paymentMethod: 'fpx',
    subtotal: total,
    shippingFee: 0,
    total: total,
    createdAt: createdAt ?? DateTime(2026, 9, 1),
    statusHistory: statusHistory,
  );
}

RoomDesign _design({
  required String name,
  required DateTime createdAt,
  String roomType = 'living_room',
}) {
  return RoomDesign(
    id: 'd-$name',
    name: name,
    roomType: roomType,
    createdAt: createdAt,
    updatedAt: createdAt,
    userId: 'u1',
  );
}

void main() {
  group('countPurchases', () {
    test('no orders → 0', () {
      expect(countPurchases(const []), 0);
    });

    test('cancelled orders never count (supplier revenue rule)', () {
      final orders = [
        _order(id: 'a', status: OrderStatus.pending),
        _order(id: 'b', status: OrderStatus.shipped),
        _order(id: 'c', status: OrderStatus.delivered),
        _order(id: 'd', status: OrderStatus.cancelled),
      ];
      expect(countPurchases(orders), 3);
    });

    test('all cancelled → 0', () {
      final orders = [
        _order(id: 'a', status: OrderStatus.cancelled),
        _order(id: 'b', status: OrderStatus.cancelled),
      ];
      expect(countPurchases(orders), 0);
    });
  });

  group('buildRecentActivity', () {
    final now = DateTime(2026, 9, 28, 12);

    test('empty sources → empty feed (callers show an empty state)', () {
      final entries = buildRecentActivity(
        orders: const [],
        designs: const [],
        now: now,
      );
      expect(entries, isEmpty);
    });

    test('pending order becomes a "placed" row at createdAt', () {
      final created = DateTime(2026, 9, 27, 9);
      final entries = buildRecentActivity(
        orders: [_order(orderNumber: 'ORD-9', createdAt: created)],
        designs: const [],
        now: now,
      );
      expect(entries, hasLength(1));
      expect(entries.first.kind, ActivityKind.orderPlaced);
      expect(entries.first.title, 'Order ORD-9 placed');
      expect(entries.first.subtitle, '1 item · RM 100');
      expect(entries.first.timestamp, created);
    });

    test('latest status event wins over createdAt for its timestamp', () {
      final shippedAt = DateTime(2026, 9, 26, 15);
      final entries = buildRecentActivity(
        orders: [
          _order(
            status: OrderStatus.shipped,
            createdAt: DateTime(2026, 9, 20),
            statusHistory: {OrderStatus.shipped.name: shippedAt},
          ),
        ],
        designs: const [],
        now: now,
      );
      expect(entries.first.kind, ActivityKind.orderShipped);
      expect(entries.first.title, contains('shipped'));
      expect(entries.first.timestamp, shippedAt);
    });

    test('cancelled orders appear honestly with their own kind', () {
      final entries = buildRecentActivity(
        orders: [_order(status: OrderStatus.cancelled)],
        designs: const [],
        now: now,
      );
      expect(entries.single.kind, ActivityKind.orderCancelled);
      expect(entries.single.title, contains('cancelled'));
    });

    test('multi-item order subtitle counts lines and shows the total', () {
      final entries = buildRecentActivity(
        orders: [_order(itemCount: 3, total: 450)],
        designs: const [],
        now: now,
      );
      expect(entries.single.subtitle, '3 items · RM 450');
    });

    test('saved design becomes a designSaved row', () {
      final savedAt = DateTime(2026, 9, 25, 10);
      final entries = buildRecentActivity(
        orders: const [],
        designs: [
          _design(name: 'Modern Loft', createdAt: savedAt,
              roomType: 'bedroom'),
        ],
        now: now,
      );
      expect(entries.single.kind, ActivityKind.designSaved);
      expect(entries.single.title, 'Saved “Modern Loft”');
      expect(entries.single.subtitle, 'Bedroom design');
      expect(entries.single.timestamp, savedAt);
    });

    test('merges orders and designs newest-first', () {
      final entries = buildRecentActivity(
        orders: [
          _order(
            id: 'old',
            orderNumber: 'ORD-OLD',
            status: OrderStatus.shipped,
            statusHistory: {
              OrderStatus.shipped.name: DateTime(2026, 9, 10),
            },
          ),
          _order(
            id: 'new',
            orderNumber: 'ORD-NEW',
            status: OrderStatus.delivered,
            statusHistory: {
              OrderStatus.delivered.name: DateTime(2026, 9, 27),
            },
          ),
        ],
        designs: [
          _design(name: 'Mid', createdAt: DateTime(2026, 9, 20)),
        ],
        now: now,
      );
      expect(entries.map((e) => e.title).toList(), [
        'Order ORD-NEW delivered',
        'Saved “Mid”',
        'Order ORD-OLD shipped',
      ]);
    });

    test('respects the entry limit', () {
      final entries = buildRecentActivity(
        orders: [
          for (var i = 0; i < 5; i++)
            _order(id: '$i', orderNumber: 'ORD-$i',
                createdAt: DateTime(2026, 9, 1 + i)),
        ],
        designs: const [],
        now: now,
        limit: 3,
      );
      expect(entries, hasLength(3));
      // Newest first: the Sep-5 order survives the cut.
      expect(entries.first.title, 'Order ORD-4 placed');
    });

    test('missing order number never crashes the row builder', () {
      final entries = buildRecentActivity(
        orders: [_order(orderNumber: '')],
        designs: const [],
        now: now,
      );
      expect(entries.single.title, 'Order — placed');
    });
  });

  group('relativeTimeLabel', () {
    final now = DateTime(2026, 9, 28, 12);

    test('within the last minute → Just now', () {
      expect(relativeTimeLabel(now.subtract(const Duration(seconds: 30)), now),
          'Just now');
    });

    test('minutes', () {
      expect(relativeTimeLabel(now.subtract(const Duration(minutes: 5)), now),
          '5m ago');
    });

    test('hours', () {
      expect(relativeTimeLabel(now.subtract(const Duration(hours: 3)), now),
          '3h ago');
    });

    test('yesterday', () {
      expect(relativeTimeLabel(now.subtract(const Duration(hours: 30)), now),
          'Yesterday');
    });

    test('several days', () {
      expect(relativeTimeLabel(now.subtract(const Duration(hours: 50)), now),
          '2d ago');
    });

    test('beyond a week → absolute date', () {
      final at = DateTime(2026, 9, 18, 8);
      expect(relativeTimeLabel(at, now), '18 Sep 2026');
    });

    test('future timestamps (clock skew) read as Just now', () {
      expect(relativeTimeLabel(now.add(const Duration(hours: 3)), now),
          'Just now');
    });
  });

  group('CustomerStats.budgetLabel', () {
    test('saved plan → formatted ringgit', () {
      final stats = CustomerStats(
        purchases: const AsyncData(0),
        savedDesigns: const AsyncData(0),
        wishlist: const AsyncData(0),
        budget: AsyncData<BudgetPlan?>(
          BudgetPlan(
            budgetRm: 4200,
            room: 'Kitchen',
            ecoFriendly: false,
            updatedAt: DateTime(2026, 9, 28),
          ),
        ),
      );
      expect(stats.budgetLabel, 'RM 4,200');
    });

    test('no plan → dash, never a placeholder figure', () {
      final stats = const CustomerStats(
        purchases: AsyncData(0),
        savedDesigns: AsyncData(0),
        wishlist: AsyncData(0),
        budget: AsyncData<BudgetPlan?>(null),
      );
      expect(stats.budgetLabel, 'RM —');
    });
  });
}
