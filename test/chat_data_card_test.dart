import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_plan.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/widgets/chat_data_card.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/models/cart_item.dart';
import 'package:interior_design_recommendation/models/chat_session.dart';
import 'package:interior_design_recommendation/models/order.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/room_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

Product _product({String id = 'sofa-1', String name = 'Nordic Sofa', int price = 1299}) =>
    Product.fromJson({
      'id': id,
      'name': name,
      'price': price,
      'stock': 4,
      'category': 'Furniture',
      'description': '',
      'image': '',
    });

class _StaticCart extends CartNotifier {
  _StaticCart(this.items);
  final List<CartItem> items;

  @override
  List<CartItem> build() => items;
}

Order _order() => Order(
      id: 'o1',
      orderNumber: 'A102',
      customerId: 'c1',
      customerName: 'Ana',
      customerEmail: 'a@b.com',
      customerPhone: '012',
      shippingAddress: 'KL',
      items: const [
        OrderItem(
          productId: 'sofa-1',
          name: 'Nordic Sofa',
          image: '',
          unitPrice: 890,
          quantity: 2,
          supplierId: 's1',
        ),
      ],
      status: OrderStatus.shipped,
      paymentMethod: 'cod',
      subtotal: 1780,
      shippingFee: 0,
      total: 1780,
      createdAt: DateTime.utc(2026, 10, 1),
    );

RoomDesign _plan() => RoomDesign(
      id: 'd1',
      name: 'Living Room A',
      roomType: 'living_room',
      widthCm: 400,
      heightCm: 500,
      furniture: const [
        FurniturePlacement(
          id: 'f1',
          name: 'Sofa',
          iconName: 'sofa',
          x: 0,
          y: 0,
          width: 180,
          height: 90,
        ),
      ],
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      userId: 'u1',
    );

Future<void> _pumpCard(
  WidgetTester tester,
  ChatDataTopic topic, {
  List<CartItem> cart = const [],
  BudgetPlan? budget,
  List<Product> products = const [],
  List<RoomDesign> designs = const [],
  List<Order> orders = const [],
  Set<String> wishlist = const {},
}) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        marketplaceProductsProvider
            .overrideWith((ref) => Stream.value(products)),
        cartProvider.overrideWith(() => _StaticCart(cart)),
        budgetPlanProvider.overrideWith((ref) => Stream.value(budget)),
        savedDesignsProvider.overrideWith((ref) => Stream.value(designs)),
        customerOrdersProvider.overrideWith((ref) => Stream.value(orders)),
        wishlistProvider.overrideWith(() => _StaticWishlist(wishlist)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ChatDataCard(topic: topic),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _StaticWishlist extends WishlistNotifier {
  _StaticWishlist(this.ids);
  final Set<String> ids;

  @override
  Set<String> build() => ids;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('cart card shows live line totals and the subtotal', (tester) async {
    await _pumpCard(
      tester,
      ChatDataTopic.cart,
      cart: [
        CartItem(product: _product(), quantity: 2),
        CartItem(
            product: _product(id: 'lamp-1', name: 'Arc Lamp', price: 600),
            quantity: 1),
      ],
      products: [
        _product(),
        _product(id: 'lamp-1', name: 'Arc Lamp', price: 600),
      ],
    );

    expect(find.text('Your cart'), findsOneWidget);
    expect(find.textContaining('Nordic Sofa ×2'), findsOneWidget);
    expect(find.textContaining('Arc Lamp ×1'), findsOneWidget);
    expect(find.textContaining('RM 2,598'), findsOneWidget);
    expect(find.textContaining('3 items'), findsOneWidget);
    expect(find.textContaining('RM 3,198'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('budget card separates the cap from the catalogue estimate',
      (tester) async {
    await _pumpCard(
      tester,
      ChatDataTopic.budget,
      budget: BudgetPlan(
        budgetRm: 2000,
        room: 'Kitchen',
        ecoFriendly: false,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      products: [
        _product(price: 1000),
        _product(id: 'l1', price: 200),
      ],
    );

    expect(find.text('Your budget'), findsOneWidget);
    expect(find.textContaining('Cap RM 2,000'), findsOneWidget);
    expect(find.textContaining('Catalogue median estimate'), findsOneWidget);
    expect(find.textContaining('spent'), findsNothing);
  });

  testWidgets('budget card says so when no budget is set', (tester) async {
    await _pumpCard(tester, ChatDataTopic.budget);
    expect(find.text('No budget set yet.'), findsOneWidget);
  });

  testWidgets('plan card lists the saved plan and pending placements',
      (tester) async {
    await _pumpCard(tester, ChatDataTopic.plan, designs: [_plan()]);
    expect(find.text('Your room plan'), findsOneWidget);
    expect(find.textContaining('Living Room A'), findsOneWidget);
    expect(find.textContaining('400×500 cm'), findsOneWidget);
    expect(find.textContaining('Sofa 180×90 cm'), findsOneWidget);
  });

  testWidgets('orders card shows the newest statuses with money', (tester) async {
    await _pumpCard(tester, ChatDataTopic.orders, orders: [_order()]);
    expect(find.text('Your recent orders'), findsOneWidget);
    expect(find.textContaining('Shipped'), findsOneWidget);
    expect(find.textContaining('RM 1,780'), findsOneWidget);
  });

  testWidgets('wishlist card counts saved items', (tester) async {
    await _pumpCard(tester, ChatDataTopic.wishlist, wishlist: {'a', 'b', 'c'});
    expect(find.text('Your wishlist'), findsOneWidget);
    expect(find.textContaining('3 saved items'), findsOneWidget);
  });

  testWidgets('wishlist card handles the empty state', (tester) async {
    await _pumpCard(tester, ChatDataTopic.wishlist);
    expect(find.text('Nothing saved yet.'), findsOneWidget);
  });
}
