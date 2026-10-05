// Device regression: the real GoRouter configuration (two shells,
// redirect, refreshListenable) must survive the exact reported flow —
// Profile → Reports → "Create a design" on the empty report — without
// tripping `!keyReservation.contains(key)` (navigator.dart:4096).
//
// The simplified router in repro_report_push_test.dart proves the crash
// mechanism (a shell-through push on top of an imperative overlay appends
// a second ShellRouteMatch keyed by route.hashCode). These tests guard
// the actual app router, whose GuardedGoRouter reroutes exactly that
// combination to `go()` instead of stacking a duplicate shell.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:interior_design_recommendation/app.dart';
import 'package:interior_design_recommendation/core/router/app_router.dart';
import 'package:interior_design_recommendation/features/auth/data/datasources/account_deletion_datasource.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/domain/repositories/auth_repository.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/stats/customer_stats.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/stats/stats_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/screens/design_report_screen.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/room_scanner_screen.dart';

/// Bounded settling: skeleton/shimmer loops make `pumpAndSettle` hang for
/// its full timeout, so step the frame clock explicitly instead.
Future<void> _settle(WidgetTester tester, {int frames = 6}) async {
  await tester.pump();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Boots the real app (real router, signed-in homeowner, Firebase-free
/// provider overrides) and returns the router for imperative navigation.
Future<GoRouter> _boot(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_HomeownerAuth()),
        savedDesignsProvider.overrideWith((ref) => Stream.value(const [])),
        marketplaceProductsProvider
            .overrideWith((ref) => Stream.value(const [])),
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

void main() {
  testWidgets(
      'Profile → Reports → Create a design never duplicates a page key',
      (tester) async {
    final router = await _boot(tester);

    // Land inside the homeowner shell, as the profile screen does.
    router.go('/profile');
    await _settle(tester);

    // pushOnce('/design/report') — the Reports tool row.
    router.push('/design/report');
    await _settle(tester);
    expect(find.byType(DesignReportScreen), findsOneWidget);
    expect(find.text('Create a design'), findsOneWidget);

    // The reported red-screen action.
    await tester.tap(find.text('Create a design'));
    await _settle(tester);

    expect(find.byType(RoomScannerScreen), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'the push must not append a second homeowner-shell match '
            '(duplicate ValueKey(route.hashCode) → keyReservation assert)');

    // Back returns to the report, as the empty-state subtitle promises.
    router.pop();
    await _settle(tester);
    expect(find.byType(DesignReportScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'shell-through push while the report is open is rerouted, not red',
      (tester) async {
    final router = await _boot(tester);

    router.go('/profile');
    await _settle(tester);
    router.push('/design/report');
    await _settle(tester);
    expect(find.byType(DesignReportScreen), findsOneWidget);

    // The historical crash: pushNamed(homeownerScan) — a location that
    // matches through the homeowner shell — pushed on top of the
    // imperative report overlay. GuardedGoRouter must convert this to
    // `go()` (tab switch replaces the stack) instead of appending a
    // second ShellRouteMatch with the same page key.
    router.push('/design');
    await _settle(tester);

    expect(tester.takeException(), isNull,
        reason: 'shell-through push under an overlay must never hit '
            '!keyReservation.contains(key)');
    expect(find.byType(RoomScannerScreen), findsOneWidget);
    expect(find.byType(DesignReportScreen), findsNothing,
        reason: 'go() replaced the stack, the report overlay is gone');
  });
}

/// Signed-in homeowner stub: the router's redirect only passes once auth
/// delivers a non-loading state, and every role gate reads this user.
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
