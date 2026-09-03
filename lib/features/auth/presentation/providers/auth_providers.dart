import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/firebase_auth_datasource.dart';
import '../../data/datasources/firestore_user_datasource.dart';
import '../../data/datasources/verification_email_datasource.dart';
import '../../data/models/app_user.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';

// ---------------------------------------------------------------------------
// Repository provider — Firebase Auth + Firestore
// ---------------------------------------------------------------------------

/// Provides the current [IAuthRepository] implementation.
/// Uses Firebase Auth + Firestore for production.
/// Switch back to [MockAuthRepository] for offline testing.
final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return AuthRepositoryImpl(
    authDatasource: FirebaseAuthDatasource(),
    firestoreDatasource: FirestoreUserDatasource(),
    verificationDatasource: VerificationEmailDatasource(),
  );
});

// ---------------------------------------------------------------------------
// Auth state notifier — manages login, register, logout
// ---------------------------------------------------------------------------

/// Reactive auth state: loading | data(AppUser?) | error.
class AuthStateNotifier extends StateNotifier<AsyncValue<AppUser?>> {
  final IAuthRepository _repository;
  StreamSubscription<AppUser?>? _authSub;

  AuthStateNotifier(this._repository) : super(const AsyncValue.data(null)) {
    // Listen to auth state changes from the repository
    _authSub = _repository.authStateChanges().listen(
      (user) {
        state = AsyncValue.data(user);
      },
      onError: (error, stack) {
        state = AsyncValue.error(error, stack);
      },
    );
  }

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    // Keep previous value while loading so the UI doesn't flash
    state = AsyncValue.data(state.valueOrNull);
    try {
      final user = await _repository.login(email, password);
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Returns the created user (or null on failure) so the register screen
  /// can navigate to the Verify-Email screen with the right params. The auth
  /// state is set to signed-out (the repository signs out after registration
  /// pending email verification).
  Future<AppUser?> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? address,
  }) async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(state.valueOrNull);
    try {
      final user = await _repository.register(
        email: email,
        password: password,
        name: name,
        role: role,
        phone: phone,
        address: address,
      );
      state = AsyncValue.data(null);
      return user;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
  }

  /// Persists profile edits and refreshes the local auth state with the
  /// updated user. Errors propagate to the caller (snackbar) — the auth
  /// state is left untouched on failure so the user is never signed out.
  Future<void> updateProfile({
    required String name,
    String? phone,
    String? address,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
  }) async {
    final updated = await _repository.updateProfile(
      name: name,
      phone: phone,
      address: address,
      businessName: businessName,
      businessPhone: businessPhone,
      businessAddress: businessAddress,
    );
    state = AsyncValue.data(updated);
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _repository.sendPasswordResetEmail(email);
  }

  /// Asks the middleware to (re)send the verification email. Errors
  /// propagate to the caller (snackbar); auth state is untouched.
  Future<void> resendVerificationEmail({
    required String email,
    required String uid,
  }) {
    return _repository.resendVerificationEmail(email: email, uid: uid);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

/// The primary auth state provider consumed by screens and the router.
final authStateProvider =
    StateNotifierProvider<AuthStateNotifier, AsyncValue<AppUser?>>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthStateNotifier(repository);
});

// ---------------------------------------------------------------------------
// Derived providers
// ---------------------------------------------------------------------------

/// Convenience: is the user currently authenticated?
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.whenOrNull(data: (user) => user != null) ?? false;
});

/// Convenience: current user's role, or null if not logged in.
final currentUserRoleProvider = Provider<UserRole?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.whenOrNull(data: (user) => user?.role);
});

/// Convenience: current user, or null.
final currentUserProvider = Provider<AppUser?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.whenOrNull(data: (user) => user);
});
