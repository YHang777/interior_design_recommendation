import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/core/theme/app_theme.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/features/supplier/presentation/screens/product_management_screen.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/shared/widgets/stat_card.dart';

/// Guards the "the whole screen is empty" report on Supplier → Products.
///
/// Two things used to blank or gut this page and both are pinned here:
/// 1. a layout exception anywhere in the ListView children (the themed
///    `ElevatedButton` with infinite min-width) blanked the ENTIRE body;
/// 2. an empty catalogue replaced the whole body with a bare EmptyState,
///    dropping the heading and the stats row with it.
void main() {
  const me = 'seller-1';

  final user = AppUser(
    uid: me,
    email: 'seller@test.com',
    name: 'Test Seller',
    role: UserRole.supplier,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  Product product(
    String id,
    String name, {
    int stock = 10,
    String owner = me,
    int? originalPrice,
    int shippingFee = 0,
  }) {
    return Product(
      id: id,
      name: name,
      price: 1250,
      originalPrice: originalPrice,
      stock: stock,
      image: '',
      description: 'A test product',
      designStyle: 'Modern',
      category: 'Furniture',
      supplier: Supplier(
        id: owner,
        name: 'Test Supplier',
        phone: '',
        address: '',
        email: 'seller@test.com',
      ),
      supplierId: owner,
      shippingEnabled: shippingFee > 0,
      shippingFee: shippingFee,
    );
  }

  Future<void> pumpScreen(WidgetTester tester, List<Product> products,
      {AppUser? signedIn, bool useDefaultUser = true, Size? surface}) async {
    tester.view.physicalSize = surface ?? const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider
              .overrideWithValue(useDefaultUser ? (signedIn ?? user) : signedIn),
          marketplaceProductsProvider
              .overrideWith((ref) => Stream<List<Product>>.value(products)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ProductManagementScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder statCards() => find.byType(StatCard);

  testWidgets('populated catalogue paints heading, stats, chips and tiles',
      (tester) async {
    await pumpScreen(tester, [
      product('p1', 'Nordic Oak Table', stock: 12),
      product('p2', 'Velvet Lounge Chair', stock: 3), // low stock
    ]);

    expect(tester.takeException(), isNull,
        reason: 'a child of the products ListView threw during build/layout — '
            'that is what blanks the whole body');

    // The page CONTENT — not an empty state, not a bare Scaffold.
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Add product'), findsOneWidget);

    // Stats row is present and correct (Total 2, Active 2, Low 1).
    expect(statCards(), findsNWidgets(3));
    expect(tester.widget<StatCard>(statCards().at(0)).label, 'Total products');
    expect(tester.widget<StatCard>(statCards().at(0)).value, '2');
    expect(tester.widget<StatCard>(statCards().at(1)).value, '2');
    expect(tester.widget<StatCard>(statCards().at(2)).value, '1');

    expect(find.text('Search your products…'), findsOneWidget);
    expect(find.text('Nordic Oak Table'), findsOneWidget);
    expect(find.text('Velvet Lounge Chair'), findsOneWidget);

    // No empty-state copy on a populated catalogue.
    expect(find.text('No products yet'), findsNothing);
    expect(find.text('Not signed in'), findsNothing);
    expect(find.text('Could not load products'), findsNothing);
  });

  testWidgets('empty catalogue keeps the page chrome instead of going bare',
      (tester) async {
    await pumpScreen(tester, [
      product('p1', 'Someone Elses Sofa', owner: 'other-seller'),
    ]);

    expect(tester.takeException(), isNull);

    // Heading, stats and the add affordance STAY on screen.
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Add product'), findsOneWidget);
    expect(statCards(), findsNWidgets(3));
    expect(tester.widget<StatCard>(statCards().at(0)).value, '0');
    expect(find.text('Search your products…'), findsOneWidget);

    // The list area explains WHY it is empty.
    expect(find.text('No products yet'), findsOneWidget);
    expect(find.textContaining('none of them belong to this account'),
        findsOneWidget);
    expect(find.text('Add your first product'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('brand-new seller sees the same chrome and the onboarding copy',
      (tester) async {
    await pumpScreen(tester, const []);

    expect(tester.takeException(), isNull);
    expect(find.text('Products'), findsOneWidget);
    expect(statCards(), findsNWidgets(3));
    expect(find.text('No products yet'), findsOneWidget);
    expect(find.textContaining('Post your first product'), findsOneWidget);
    expect(find.text('Add your first product'), findsOneWidget);
  });

  testWidgets('a filter that matches nothing offers Clear filters',
      (tester) async {
    await pumpScreen(tester, [
      product('p1', 'Nordic Oak Table', stock: 12), // active, not paused
    ]);

    // Tap the "Paused" filter chip (it is the 3rd chip; the 4th is outside
    // the horizontal ListView's build window until scrolled).
    await tester.tap(find.text('Paused'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No products match this filter'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
    expect(find.text('No products yet'), findsNothing);

    // Clear filters brings the product back.
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Nordic Oak Table'), findsOneWidget);
  });

  testWidgets('signed-out state is explained, not blank', (tester) async {
    await pumpScreen(tester, const [], useDefaultUser: false);

    expect(tester.takeException(), isNull);
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Products'), findsNothing);
  });

  testWidgets('rich product data (discount, shipping, stock pills) renders',
      (tester) async {
    await pumpScreen(tester, [
      product('p1', 'Handcrafted Walnut Dining Table With Very Long Name',
          stock: 0, originalPrice: 2500, shippingFee: 45),
      product('p2', 'Velvet Lounge Chair', stock: 3, originalPrice: 1500),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('-50%'), findsOneWidget);
    expect(find.textContaining('Out of stock'), findsOneWidget);
    expect(find.textContaining('Shipping'), findsOneWidget);
  });

  testWidgets('populated catalogue also renders at 320dp', (tester) async {
    await pumpScreen(
      tester,
      [
        product('p1', 'Nordic Oak Table', stock: 12),
        product('p2', 'Velvet Lounge Chair', stock: 3),
      ],
      surface: const Size(320, 640),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Nordic Oak Table'), findsOneWidget);
    expect(find.text('Add product'), findsOneWidget);
    expect(statCards(), findsNWidgets(3));
  });
}
