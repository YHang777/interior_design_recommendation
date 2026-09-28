import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/domain/repositories/auth_repository.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';

/// Regression tests for the silent sign-in failure: pressing "Sign In"
/// did nothing — no spinner, no error message, no navigation.
///
/// Three compounding defects produced that:
///  1. `login()` set `AsyncValue.loading()` then immediately overwrote it
///     with `data(null)`, so the button never disabled.
///  2. the `authStateChanges()` listener overwrote the `AsyncError` a failed
///     login produced. An unverified sign-in calls `signOut()`, which emits
///     `data(null)` right after the throw and wiped the error before any
///     listener could show it.
///  3. `login()` swallowed the failure instead of rethrowing to the caller.
void main() {
  AppUser user({
    String uid = 'u1',
    bool verified = true,
  }) {
    final now = DateTime(2026, 1, 1);
    return AppUser(
      uid: uid,
      email: 'a@b.com',
      name: 'A',
      role: UserRole.homeowner,
      verificationStatus: verified ? 'verified' : 'pending',
      createdAt: now,
      updatedAt: now,
    );
  }

  test('login() enters loading and does not instantly snap back to data(null)',
      () async {
    final repo = _FakeAuthRepository();
    final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);

    final notifier = container.read(authStateProvider.notifier);

    // Hold the future open so we can observe the in-flight state.
    final gate = Completer<AppUser>();
    repo.onLogin = () => gate.future;

    final pending = notifier.login('a@b.com', 'pw');

    // Regression: this used to already be `AsyncValue.data(null)`, which
    // left the button enabled and silent for the whole attempt.
    final inFlight = container.read(authStateProvider);
    expect(inFlight.isLoading, isTrue,
        reason: 'login() must stay in loading while the call is in flight');

    gate.complete(user());
    await pending;

    final after = container.read(authStateProvider);
    expect(after.isLoading, isFalse);
    expect(after.valueOrNull?.uid, 'u1');
  });

  test('a failed login keeps its AsyncError even when the auth stream emits '
      'data(null) afterwards (unverified sign-in signs out)', () async {
    final repo = _FakeAuthRepository();
    final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);

    repo.loginError = const AuthException('Please verify your email first.',
        code: 'unverified');
    // The repository signs the user out after rejecting an unverified
    // sign-in, so the stream fires `null` right behind the throw.
    repo.emitAfterLoginFailure = true;

    final notifier = container.read(authStateProvider.notifier);

    await expectLater(
      notifier.login('a@b.com', 'pw'),
      throwsA(isA<AuthException>()),
    );

    // Let the deferred `data(null)` from the post-failure signOut land.
    await Future<void>.delayed(Duration.zero);

    final state = container.read(authStateProvider);
    expect(state.hasError, isTrue,
        reason: 'the auth-state stream must not wipe the error of a failed '
            'login — that is what hid the message from the UI');
    expect(state.error, isA<AuthException>());
    expect((state.error! as AuthException).message,
        'Please verify your email first.');
  });

  test('login() rethrows so the caller can surface the message itself', () async {
    final repo = _FakeAuthRepository();
    final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);

    repo.loginError = const AuthException('Incorrect email or password.',
        code: 'wrong-password');

    Object? caught;
    try {
      await container.read(authStateProvider.notifier).login('a@b.com', 'x');
    } catch (e) {
      caught = e;
    }

    expect(caught, isA<AuthException>());
    expect((caught! as AuthException).message, 'Incorrect email or password.');
  });

  test('the auth stream is live again after a successful login', () async {
    final repo = _FakeAuthRepository();
    final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);

    final notifier = container.read(authStateProvider.notifier);
    await notifier.login('a@b.com', 'pw');

    repo.controller.add(user(uid: 'other-tab'));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(authStateProvider).valueOrNull?.uid, 'other-tab');
  });

  test('after a failed login the stream stays suppressed until the next '
      'explicit action (logout)', () async {
    final repo = _FakeAuthRepository();
    final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);

    final notifier = container.read(authStateProvider.notifier);
    repo.loginError = const AuthException('Please verify your email first.');
    repo.emitAfterLoginFailure = true;

    try {
      await notifier.login('a@b.com', 'x');
    } catch (_) {}
    await Future<void>.delayed(Duration.zero);

    // The failure's error is still on screen — not wiped by the sign-out.
    expect(container.read(authStateProvider).hasError, isTrue);

    // A late, unrelated stream emission must not silently clear it either:
    // only the user starting a new action re-opens the stream.
    repo.controller.add(user(uid: 'stray'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(authStateProvider).hasError, isTrue,
        reason: 'a stray emission must not clear an on-screen sign-in error');

    // Explicit sign-out re-opens the stream, so the app keeps working.
    await notifier.logout();
    repo.controller.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(authStateProvider).hasError, isFalse);
    expect(container.read(authStateProvider).valueOrNull, isNull);
  });
}

class _FakeAuthRepository implements IAuthRepository {
  final StreamController<AppUser?> controller =
      StreamController<AppUser?>.broadcast();

  /// When set, `login` waits on this future before completing.
  Future<AppUser> Function()? onLogin;
  Object? loginError;

  /// Emit `data(null)` from the auth stream right after a failed login —
  /// the unverified sign-in path calls `signOut()`, which does exactly this.
  bool emitAfterLoginFailure = false;

  @override
  Stream<AppUser?> authStateChanges() => controller.stream;

  @override
  Future<AppUser> login(String email, String password) async {
    if (onLogin != null) return onLogin!();
    final error = loginError;
    if (error != null) {
      if (emitAfterLoginFailure) {
        // Deferred so it lands *after* login() has recorded the error.
        scheduleMicrotask(() => controller.add(null));
      }
      // ignore: only_throw_errors
      throw error;
    }
    return AppUser(
      uid: 'u1',
      email: email,
      name: 'A',
      role: UserRole.homeowner,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<AppUser?> getCurrentUser() async => null;

  @override
  Future<bool> isEmailVerified() async => false;

  @override
  Future<void> logout() async {}

  @override
  Future<AppUser> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? address,
  }) =>
      login(email, password);

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> resendVerificationEmail({
    required String email,
    required String uid,
  }) async {}

  @override
  Future<AppUser> updateProfile({
    required String name,
    String? phone,
    String? address,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
  }) async =>
      AppUser(
        uid: 'u1',
        email: 'a@b.com',
        name: name,
        role: UserRole.homeowner,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
}
