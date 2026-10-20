import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:interior_design_recommendation/app.dart';
import 'package:interior_design_recommendation/core/router/app_router.dart';
import 'package:interior_design_recommendation/features/auth/data/datasources/account_deletion_datasource.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/domain/repositories/auth_repository.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/stats/customer_stats.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/stats/stats_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/screens/ai_recommendation_screen.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/screens/marketplace_screen.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/room_scanner_screen.dart';
import 'package:interior_design_recommendation/models/cart_item.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/product_category.dart';
import 'package:interior_design_recommendation/shared/widgets/floating_nav_bar.dart';

Product _product(String id, String name) => Product.fromJson({
      'id': id,
      'name': name,
      'price': 899,
      'stock': 5,
      'category': 'Sofa',
      'designStyle': 'Scandinavian',
      'description': 'Test listing.',
      'image': '',
    });

class _LocalCart extends CartNotifier {
  @override
  List<CartItem> build() => [];
}

Future<void> _settle(WidgetTester tester, {int frames = 8}) async {
  await tester.pump();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<GoRouter> _boot(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_HomeownerAuth()),
        savedDesignsProvider.overrideWith((ref) => Stream.value(const [])),
        marketplaceProductsProvider.overrideWith(
          (ref) => Stream.value([
            _product('sofa-1', 'Nordic Sofa'),
            _product('lamp-1', 'Arc Floor Lamp'),
          ]),
        ),
        customerStatsProvider.overrideWith(
          (ref) => const CustomerStats(
            purchases: AsyncData(0),
            savedDesigns: AsyncData(0),
            wishlist: AsyncData(0),
            budget: AsyncData(null),
          ),
        ),
        recentActivityProvider
            .overrideWith((ref) => const AsyncData(<ActivityEntry>[])),
        customerOrdersProvider.overrideWith((ref) => Stream.value(const [])),
        categoriesProvider.overrideWith(
          (ref) async => const <ProductCategory>[],
        ),
        stylesProvider.overrideWith((ref) async => const <String>[]),
        cartProvider.overrideWith(() => _LocalCart()),
        wishlistCountProvider.overrideWithValue(0),
      ],
      child: const InteriorDesignApp(),
    ),
  );
  await _settle(tester);

  final container = ProviderScope.containerOf(
    tester.element(find.byType(InteriorDesignApp)),
  );
  return container.read(appRouterProvider);
}

int _navIndex(WidgetTester tester) =>
    tester.widget<FloatingNavBar>(find.byType(FloatingNavBar)).selectedIndex;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Under testWidgets FakeAsync an unmocked platform-channel future never
    // completes, so availableCameras() would hang forever. Reply with an
    // empty list to exercise the graceful "no camera" branch.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/camera'),
      (call) async {
        if (call.method == 'availableCameras') return <Object>[];
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/camera'), null);
  });

  testWidgets(
      'design tab: interactions then switch to marketplace never throws',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = await _boot(tester);
    router.go('/design');
    await _settle(tester);
    expect(find.byType(RoomScannerScreen), findsOneWidget);
    expect(_navIndex(tester), 1);
    expect(tester.takeException(), isNull);

    // The scan button exercises the camera path — in tests there is no
    // camera, so this must land on the graceful "not available" branch
    // instead of throwing.
    expect(find.byTooltip('Scan Room'), findsOneWidget);
    await tester.tap(find.byTooltip('Scan Room'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Camera not available'), findsOneWidget);

    // Open the furniture picker and place an item on the plan. The sheet
    // title repeats the button label, so the same text is on screen twice.
    await tester.tap(find.text('Add furniture'));
    await _settle(tester);
    expect(find.text('Add furniture'), findsAtLeastNWidgets(1));
    final sofaTile = find.text('Sofa').last;
    if (sofaTile.evaluate().isNotEmpty) {
      await tester.tap(sofaTile);
      await _settle(tester);
    }
    expect(tester.takeException(), isNull);

    // Let a few of the scanner's 1-second timer windows elapse while the
    // Design tab is still visible, then hop to the marketplace.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 700));
    }
    expect(tester.takeException(), isNull);

    router.go('/marketplace');
    await _settle(tester);
    expect(find.byType(MarketplaceScreen), findsOneWidget);
    expect(_navIndex(tester), 3);
    expect(tester.takeException(), isNull);

    // The scanner keeps its timers/state alive behind the shell — keep
    // pumping frames while it is hidden.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull);

    // Round trip back to the design tab.
    router.go('/design');
    await _settle(tester);
    expect(find.byType(RoomScannerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    // And again to the marketplace, exercising product cards this time.
    router.go('/marketplace');
    await _settle(tester);
    expect(find.text('Nordic Sofa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI tab → marketplace switch keeps both branches healthy',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = await _boot(tester);
    router.go('/ai');
    await _settle(tester);
    expect(find.byType(AiRecommendationScreen), findsOneWidget);
    expect(_navIndex(tester), 2);
    expect(tester.takeException(), isNull);

    router.go('/marketplace');
    await _settle(tester);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(MarketplaceScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    router.go('/design');
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}

class _HomeownerAuth implements IAuthRepository {
  static final AppUser _user = AppUser(
    uid: 'u-test',
    email: 'home@example.com',
    name: 'Home Owner',
    role: UserRole.homeowner,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
  }

  @override
  Future<AppUser?> getCurrentUser() async => _user;

  @override
  Future<AppUser> login(String email, String password) async => _user;

  @override
  Future<AppUser> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? address,
  }) async =>
      _user;

  @override
  Future<void> logout() async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> resendVerificationEmail({
    required String email,
    required String uid,
  }) async {}

  @override
  Future<bool> isEmailVerified() async => true;

  @override
  Future<DeletionStatus> requestAccountDeletion(String confirmEmail) =>
      throw UnimplementedError();

  @override
  Future<DeletionStatus> cancelAccountDeletion() => throw UnimplementedError();

  @override
  Future<DeletionStatus> fetchDeletionStatus() async =>
      const DeletionStatus(status: 'none');

  @override
  Future<AppUser> updateProfile({
    required String name,
    String? phone,
    String? address,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
  }) async =>
      _user;
}
