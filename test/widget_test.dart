import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/app.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/domain/repositories/auth_repository.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';

void main() {
  testWidgets('Intellar App smoke test', (WidgetTester tester) async {
    // The app requires Firebase at boot. In unit tests we substitute the
    // auth repository so the router can render the (signed-out) login screen.
    final fakeAuth = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
        ],
        child: const InteriorDesignApp(),
      ),
    );

    // Verify that the app loads and shows the login screen
    expect(find.byType(MaterialApp), findsOneWidget);
    // The login screen should render with email/password fields
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);

    // Regression for "I press Sign In and nothing happens": the submit
    // button must be tappable, not stuck behind a spinner. Auth starts in
    // `AsyncLoading` and the login screen treats that as busy, so the
    // repository must deliver an initial state (as Firebase always does)
    // or the button stays disabled forever.
    final signInButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Sign In'),
    );
    expect(signInButton.onPressed, isNotNull,
        reason: 'Sign In must be enabled once auth has resolved');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

/// Signed-out stub used only to keep Firebase out of widget tests.
class _FakeAuthRepository implements IAuthRepository {
  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();

  /// Firebase's `authStateChanges()` always delivers the current state on
  /// listen (signed-out = null). Emitting nothing instead left the auth
  /// notifier in `AsyncLoading` for the whole test and the login button
  /// spinning — which is why `pumpAndSettle` used to time out here.
  @override
  Stream<AppUser?> authStateChanges() async* {
    yield null;
    yield* _controller.stream;
  }

  @override
  Future<AppUser?> getCurrentUser() async => null;

  @override
  Future<AppUser> login(String email, String password) {
    throw UnimplementedError();
  }

  @override
  Future<AppUser> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? address,
  }) {
    throw UnimplementedError();
  }

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
  Future<bool> isEmailVerified() async => false;

  @override
  Future<AppUser> updateProfile({
    required String name,
    String? phone,
    String? address,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
  }) {
    throw UnimplementedError();
  }
}
