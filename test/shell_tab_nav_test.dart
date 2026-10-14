// Floating nav bar sync: navigating to another shell branch must SWITCH
// the StatefulShellRoute branch, otherwise the pushed screen shows while
// FloatingNavBar keeps highlighting the previous tab (reported: home →
// AI page, nav bar still shows Home).
//
// go_router implements `push('/ai')` from `/home` by recursing into the
// shell's children while keeping the shell match's ORIGINAL branch
// navigatorKey, so StatefulNavigationShell.currentIndex never moves.
// Two layers are asserted against the real app router:
//   1. the dashboard's own "AI Design" shortcut — the reported repro,
//      which now calls context.go directly; and
//   2. GuardedGoRouter.push, which reroutes any cross-branch push to
//      go() so call sites added later (or outside lib/) cannot silently
//      regress the highlight.

import 'package:flutter/material.dart';
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
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/screens/dashboard_screen.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/screens/saved_designs_screen.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/shared/widgets/floating_nav_bar.dart';

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
/// The redirect lands the app in the homeowner shell on `/home`.
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

/// What the FloatingNavBar is actually highlighting right now.
int _navIndex(WidgetTester tester) =>
    tester.widget<FloatingNavBar>(find.byType(FloatingNavBar)).selectedIndex;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The AI screen's chat history notifier reads SharedPreferences.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('dashboard AI shortcut lands on AI with the AI tab highlighted',
      (tester) async {
    // Tall surface so the Quick Actions row is on screen without
    // hunting for the right scrollable in a nested-scroll dashboard.
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = await _boot(tester);
    router.go('/home');
    await _settle(tester);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(_navIndex(tester), 0, reason: 'boot state is the Home tab');

    // The reported repro: "from home to AI page".
    await tester.tap(find.text('AI Design'));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(AiRecommendationScreen), findsOneWidget);
    expect(
      _navIndex(tester),
      2,
      reason: 'nav bar must follow the shortcut target (AI), not stay on '
          'Home — a branch switch is go(), not push()',
    );
  });

  testWidgets('cross-branch push through GuardedGoRouter highlights the tab',
      (tester) async {
    final router = await _boot(tester);
    router.go('/home');
    await _settle(tester);
    expect(_navIndex(tester), 0);

    // Any push into a different branch of the shell on top of the stack
    // (dashboard call site, pushOnce, a future call site) must behave as
    // a branch switch: the shell's currentIndex — and with it the
    // FloatingNavBar — has to move.
    router.push('/saved');
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(SavedDesignsScreen), findsOneWidget);
    expect(
      _navIndex(tester),
      4,
      reason: 'GuardedGoRouter must reroute a cross-branch push to go() '
          'so the nav bar highlights the pushed branch',
    );
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
