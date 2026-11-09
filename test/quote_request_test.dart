import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/core/theme/app_theme.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/screens/order_history_screen.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/screens/product_detail_screen.dart';
import 'package:interior_design_recommendation/features/supplier/presentation/screens/quote_request_detail_screen.dart';
import 'package:interior_design_recommendation/features/supplier/presentation/screens/quote_requests_screen.dart';
import 'package:interior_design_recommendation/models/app_config_data.dart';
import 'package:interior_design_recommendation/models/cart_item.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/quote_request.dart';
import 'package:interior_design_recommendation/models/review.dart';
import 'package:interior_design_recommendation/services/marketplace_repository.dart';

final _day = DateTime(2026, 1, 1);

final _buyer = AppUser(
  uid: 'buyer-1',
  email: 'aina@example.com',
  name: 'Aina',
  role: UserRole.homeowner,
  phone: '0123456789',
  createdAt: _day,
  updatedAt: _day,
);

final _buyerNoPhone = AppUser(
  uid: 'buyer-2',
  email: 'baru@example.com',
  name: 'Baru',
  role: UserRole.homeowner,
  createdAt: _day,
  updatedAt: _day,
);

final _supplier = AppUser(
  uid: 'sup-1',
  email: 'seller@example.com',
  name: 'Kedai Furnitur',
  role: UserRole.supplier,
  createdAt: _day,
  updatedAt: _day,
);

Product _product() => Product(
      id: 'p-1',
      name: 'Oak Dining Table',
      price: 1200,
      stock: 20,
      image: '',
      description: 'Solid oak three-seater.',
      designStyle: 'Modern',
      category: 'Furniture',
      supplier: const Supplier(
        id: 'sup-1',
        name: 'Kedai Furnitur',
        phone: '0312345678',
        address: 'Shah Alam',
        email: 'seller@example.com',
      ),
      supplierId: 'sup-1',
    );

QuoteRequest _request({
  String id = 'q-1',
  String status = QuoteRequest.statusSubmitted,
  int quantity = 20,
  String note = '20 units, delivery to Johor',
  DateTime? contactedAt,
}) =>
    QuoteRequest(
      id: id,
      productId: 'p-1',
      productName: 'Oak Dining Table',
      productImage: '',
      supplierId: 'sup-1',
      customerId: 'buyer-1',
      customerName: 'Aina',
      customerEmail: 'aina@example.com',
      customerPhone: '0123456789',
      quantity: quantity,
      note: note,
      status: status,
      createdAt: DateTime(2026, 11, 1),
      contactedAt: contactedAt,
    );

class _FakeMarketplaceRepository implements MarketplaceRepository {
  _FakeMarketplaceRepository({List<Product>? products, List<QuoteRequest>? quotes})
      : products = products ?? const [],
        quotes = quotes ?? const [];

  final List<Product> products;
  final List<QuoteRequest> quotes;
  final List<QuoteRequest> created = [];
  final List<String> contactedIds = [];

  @override
  Future<void> createQuoteRequest(QuoteRequest request) async {
    created.add(request);
  }

  @override
  Future<void> markQuoteContacted(String id) async {
    contactedIds.add(id);
  }

  @override
  Stream<List<QuoteRequest>> watchCustomerQuoteRequests(String customerId) =>
      Stream.value(quotes);

  @override
  Stream<List<QuoteRequest>> watchSupplierQuoteRequests(String supplierId) =>
      Stream.value(quotes);

  @override
  Stream<List<Product>> watchProducts() => Stream.value(products);

  @override
  Stream<List<Review>> watchReviews(String productId) =>
      Stream.value(const []);

  @override
  Stream<List<String>> watchWishlistIds(String uid) => Stream.value(const []);

  @override
  Stream<List<CartItem>> watchCart(String uid) => Stream.value(const []);

