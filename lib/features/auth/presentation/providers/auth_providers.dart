import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/firebase_auth_datasource.dart';
import '../../data/datasources/firestore_user_datasource.dart';
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

  Future<void> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
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
      );
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> logout() async {
    await _repository.logout();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _repository.sendPasswordResetEmail(email);
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
