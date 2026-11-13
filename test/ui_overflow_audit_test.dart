import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/models/cart_item.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

// ── UI overflow audit ──
// Boots the real app (router, shells, themes) with fake auth + data and
// visits every routable screen on small/medium/large phones and with large
// text. Any "RenderFlex overflowed" is a failure; any other exception is
// reported as a harness gap so it is never silently swallowed.

const _sizes = <String, Size>{
  'small 320x568': Size(320, 568),
  'medium 360x640': Size(360, 640),
  'large 412x915': Size(412, 915),
};

const _homeownerRoutes = [
  '/home',
  '/design',
  '/ai',
  '/marketplace',
  '/saved',
  '/profile',
  '/budget',
  '/walkthrough',
  '/marketplace/cart',
  '/marketplace/orders',
  '/marketplace/wishlist',
  '/marketplace/product/p1',
];

const _supplierRoutes = [
  '/supplier/dashboard',
  '/supplier/products',
  '/supplier/orders',
  '/supplier/analytics',
  '/supplier/profile',
  '/supplier/quotes',
  '/supplier/products/new',
  '/supplier/verification',
  '/supplier/sales-report',
];

const _authRoutes = ['/login', '/register', '/forgot-password'];

Product _product(String id, String name) => Product.fromJson({
      'id': id,
      'name': name,
      'price': 128900,
      'originalPrice': 159900,
      'stock': 3,
      'category': 'Living Room Seating & Lounge Furniture',
      'designStyle': 'Scandinavian Modern Minimalist',
      'description': 'A deliberately long description ' * 8,
      'image': '',
      'rating': 4.7,
      'ratingCount': 1234,
      'isEcoFriendly': true,
      'dimensions': {'widthM': 2.2, 'heightM': 0.9, 'depthM': 1.0},
      'supplier': {
        'id': 's1',
        'name': 'An Extremely Long Furniture Supplier Name Sdn Bhd',
        'phone': '+60 12-345 6789',
        'address': 'Lot 1234, Jalan Panjang Sekali, Kuala Lumpur',
        'email': 'sales@verylongsuppliername.example.com',
        'verificationStatus': 'verified',
      },
    });

final _products = [
  _product('p1', 'Extra Long Scandinavian Three Seater Sofa Bed With Storage'),
  _product('p2', 'Oak Coffee Table'),
  _product('p3', 'Velvet Armchair In Deep Emerald Green With Brass Legs'),
];

class _SeedCart extends CartNotifier {
  @override
  List<CartItem> build() =>
      [for (final p in _products) CartItem(product: p, quantity: 2)];
}

class _SeedWishlist extends WishlistNotifier {
  @override
  Set<String> build() => {for (final p in _products) p.id};
}

final _designs = [
  for (var i = 0; i < 3; i++)
    RoomDesign(
      id: 'd$i',
      name: 'My Very Long Scandinavian Living Room Renovation Plan Number $i',
      roomType: 'living_room',
      widthCm: 420,
      heightCm: 510,
      furniture: const [
        FurniturePlacement(
            id: 'f1',
            name: 'Extra Long Three Seater Sofa With Chaise',
            iconName: 'sofa',
            x: 20,
            y: 20,
            width: 220,
            height: 95),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
      userId: 'u1',
    ),
];

class _FakeAuth implements IAuthRepository {
  _FakeAuth(this._user);
  final AppUser? _user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
  }

  @override
  Future<AppUser?> getCurrentUser() async => _user;
  @override
  Future<AppUser> login(String email, String password) async => _user!;
  @override
  Future<AppUser> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? address,
  }) async =>
      _user!;
  @override
  Future<void> logout() async {}
  @override
  Future<void> sendPasswordResetEmail(String email) async {}
  @override
  Future<void> resendVerificationEmail(
      {required String email, required String uid}) async {}
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
      _user!;
}

