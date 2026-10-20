import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_plan.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/chat_state_context.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/models/cart_item.dart';
import 'package:interior_design_recommendation/models/order.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

Product _product({
  String id = 'p1',
  String name = 'Nordic Sofa',
  int price = 1299,
  String category = 'Furniture',
  bool isActive = true,
  bool isEcoFriendly = false,
}) =>
    Product.fromJson({
      'id': id,
      'name': name,
      'price': price,
      'stock': 5,
      'category': category,
      'description': '',
      'image': '',
      'isActive': isActive,
      'isEcoFriendly': isEcoFriendly,
    });

CartRow _row(Product product, {int qty = 1, bool missing = false}) => CartRow(
      item: CartItem(product: product, quantity: qty),
      live: product,
      missing: missing,
      inactive: false,
    );

Order _order({
  String number = 'A102',
  OrderStatus status = OrderStatus.shipped,
  int total = 890,
  int qty = 2,
  DateTime? createdAt,
}) =>
    Order(
      id: 'o1',
      orderNumber: number,
      customerId: 'c1',
      customerName: 'Ana',
      customerEmail: 'a@b.com',
      customerPhone: '012',
      shippingAddress: 'KL',
      items: [
        OrderItem(
          productId: 'p1',
          name: 'Nordic Sofa',
          image: '',
          unitPrice: total ~/ qty,
          quantity: qty,
          supplierId: 's1',
        ),
      ],
      status: status,
      paymentMethod: 'cod',
      subtotal: total,
      shippingFee: 0,
      total: total,
      createdAt: createdAt ?? DateTime.utc(2026, 10, 1),
    );

RoomDesign _plan({List<FurniturePlacement> furniture = const []}) => RoomDesign(
      id: 'd1',
      name: 'Living Room A',
      roomType: 'living_room',
      widthCm: 400,
      heightCm: 500,
      furniture: furniture,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      userId: 'u1',
    );

BudgetPlan _budget({int cap = 2000, bool eco = false}) => BudgetPlan(
      budgetRm: cap,
      room: 'Kitchen',
      ecoFriendly: eco,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('buildChatStateJson', () {
    test('returns null when every section is empty', () {
      expect(
        buildChatStateJson(
          cartRows: const [],
          cartCount: 0,
          cartSubtotal: 0,
          budget: null,
          orders: const [],
          plan: null,
          pendingPlacements: 0,
          wishlistCount: 0,
        ),
        isNull,
      );
    });

    test('caps cart lines at 8 and clips names to 48 characters', () {
      final rows = [
        for (var i = 0; i < 9; i++)
          _row(
            _product(
              id: 'p$i',
              name: 'Item $i ${'x' * 80}',
              price: 100 + i,
            ),
            qty: 2,
          ),
      ];
      final json = buildChatStateJson(
        cartRows: rows,
        cartCount: 18,
        cartSubtotal: 2000,
        budget: null,
        orders: const [],
        plan: null,
        pendingPlacements: 0,
      )!;
      final cart = json['cart'] as Map<String, Object?>;
      final items = cart['items'] as List;
      expect(items, hasLength(8));
      for (final item in items.cast<Map<String, Object?>>()) {
        expect((item['name'] as String).length, lessThanOrEqualTo(48));
      }
      expect(cart['itemCount'], 18);
      expect(cart['subtotal'], 2000);
    });

    test('caps placed items at 10 and orders at 3', () {
      final furniture = [
        for (var i = 0; i < 12; i++)
          FurniturePlacement(
            id: 'f$i',
            name: 'Sofa $i',
            iconName: 'sofa',
            x: 0,
            y: 0,
            width: 100,
            height: 50,
          ),
      ];
      final orders = [
        for (var i = 0; i < 5; i++)
          _order(
            number: 'A10$i',
            createdAt: DateTime.utc(2026, 1, i + 1),
          ),
      ];
      final json = buildChatStateJson(
        cartRows: const [],
        cartCount: 0,
        cartSubtotal: 0,
        budget: null,
        orders: orders,
        plan: _plan(furniture: furniture),
        pendingPlacements: 2,
        wishlistCount: 5,
      )!;

      final plan = json['plan'] as Map<String, Object?>;
      expect(plan['placed'], hasLength(10));
      expect(plan['pendingPlacements'], 2);
      expect(json['orders'], hasLength(3));
      expect(json['wishlistCount'], 5);
    });

    test('omits the budget section when none is set', () {
      final json = buildChatStateJson(
        cartRows: [_row(_product())],
        cartCount: 1,
        cartSubtotal: 1299,
        budget: null,
        orders: const [],
        plan: null,
        pendingPlacements: 0,
      )!;
      expect(json.containsKey('budget'), isFalse);
    });

    test('a full fixture serialises under 2k chars', () {
      final json = buildChatStateJson(
        cartRows: [
          for (var i = 0; i < 8; i++)
            _row(_product(id: 'p$i', name: 'Lamp $i'), qty: 3),
        ],
        cartCount: 24,
        cartSubtotal: 9800,
        budget: _budget(cap: 5000, eco: true),
        estimateRm: 3200,
        remainingRm: 1800,
        orders: [
          for (var i = 0; i < 3; i++)
            _order(number: 'A10$i', createdAt: DateTime.utc(2026, 10, i + 1)),
        ],
        plan: _plan(furniture: [
          for (var i = 0; i < 10; i++)
            FurniturePlacement(
              id: 'f$i',
              name: 'Chair $i',
              iconName: 'chair',
              x: 0,
              y: 0,
              width: 40,
              height: 40,
            ),
        ]),
        pendingPlacements: 2,
        wishlistCount: 7,
      )!;
      expect(jsonEncode(json).length, lessThan(2000));
    });

    test('budget section carries cap, room, and estimate arithmetic', () {
      final json = buildChatStateJson(
        cartRows: const [],
        cartCount: 0,
        cartSubtotal: 0,
        budget: _budget(cap: 5000, eco: true),
        estimateRm: 3200,
        remainingRm: 1800,
        orders: const [],
        plan: null,
        pendingPlacements: 0,
      )!;
      final budget = json['budget'] as Map<String, Object?>;
      expect(budget['capRm'], 5000);
      expect(budget['room'], 'Kitchen');
      expect(budget['ecoFriendly'], isTrue);
      expect(budget['estimateRm'], 3200);
      expect(budget['remainingRm'], 1800);
    });
  });

  group('budgetEstimate', () {
    test('sums category medians and subtracts from the cap', () {
      final products = [
        _product(id: 'f', category: 'Furniture', price: 1000),
        _product(id: 'l', category: 'Lighting', price: 200),
        _product(id: 'p', category: 'Paint', price: 300),
      ];
      final estimate = budgetEstimate(budget: _budget(cap: 2000), products: products);
      expect(estimate, isNotNull);
      expect(estimate!.$1, 1500);
      expect(estimate.$2, 500);
    });

    test('eco filter drops non-eco listings from the median', () {
      final products = [
        _product(id: 'f1', category: 'Furniture', price: 1000),
        _product(
            id: 'f2', category: 'Furniture', price: 200, isEcoFriendly: true),
      ];
      final normal = budgetEstimate(budget: _budget(cap: 0), products: products);
      expect(normal!.$1, 600);
      final eco = budgetEstimate(
          budget: _budget(cap: 0, eco: true), products: products);
      expect(eco!.$1, 200);
    });

    test('returns null when the catalogue is empty', () {
      expect(budgetEstimate(budget: _budget(), products: const []), isNull);
    });
  });
}
