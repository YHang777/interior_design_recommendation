import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/core/theme/app_theme.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/screens/buyer_order_detail_screen.dart';
import 'package:interior_design_recommendation/models/app_config_data.dart';
import 'package:interior_design_recommendation/models/order.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/review.dart';
import 'package:interior_design_recommendation/services/marketplace_repository.dart';

final AppUser _buyer = AppUser(
  uid: 'buyer-1',
  email: 'aina@example.com',
  name: 'Aina',
  role: UserRole.homeowner,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Order _order({OrderStatus status = OrderStatus.pending, int itemCount = 2}) {
  return Order(
    id: 'o-1',
    orderNumber: 'ORD-20261014-1234',
    customerId: _buyer.uid,
    customerName: _buyer.name,
    customerEmail: _buyer.email,
    customerPhone: '0123456789',
    shippingAddress: '1 Jalan Test, Kuala Lumpur',
    items: [
      for (var i = 0; i < itemCount; i++)
        OrderItem(
          productId: 'p-$i',
          name: 'Test Product $i',
          image: '',
          unitPrice: 100,
          quantity: 1,
          supplierId: 's-ghost',
        ),
    ],
    status: status,
    paymentMethod: 'fpx',
    subtotal: 100 * itemCount,
    shippingFee: 0,
    total: 100 * itemCount,
    discount: 0,
    tax: 0,
    supplierIds: const ['s-ghost'],
    shippingBySupplier: const {},
    createdAt: DateTime(2026, 10, 1),
    invoices: const {},
  );
}

class _FakeMarketplaceRepository implements MarketplaceRepository {
  _FakeMarketplaceRepository({
    required this.order,
    Map<String, Review>? reviews,
  }) : reviews = reviews ?? {};

  Order order;

  final Map<String, Review> reviews;
  final List<Review> filedReviews = [];
  final List<OrderStatus> statusChanges = [];
  final StreamController<Order> _orderChanges = StreamController<Order>.broadcast();

  void dispose() {
    _orderChanges.close();
  }

  @override
  Stream<Order?> watchOrder(String orderId) async* {
    yield order;
    yield* _orderChanges.stream;
  }

  @override
  Stream<List<Product>> watchProducts() =>
      Stream<List<Product>>.value(const <Product>[]);

  @override
  Future<AppConfigData> fetchConfig() async => const AppConfigData(
        shippingFee: 25,
        freeShippingThreshold: 500,
        currency: 'MYR',
        taxRate: 0.06,
        membershipTiers: [],
      );

  @override
  Future<Review?> fetchReviewForOrder(String productId, String orderId) async =>
      reviews[productId];

  @override
  Future<void> addReview(String productId, Review review) async {
    filedReviews.add(review);
    reviews[productId] = review;
  }

  @override
  Future<Order> updateOrderStatus(String orderId, OrderStatus status) async {
    statusChanges.add(status);
    order = order.copyWith(status: status);
    _orderChanges.add(order);
    return order;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('fake repo did not stub ${invocation.memberName}');
}

Future<void> _pumpOrderDetail(
  WidgetTester tester,
  _FakeMarketplaceRepository repo,
) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(repo.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        marketplaceRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(_buyer),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: BuyerOrderDetailScreen(orderId: repo.order.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('review aggregate math', () {
    test('a virgin listing (0.0 / 0) takes the first review outright', () {
      expect(rollingRating(ratingCount: 0, rating: 0.0, added: 5), 5.0);
      expect(rollingRating(ratingCount: 0, rating: 0.0, added: 4), 4.0);
    });

    test('later reviews roll over the stored sum, rounded to one decimal', () {
      expect(rollingRating(ratingCount: 2, rating: 4.5, added: 1), 3.3);
      expect(rollingRating(ratingCount: 1, rating: 4.0, added: 5), 4.5);
    });

    test('aggregateForRatings recomputes from the actual review docs', () {
      expect(
        aggregateForRatings(const []),
        (rating: 0.0, ratingCount: 0),
      );
      expect(
        aggregateForRatings(const [5, 4]),
        (rating: 4.5, ratingCount: 2),
      );
      expect(
        aggregateForRatings(const [5, 4, 4]),
        (rating: 4.3, ratingCount: 3),
      );
    });

    test('backfill target replaces a fabricated 4.5 (12) honestly', () {
      expect(
        aggregateForRatings(const [5]),
        (rating: 5.0, ratingCount: 1),
      );
      expect(
        aggregateForRatings(const []),
        (rating: 0.0, ratingCount: 0),
      );
    });
  });

  group('buyer order-detail review entry gating', () {
    testWidgets('an undelivered order offers no review entry', (tester) async {
      final repo =
          _FakeMarketplaceRepository(order: _order(status: OrderStatus.pending));
      await _pumpOrderDetail(tester, repo);

      expect(find.text('Rate your items'), findsNothing);
      expect(find.text('Write review'), findsNothing);
      expect(find.text('Confirm delivery'), findsNothing);
      expect(find.text('Cancel order'), findsOneWidget);
    });

    testWidgets('a delivered order lists each item for review, honoring '
        'already-filed reviews', (tester) async {
      final repo = _FakeMarketplaceRepository(
        order: _order(status: OrderStatus.delivered),
        reviews: {
          'p-0': Review(
            id: 'o-1',
            orderId: 'o-1',
            userId: _buyer.uid,
            userName: _buyer.name,
            rating: 5,
            comment: 'Lovely seat, fast delivery.',
            createdAt: DateTime(2026, 10, 2),
          ),
        },
      );
      await _pumpOrderDetail(tester, repo);

      expect(find.text('Rate your items'), findsOneWidget);
      expect(find.text('Write review'), findsOneWidget);
      expect(find.text('Reviewed ✓'), findsOneWidget);
      expect(find.text('Confirm delivery'), findsNothing);
    });

    testWidgets('a shipped order can be delivered by the buyer, unlocking '
        'the review entry', (tester) async {
      final repo =
          _FakeMarketplaceRepository(order: _order(status: OrderStatus.shipped));
      await _pumpOrderDetail(tester, repo);

      expect(find.text('Rate your items'), findsNothing);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm delivery'));
      await tester.pumpAndSettle();

      final dialogConfirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Confirm delivery'),
      );
      expect(dialogConfirm, findsOneWidget);
      await tester.tap(dialogConfirm);
      await tester.pumpAndSettle();

      expect(repo.statusChanges, [OrderStatus.delivered]);
      expect(find.text('Rate your items'), findsOneWidget);
      expect(find.text('Write review'), findsNWidgets(2));
    });

    testWidgets('the review sheet files an order-tied star review against '
        'the product', (tester) async {
      final repo = _FakeMarketplaceRepository(
        order: _order(status: OrderStatus.delivered),
      );
      await _pumpOrderDetail(tester, repo);

      await tester.tap(find.text('Write review').first);
      await tester.pumpAndSettle();

      expect(find.text('Tap the stars to rate'), findsOneWidget);
      final disabledSubmit = find.text('Tap the stars to rate');
      expect(
        tester.widget<ElevatedButton>(
          find.ancestor(
            of: disabledSubmit,
            matching: find.byType(ElevatedButton),
          ),
        ).onPressed,
        isNull,
      );

      await tester.tap(find.byIcon(Icons.star_border).at(3));
      await tester.pump();
      await tester.enterText(
        find.byType(TextField),
        'Really comfortable and sturdy.',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit review'));
      await tester.pumpAndSettle();

      expect(repo.filedReviews, hasLength(1));
      final filed = repo.filedReviews.single;
      expect(filed.id, 'o-1');
      expect(filed.orderId, 'o-1');
      expect(filed.rating, 4);
      expect(filed.comment, 'Really comfortable and sturdy.');
      expect(repo.reviews.keys, contains('p-0'));

      expect(find.text('Reviewed ✓'), findsOneWidget);
      expect(find.text('Write review'), findsOneWidget);
    });
  });
}