  @override
  Future<AppConfigData> fetchConfig() async => const AppConfigData(
        currency: 'MYR',
        taxRate: 0.06,
        membershipTiers: [],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('fake repo did not stub ${invocation.memberName}');
}

Future<void> _pumpProductDetail(
  WidgetTester tester,
  _FakeMarketplaceRepository repo, {
  AppUser? user,
}) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        marketplaceRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(user ?? _buyer),
        marketplaceProductsProvider
            .overrideWith((ref) => Stream.value(repo.products)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        // The floating robot avatar bobs forever and stalls pumpAndSettle —
        // the same disableAnimations wrap robot_assistant_test uses.
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: ProductDetailScreen(productId: 'p-1'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openQuoteDialog(WidgetTester tester) async {
  final cta = find.text('Request bulk quote');
  expect(cta, findsOneWidget);
  // The gallery's PageView adds a nested Scrollable inside the same
  // CustomScrollView — pin the scrollable that actually contains the CTA.
  await tester.scrollUntilVisible(
    cta,
    400,
    scrollable: find.ancestor(of: cta, matching: find.byType(Scrollable)),
  );
  await tester.tap(cta);
  await tester.pumpAndSettle();
}

Future<void> _pumpOrderHistory(
  WidgetTester tester, {
  required List<QuoteRequest> quotes,
}) async {
  tester.view.physicalSize = const Size(700, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(_buyer),
        customerOrdersProvider.overrideWith((ref) => Stream.value(const [])),
        customerQuoteRequestsProvider
            .overrideWith((ref) => Stream.value(quotes)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const OrderHistoryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Quotes'));
  await tester.pumpAndSettle();
}

Future<void> _pumpSupplierScreen(
  WidgetTester tester,
  _FakeMarketplaceRepository repo,
  Widget screen,
) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        marketplaceRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(_supplier),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('QuoteRequest serialization', () {
    test('round-trips every field through toJson/fromJson', () {
      final request = _request(
        status: QuoteRequest.statusContacted,
        contactedAt: DateTime(2026, 11, 3, 9, 15),
      );

      final back = QuoteRequest.fromJson(request.toJson());

      expect(back.id, request.id);
      expect(back.productId, request.productId);
      expect(back.productName, request.productName);
      expect(back.productImage, request.productImage);
      expect(back.supplierId, request.supplierId);
      expect(back.customerId, request.customerId);
      expect(back.customerName, request.customerName);
      expect(back.customerEmail, request.customerEmail);
      expect(back.customerPhone, request.customerPhone);
      expect(back.quantity, request.quantity);
      expect(back.note, request.note);
      expect(back.status, request.status);
      expect(back.createdAt.isAtSameMomentAs(request.createdAt), isTrue);
      expect(back.contactedAt!.isAtSameMomentAs(request.contactedAt!), isTrue);
      expect(back.isContacted, isTrue);
    });

    test('toJson writes ISO strings and omits a null contactedAt', () {
      final json = _request().toJson();
      expect(json['createdAt'], isA<String>());
      expect(json.containsKey('contactedAt'), isFalse);
    });

    test('reads Firestore Timestamps written by markQuoteContacted', () {
      final created = DateTime.utc(2026, 11, 9, 8, 30);
      final contacted = created.add(const Duration(days: 1));
      final request = QuoteRequest.fromJson({
        'id': 'q-9',
        'productId': 'p-1',
        'productName': 'Pendant Lamp',
        'supplierId': 'sup-1',
        'customerId': 'buyer-1',
        'customerName': 'Aina',
        'customerEmail': 'aina@example.com',
        'customerPhone': '0123456789',
        'quantity': 7,
        'status': 'contacted',
        'createdAt': Timestamp.fromDate(created),
        'contactedAt': Timestamp.fromDate(contacted),
      });

      expect(request.createdAt.isAtSameMomentAs(created), isTrue);
      expect(request.contactedAt!.isAtSameMomentAs(contacted), isTrue);
      expect(request.isContacted, isTrue);
      expect(request.productImage, isNull);
      expect(request.note, '');
    });

    test('legacy docs missing optional fields get safe defaults', () {
      final request = QuoteRequest.fromJson({
        'id': 'q-2',
        'productId': 'p-1',
        'productName': 'Study Chair',
        'supplierId': 'sup-1',
        'customerId': 'buyer-1',
        'createdAt': '2026-11-01T00:00:00.000Z',
      });

      expect(request.status, QuoteRequest.statusSubmitted);
      expect(request.quantity, 1);
      expect(request.note, '');
      expect(request.productImage, isNull);
      expect(request.contactedAt, isNull);
      expect(request.isContacted, isFalse);
      expect(request.createdAt.toUtc().year, 2026);
    });
  });

  group('customer bulk-quote CTA', () {
    testWidgets('files a submitted request and confirms with a notice',
        (tester) async {
      final repo = _FakeMarketplaceRepository(products: [_product()]);
      await _pumpProductDetail(tester, repo);
      await _openQuoteDialog(tester);

      expect(
        find.text('The supplier will contact you personally by phone or '
            'email.'),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pump();
      await tester.enterText(
        find.byType(TextField).last,
        'Need 20 units delivered to Johor.',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send request'));
      await tester.pumpAndSettle();

      expect(repo.created, hasLength(1));
      final filed = repo.created.single;
      expect(filed.customerId, 'buyer-1');
      expect(filed.supplierId, 'sup-1');
      expect(filed.productId, 'p-1');
      expect(filed.status, QuoteRequest.statusSubmitted);
      expect(filed.quantity, 2);
      expect(filed.customerPhone, '0123456789');
      expect(filed.customerName, 'Aina');
      expect(filed.note, 'Need 20 units delivered to Johor.');
      expect(filed.id, isNotEmpty);

      expect(
        find.text('Quote request sent — the supplier will contact you '
            'directly'),
        findsOneWidget,
      );
      expect(find.text('View my quotes'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('blocks submit while the phone number is empty',
        (tester) async {
      final repo = _FakeMarketplaceRepository(products: [_product()]);
      await _pumpProductDetail(tester, repo, user: _buyerNoPhone);
      await _openQuoteDialog(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Send request'));
      await tester.pumpAndSettle();

      expect(
        find.text('Add your phone number so the supplier can reach you.'),
        findsOneWidget,
      );
      expect(repo.created, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('customer Quotes tab', () {
    testWidgets('explains both statuses in buyer-facing wording',
        (tester) async {
      await _pumpOrderHistory(tester, quotes: [
        _request(),
        _request(
          id: 'q-2',
          status: QuoteRequest.statusContacted,
          quantity: 5,
          note: '',
          contactedAt: DateTime(2026, 11, 3),
        ),
      ]);

      expect(find.text('Oak Dining Table'), findsNWidgets(2));
      expect(find.text('Qty 20'), findsOneWidget);
      expect(find.text('20 units, delivery to Johor'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Contacted'), findsOneWidget);
      expect(find.text('Supplier will contact you'), findsOneWidget);
      expect(
        find.text('The supplier has reached out to you'),
        findsOneWidget,
      );
    });

    testWidgets('empty state tells buyers how to send one', (tester) async {
      await _pumpOrderHistory(tester, quotes: const []);

      expect(find.text('No quote requests yet'), findsOneWidget);
      expect(
        find.textContaining('Request bulk quote'),
        findsOneWidget,
      );
    });
  });

  group('supplier quote inbox', () {
    testWidgets('renders the off-app banner and request tiles',
        (tester) async {
      final repo = _FakeMarketplaceRepository(quotes: [_request()]);
      await _pumpSupplierScreen(tester, repo, const QuoteRequestsScreen());

      expect(
        find.text('Contact buyers outside the app — call or email them '
            'directly. Payment and delivery are arranged with the buyer.'),
        findsOneWidget,
      );
      expect(find.text('Oak Dining Table'), findsOneWidget);
      expect(find.text('Qty 20 · Aina'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('No quote requests yet'), findsNothing);
    });

    testWidgets('empty inbox says what will show up here', (tester) async {
      final repo = _FakeMarketplaceRepository();
      await _pumpSupplierScreen(tester, repo, const QuoteRequestsScreen());

      expect(find.text('No quote requests yet'), findsOneWidget);
      expect(
        find.textContaining('When buyers ask for bulk pricing'),
        findsOneWidget,
      );
    });

    testWidgets('Mark as contacted records the id and confirms',
        (tester) async {
      final repo = _FakeMarketplaceRepository(quotes: [_request()]);
      await _pumpSupplierScreen(
        tester,
        repo,
        const QuoteRequestDetailScreen(requestId: 'q-1'),
      );

      expect(find.text('Mark as contacted'), findsOneWidget);
      expect(find.text('Contacted ✓'), findsNothing);
      expect(find.text('aina@example.com'), findsOneWidget);
      expect(find.textContaining('Contact the buyer outside the app'),
          findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Mark as contacted'));
      await tester.pumpAndSettle();

      expect(repo.contactedIds, ['q-1']);
      expect(find.text('Contacted ✓'), findsOneWidget);
      expect(find.text('Mark as contacted'), findsNothing);
    });
  });
}