AppUser _user(UserRole role) => AppUser(
      uid: role == UserRole.supplier ? 's1' : 'u1',
      email: 'a.very.long.email.address.for.testing@example.com',
      name: 'Nur Aisyah Binti Abdullah Rahman',
      role: role,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Finding {
  _Finding(this.where, this.message);
  final String where;
  final String message;
  @override
  String toString() => '[$where] $message';
}

Future<(List<_Finding>, List<_Finding>)> _audit(
  WidgetTester tester, {
  required AppUser? user,
  required List<String> routes,
  required Map<String, Size> sizes,
  double textScale = 1.0,
}) async {
  final overflows = <_Finding>[];
  final others = <_Finding>[];
  var where = 'boot';
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    final loc = RegExp(r'lib[\\/][^\s:]+\.dart:\d+')
            .firstMatch(details.toString())
            ?.group(0) ??
        '';
    final finding = _Finding(where, '${text.split('\n').first} $loc');
    if (text.contains('overflowed')) {
      overflows.add(finding);
    } else {
      others.add(finding);
    }
  };
  try {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    for (final entry in sizes.entries) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = entry.value;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_FakeAuth(user)),
            savedDesignsProvider.overrideWith((ref) => Stream.value(_designs)),
            cartProvider.overrideWith(_SeedCart.new),
            wishlistProvider.overrideWith(_SeedWishlist.new),
            marketplaceProductsProvider
                .overrideWith((ref) => Stream.value(_products)),
            customerStatsProvider.overrideWith(
              (ref) => const CustomerStats(
                purchases: AsyncData(12),
                savedDesigns: AsyncData(7),
                wishlist: AsyncData(3),
                budget: AsyncData(null),
              ),
            ),
            recentActivityProvider
                .overrideWith((ref) => const AsyncData(<ActivityEntry>[])),
          ],
          child: const InteriorDesignApp(),
        ),
      );
      where = 'boot @ ${entry.key}';
      await _settle(tester);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(InteriorDesignApp)));
      final router = container.read(appRouterProvider);
      for (final route in routes) {
        where = '$route @ ${entry.key} x$textScale';
        router.go(route);
        await _settle(tester);
        // Drain any exception the binding is holding for this frame.
        final pending = tester.takeException();
        if (pending != null) {
          final text = pending.toString();
          (text.contains('overflowed') ? overflows : others)
              .add(_Finding(where, text.split('\n').first));
        }
      }
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
    }
  } finally {
    FlutterError.onError = previous;
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
  return (overflows, others);
}

void _report(String label, List<_Finding> overflows, List<_Finding> others) {
  // ignore: avoid_print
  print('── $label: ${overflows.length} overflow(s), '
      '${others.length} other error(s)');
  for (final f in {...overflows.map((e) => e.toString())}) {
    // ignore: avoid_print
    print('  OVERFLOW $f');
  }
  for (final f in {...others.map((e) => e.toString())}.take(40)) {
    // ignore: avoid_print
    print('  ERROR    $f');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('homeowner screens: no overflow on any phone size',
      (tester) async {
    final (o, e) = await _audit(tester,
        user: _user(UserRole.homeowner),
        routes: _homeownerRoutes,
        sizes: _sizes);
    _report('homeowner', o, e);
    expect(o, isEmpty);
  });

  testWidgets('homeowner screens: no overflow with large text (1.3x)',
      (tester) async {
    final (o, e) = await _audit(tester,
        user: _user(UserRole.homeowner),
        routes: _homeownerRoutes,
        sizes: {'small 320x568': _sizes['small 320x568']!},
        textScale: 1.3);
    _report('homeowner large text', o, e);
    expect(o, isEmpty);
  });

  testWidgets('supplier screens: no overflow on any phone size',
      (tester) async {
    final (o, e) = await _audit(tester,
        user: _user(UserRole.supplier),
        routes: _supplierRoutes,
        sizes: _sizes);
    _report('supplier', o, e);
    expect(o, isEmpty);
  });

  testWidgets('supplier screens: no overflow with large text (1.3x)',
      (tester) async {
    final (o, e) = await _audit(tester,
        user: _user(UserRole.supplier),
        routes: _supplierRoutes,
        sizes: {'small 320x568': _sizes['small 320x568']!},
        textScale: 1.3);
    _report('supplier large text', o, e);
    expect(o, isEmpty);
  });

  testWidgets('sign-in screens: no overflow (sizes + large text)',
      (tester) async {
    final (o1, e1) = await _audit(tester,
        user: null, routes: _authRoutes, sizes: _sizes);
    final (o2, e2) = await _audit(tester,
        user: null,
        routes: _authRoutes,
        sizes: {'small 320x568': _sizes['small 320x568']!},
        textScale: 1.3);
    _report('auth', [...o1, ...o2], [...e1, ...e2]);
    expect([...o1, ...o2], isEmpty);
  });
}
