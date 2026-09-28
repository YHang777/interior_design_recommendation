// Widget tests for the homeowner dashboard's real stats layer.
//
// All live sources are overridden with real-shaped data, so the tests
// prove the screen renders what the providers actually return — and that
// none of the old hardcoded figures ("RM 5.2K", "Order #1234 Shipped", …)
// can ever come back.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_plan.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/screens/dashboard_screen.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/models/order.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

AppUser _user() => AppUser(
      uid: 'u1',
      email: 'aina@example.com',
      name: 'Aina',
      role: UserRole.homeowner,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Order _order({
  String id = 'o1',
  required String orderNumber,
  required OrderStatus status,
  required DateTime createdAt,
  Map<String, DateTime> statusHistory = const {},
  int total = 100,
}) {
  return Order(
    id: id,
    orderNumber: orderNumber,
    customerId: 'u1',
    customerName: 'Aina',
    customerEmail: 'aina@example.com',
    customerPhone: '0123456789',
    shippingAddress: '1 Jalan Test, KL',
    items: const [
      OrderItem(
        productId: 'p1',
        name: 'Item',
        image: '',
        unitPrice: 100,
        quantity: 1,
        supplierId: 's1',
      ),
    ],
    status: status,
    paymentMethod: 'fpx',
    subtotal: total,
    shippingFee: 0,
    total: total,
    createdAt: createdAt,
    statusHistory: statusHistory,
  );
}

RoomDesign _design(String name, DateTime createdAt) => RoomDesign(
      id: 'd-$name',
      name: name,
      roomType: 'living_room',
      createdAt: createdAt,
      updatedAt: createdAt,
      userId: 'u1',
    );

Future<void> _pump(WidgetTester tester, {required List<Override> overrides}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
    ),
  );
  // Let the StreamValues / errors resolve and the rebuild land.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('renders live provider values, not hardcoded stats',
      (tester) async {
    final now = DateTime.now();

    await _pump(tester, overrides: [
      currentUserProvider.overrideWithValue(_user()),
      customerOrdersProvider.overrideWith((ref) => Stream.value([
        _order(
          orderNumber: 'ORD-42',
          status: OrderStatus.delivered,
          statusHistory: {
            OrderStatus.delivered.name:
                now.subtract(const Duration(hours: 1)),
          },
          createdAt: now.subtract(const Duration(days: 2)),
          total: 420,
        ),
        _order(
          id: 'o2',
          orderNumber: 'ORD-99',
          status: OrderStatus.cancelled,
          createdAt: now.subtract(const Duration(days: 3)),
        ),
      ])),
      savedDesignsProvider.overrideWith((ref) => Stream.value([
        _design('Modern Loft', now.subtract(const Duration(hours: 2))),
      ])),
      budgetPlanProvider.overrideWith((ref) => Stream.value(BudgetPlan(
            budgetRm: 4200,
            room: 'Kitchen',
            ecoFriendly: false,
            updatedAt: now,
          ))),
      wishlistCountProvider.overrideWithValue(0),
    ]);

    // Budget tile ← budgetPlanProvider (users/{uid}.budgetPlan).
    expect(find.text('RM 4,200'), findsOneWidget);

    // Purchases: 2 orders − 1 cancelled = 1. Saved Designs: 1 design = 1.
    expect(find.text('1'), findsNWidgets(2));

    // Real activity rows, newest first.
    expect(find.text('Order ORD-42 delivered'), findsOneWidget);
    expect(find.text('Saved “Modern Loft”'), findsOneWidget);
    expect(find.text('1 item · RM 420'), findsOneWidget);

    // The old hardcoded stats can never come back.
    expect(find.text('RM 5.2K'), findsNothing);
    expect(find.text('Order #1234 Shipped'), findsNothing);
    expect(find.text('Budget Alert'), findsNothing);
    expect(find.text('Kitchen renovation over budget'), findsNothing);
    expect(find.text('New design saved'), findsNothing);
    expect(find.text('Modern Living Room'), findsNothing);
    expect(find.text('3'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('empty account shows zeros, a dash and a real empty state',
      (tester) async {
    await _pump(tester, overrides: [
      currentUserProvider.overrideWithValue(_user()),
      customerOrdersProvider.overrideWith((ref) => Stream.value(const [])),
      savedDesignsProvider.overrideWith((ref) => Stream.value(const [])),
      budgetPlanProvider.overrideWith((ref) => Stream.value(null)),
      wishlistCountProvider.overrideWithValue(0),
    ]);

    // No saved budget → dash, never a placeholder figure.
    expect(find.text('RM —'), findsOneWidget);
    // Real zeroes for purchases and saved designs.
    expect(find.text('0'), findsNWidgets(2));
    // Proper empty state instead of invented activity rows.
    expect(find.text('No activity yet'), findsOneWidget);
    expect(find.text('RM 5.2K'), findsNothing);
    expect(find.text('Order #1234 Shipped'), findsNothing);
  });

  testWidgets('a failed orders stream shows error states without crashing',
      (tester) async {
    await _pump(tester, overrides: [
      currentUserProvider.overrideWithValue(_user()),
      customerOrdersProvider
          .overrideWith((ref) => Stream<List<Order>>.error(Exception('x'))),
      savedDesignsProvider.overrideWith((ref) => Stream.value(const [])),
      budgetPlanProvider.overrideWith((ref) => Stream.value(null)),
      wishlistCountProvider.overrideWithValue(0),
    ]);

    // Purchases tile → dash; saved designs still a real 0.
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    // Feed shows a retryable error card instead of partial fake rows.
    expect(find.text('Could not load activity'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('RM 5.2K'), findsNothing);
  });
}
