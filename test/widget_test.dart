import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/app.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/domain/repositories/auth_repository.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';

void main() {
  testWidgets('Interior Design App smoke test', (WidgetTester tester) async {
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
  });
}

/// Signed-out stub used only to keep Firebase out of widget tests.
class _FakeAuthRepository implements IAuthRepository {
  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;

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
  Future<void> resendVerificationEmail() async {}

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
