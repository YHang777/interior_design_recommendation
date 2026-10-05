import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/account_deletion_datasource.dart';
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
    deletionDatasource: AccountDeletionDatasource(),
  );
});

// ---------------------------------------------------------------------------
// Auth state notifier — manages login, register, logout
// ---------------------------------------------------------------------------

/// Reactive auth state: loading | data(AppUser?) | error.
class AuthStateNotifier extends StateNotifier<AsyncValue<AppUser?>> {
  final IAuthRepository _repository;
  StreamSubscription<AppUser?>? _authSub;

  /// True while `authStateChanges()` must not overwrite [state].
  ///
  /// Set for the duration of an explicit `login()` / `register()` call, and
  /// **kept set after a failed sign-in** until the next explicit action.
  ///
  /// Why it cannot just be an in-flight guard cleared in `finally`: a
  /// rejected sign-in (e.g. unverified email) throws *and* the repository
  /// signs the user out, so `authStateChanges()` emits `data(null)` a moment
  /// later — after `finally` has already run. That emission wiped the
  /// `AsyncError` the failure had just recorded, before any listener could
  /// surface it, leaving the login button dead and silent.
  bool _authStreamSuspended = false;

  AuthStateNotifier(this._repository) : super(const AsyncValue.loading()) {
    // Listen to auth state changes from the repository
    _authSub = _repository.authStateChanges().listen(
      (user) {
        if (_authStreamSuspended) return;
        state = AsyncValue.data(user);
      },
      onError: (error, stack) {
        if (_authStreamSuspended) return;
        state = AsyncValue.error(error, stack);
      },
    );
  }

  Future<void> login(String email, String password) async {
    // A new attempt makes the stream authoritative again, so a successful
    // sign-in still lands even if a previous attempt left it suspended.
    _authStreamSuspended = true;
    // Keep the previous value while loading so the UI doesn't flash empty.
    // (Setting `AsyncLoading` and then immediately overwriting it with
    // `AsyncData` — as this used to — meant the button never showed a
    // spinner and stayed tappable for the whole attempt.)
    state = const AsyncValue<AppUser?>.loading().copyWithPrevious(state);
    try {
      final user = await _repository.login(email, password);
      state = AsyncValue.data(user);
      // Settled happy: let the stream take over again (token refresh, other
      // tabs, a later sign-out).
      _authStreamSuspended = false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // Stay suspended — the `signOut()` this failure performs will emit
      // `data(null)` and would wipe the message before the UI can show it.
      // Rethrow so the caller can surface the message itself rather than
      // relying solely on `ref.listen` observing this state.
      rethrow;
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
    _authStreamSuspended = true;
    // Same contract as [login]: stay in loading for the whole attempt.
    // (Setting `AsyncLoading` and then immediately overwriting it with
    // `AsyncData` — as this used to — meant the button never showed a
    // spinner and stayed tappable for the whole attempt.)
    state = const AsyncValue<AppUser?>.loading().copyWithPrevious(state);
    try {
      final user = await _repository.register(
        email: email,
        password: password,
        name: name,
        role: role,
        phone: phone,
        address: address,
      );
      // Signed-out pending email verification.
      state = AsyncValue.data(null);
      return user;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // Stay suspended so a post-failure sign-out can't wipe the message.
      return null;
    }
  }

  Future<void> logout() async {
    // Explicit sign-out: the stream's `data(null)` is exactly what we want.
    _authStreamSuspended = false;
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

  /// Starts account deletion. The user stays signed in — grace-period
  /// accounts keep their session until the sweep purges them, and
  /// [deletionStatusProvider] drives the pending/scheduled banner.
  /// Errors propagate to the caller (dialog snackbar).
  Future<DeletionStatus> requestAccountDeletion(String confirmEmail) {
    return _repository.requestAccountDeletion(confirmEmail);
  }

  /// Cancels an active deletion request (pending or grace): the account is
  /// restored. Callers should `ref.invalidate(deletionStatusProvider)`
  /// afterwards. Errors propagate to the caller.
  Future<DeletionStatus> cancelAccountDeletion() {
    return _repository.cancelAccountDeletion();
  }

  /// Fresh deletion status for the signed-in user — for callers that need
  /// it imperatively; the banner reads [deletionStatusProvider] instead.
  Future<DeletionStatus> fetchDeletionStatus() {
    return _repository.fetchDeletionStatus();
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

/// A [ChangeNotifier] that fires whenever the auth state changes.
/// Used as GoRouter's [refreshListenable] so redirects are re-evaluated
/// without recreating the router (which would flash the login page).
class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier(StateNotifier<AsyncValue<AppUser?>> authNotifier) {
    // state_notifier 1.0.0: addListener returns a remove callback.
    _removeListener = authNotifier.addListener((_) => notifyListeners());
  }

  late final VoidCallback _removeListener;

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }
}

/// Provider for the auth refresh notifier, consumed by the router.
final authRefreshProvider = Provider<AuthRefreshNotifier>((ref) {
  final authNotifier = ref.watch(authStateProvider.notifier);
  final notifier = AuthRefreshNotifier(authNotifier);
  ref.onDispose(notifier.dispose);
  return notifier;
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

/// The signed-in user's account-deletion status.
///
/// Yields `DeletionStatus(status: 'none')` while signed out (and while the
/// auth state is still resolving), so consumers can treat "no data" as
/// "nothing pending". Fetch failures stay in the [AsyncValue] — the banner
/// fails silent by reading `valueOrNull`.
///
/// Re-fetches automatically on sign-in/sign-out; invalidate explicitly
/// after a request or cancel: `ref.invalidate(deletionStatusProvider)`.
final deletionStatusProvider = FutureProvider<DeletionStatus>((ref) async {
  final signedIn = ref.watch(isAuthenticatedProvider);
  if (!signedIn) return const DeletionStatus(status: 'none');
  return ref.watch(authRepositoryProvider).fetchDeletionStatus();
});
