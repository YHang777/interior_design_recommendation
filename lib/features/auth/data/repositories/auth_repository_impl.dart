import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show debugPrint;
import '../../../../core/utils/boot_trace.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/firebase_auth_datasource.dart';
import '../datasources/firestore_user_datasource.dart';
import '../datasources/verification_email_datasource.dart';
import '../models/app_user.dart';

/// Production auth repository using Firebase Auth + Firestore.
class AuthRepositoryImpl implements IAuthRepository {
  final FirebaseAuthDatasource _authDatasource;
  final FirestoreUserDatasource _firestoreDatasource;
  final VerificationEmailDatasource _verificationDatasource;

  AuthRepositoryImpl({
    required FirebaseAuthDatasource authDatasource,
    required FirestoreUserDatasource firestoreDatasource,
    required VerificationEmailDatasource verificationDatasource,
  })  : _authDatasource = authDatasource,
        _firestoreDatasource = firestoreDatasource,
        _verificationDatasource = verificationDatasource;

  /// In-flight profile fetch, keyed by uid — see [_buildAppUser].
  String? _profileFetchUid;
  Future<AppUser>? _profileFetch;

  @override
  Stream<AppUser?> authStateChanges() {
    return _authDatasource.authStateChanges().asyncMap((fbUser) async {
      if (fbUser == null) {
        await BootTrace.log('authState: signed out');
        return null;
      }
      // Unverified sign-ins are treated as signed out. This matches the
      // login() gate below AND fixes the post-register bounce race: the late
      // `User` emission from createUserWithEmailAndPassword (which lands
      // after register() has already signed out) would otherwise flip the
      // router away from the Verify-Email screen seconds after arrival.
      if (!fbUser.emailVerified) {
        await BootTrace.log('authState: user present but email unverified');
        return null;
      }
      await BootTrace.log('authState: restoring session uid=${fbUser.uid}');
      try {
        final user = await _buildAppUser(fbUser)
            .timeout(const Duration(seconds: 25));
        await BootTrace.log('authState: profile OK');
        return user;
      } catch (e) {
        await BootTrace.log('authState: profile FAILED: $e');
        rethrow;
      }
    });
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    final fbUser = _authDatasource.currentUser;
    if (fbUser == null) return null;
    return _buildAppUser(fbUser);
  }

  @override
  Future<AppUser> login(String email, String password) async {
    try {
      await BootTrace.log('login: signInWithEmailAndPassword begin');
      // Bound the auth round trip — without a timeout a stalled network
      // leaves the Sign In button spinning forever with no feedback.
      final credential = await _authDatasource
          .signInWithEmailAndPassword(email, password)
          .timeout(const Duration(seconds: 25));
      await BootTrace.log('login: signIn OK uid=${credential.user?.uid}');
      final fbUser = credential.user!;

      if (!fbUser.emailVerified) {
        await BootTrace.log('login: email NOT verified — signing out');
        await _authDatasource.signOut();
        throw const AuthException(
          'Please verify your email first. Check your inbox.',
          code: 'email-not-verified',
        );
      }

      await BootTrace.log('login: fetching profile document');
      final user = await _buildAppUser(fbUser)
          .timeout(const Duration(seconds: 25));
      await BootTrace.log('login: profile OK role=${user.role.name}');
      return user;
    } on TimeoutException {
      await BootTrace.log('login: TIMED OUT');
      throw const AuthException(
        'Sign in timed out. Check your connection and try again.',
        code: 'timeout',
      );
    } on fb.FirebaseAuthException catch (e) {
      await BootTrace.log('login: FirebaseAuthException ${e.code}');
      throw _mapFirebaseError(e, op: _AuthOp.signIn);
    }
  }

  @override
  Future<AppUser> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? address,
  }) async {
    try {
      final credential = await _authDatasource.createUserWithEmailAndPassword(
        email,
        password,
      );
      final fbUser = credential.user!;

      final isSupplier = role == UserRole.supplier;

      // New accounts start UNVERIFIED. A supplier's "Verified" badge is an
      // admin decision — it is granted only after they upload their IC and
      // supporting documents and an admin approves them. Writing 'verified'
      // here would make the badge meaningless.
      //
      // This is also a hard requirement of `firestore.rules`: the `users`
      // rule refuses any client write of `verificationStatus: 'verified'`,
      // so stamping it at signup would deny every registration outright.
      // Only the admin backend (Admin SDK, bypasses rules) may set it.
      const verificationStatus = 'none';

      // Create Firestore document.
      await _firestoreDatasource.createUser(
        uid: fbUser.uid,
        data: {
          'name': name,
          'email': email,
          'role': role.firestoreValue,
          'phone': phone ?? '',
          'address': address ?? '',
          'profilePicture': '',
          'verificationStatus': verificationStatus,
          'businessName': isSupplier ? name : '',
          'businessPhone': isSupplier ? (phone ?? '') : '',
          'businessAddress': isSupplier ? (address ?? '') : '',
        },
      );

      // Custom verification flow: the middleware emails a confirmation link
      // (Brevo). Best-effort — a failure here must NOT fail registration;
      // the Verify screen's Resend button is the retry path.
      try {
        await _verificationDatasource.sendVerificationEmail(
          email: email,
          uid: fbUser.uid,
        );
      } catch (e) {
        debugPrint('[verify] initial send failed (Resend can retry): $e');
      }

      // The user must verify before their first login: sign out now so the
      // Verify-Email screen stays reachable (the router redirects signed-in
      // users off auth routes).
      await _authDatasource.signOut();

      final user = AppUser(
        uid: fbUser.uid,
        email: email,
        name: name,
        role: role,
        phone: phone,
        address: address,
        verificationStatus: verificationStatus,
        businessName: isSupplier ? name : null,
        businessPhone: isSupplier ? phone : null,
        businessAddress: isSupplier ? address : null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      return user;
    } on fb.FirebaseAuthException catch (e) {
      throw _mapFirebaseError(e, op: _AuthOp.register);
    }
  }

  @override
  Future<AppUser> updateProfile({
    required String name,
    String? phone,
    String? address,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
  }) async {
    final fbUser = _authDatasource.currentUser;
    if (fbUser == null) {
      throw const AuthException('You are not signed in', code: 'not-signed-in');
    }
    await _firestoreDatasource.updateUser(fbUser.uid, {
      'name': name,
      'phone': phone ?? '',
      'address': address ?? '',
      'businessName': businessName ?? '',
      'businessPhone': businessPhone ?? '',
      'businessAddress': businessAddress ?? '',
    });
    // Deliberately bypasses the [_buildAppUser] memo: this read must observe
    // the write above, never a profile fetch that was already in flight.
    return _fetchAppUser(fbUser);
  }

  @override
  Future<void> logout() => _authDatasource.signOut();

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _authDatasource.sendPasswordResetEmail(email);
    } on fb.FirebaseAuthException catch (e) {
      throw _mapFirebaseError(e, op: _AuthOp.passwordReset);
    }
  }

  @override
  Future<void> resendVerificationEmail({
    required String email,
    required String uid,
  }) {
    return _verificationDatasource.sendVerificationEmail(
      email: email,
      uid: uid,
    );
  }

  @override
  Future<bool> isEmailVerified() async {
    await _authDatasource.reloadUser();
    return _authDatasource.isEmailVerified;
  }

  /// Builds the [AppUser] for [fbUser], de-duplicating concurrent calls.
  ///
  /// `login()` and the `authStateChanges()` stream both resolve a profile for
  /// the same uid within the same event-loop turn: sign-in makes Firebase Auth
  /// emit on its stream while `login()` carries on to its own lookup. Each
  /// used to issue a separate `users/{uid}` read, so one sign-in paid for two
  /// concurrent network round trips — and the stream's copy was then discarded
  /// by the notifier's suspension guard, making it pure waste on the exact
  /// critical path the splash screen waits on.
  ///
  /// Concurrent callers for the same uid now share one read. The memo lives
  /// only until that shared future settles, so a later call — or a different
  /// uid — always starts fresh and no stale profile can be observed.
  Future<AppUser> _buildAppUser(fb.User fbUser) {
    final inFlight = _profileFetch;
    if (inFlight != null && _profileFetchUid == fbUser.uid) {
      return inFlight;
    }
    final fetch = _fetchAppUser(fbUser);
    _profileFetchUid = fbUser.uid;
    _profileFetch = fetch;
    // Clear on both outcomes. This `onError` consumes the error for the
    // derived future only — callers still receive it from `fetch` itself.
    unawaited(fetch.then(
      (_) => _clearProfileFetch(fetch),
      onError: (_) => _clearProfileFetch(fetch),
    ));
    return fetch;
  }

  void _clearProfileFetch(Future<AppUser> fetch) {
    if (identical(_profileFetch, fetch)) {
      _profileFetch = null;
      _profileFetchUid = null;
    }
  }

  /// Reads `users/{uid}` and maps it to an [AppUser]. Always hits Firestore.
  Future<AppUser> _fetchAppUser(fb.User fbUser) async {
    await BootTrace.log('profile: users/${fbUser.uid} get()');
    final doc = await _firestoreDatasource.getUser(fbUser.uid);
    await BootTrace.log('profile: users/${fbUser.uid} exists=${doc.exists}');

    if (!doc.exists) {
      throw AuthException(
        'User profile not found. Please contact support.',
        code: 'profile-not-found',
      );
    }

    return AppUser.fromFirestore(
      uid: fbUser.uid,
      email: fbUser.email!,
      data: doc.data() as Map<String, dynamic>,
    );
  }

  /// Which sign-in form produced the failure — the same Firebase code means
  /// different things per screen ("Email or password is incorrect." at login,
  /// "No account found with this email." at password reset).
  AuthException _mapFirebaseError(
    fb.FirebaseAuthException e, {
    required _AuthOp op,
  }) {
    // Codes that only ever mean "this connection is broken".
    if (e.code == 'network-request-failed' || e.code == 'network-error') {
      return const AuthException(
        'No internet connection. Check your network and try again.',
        code: 'network-error',
      );
    }
    if (e.code == 'too-many-requests') {
      return const AuthException(
        'Too many attempts. Wait a moment and try again.',
        code: 'too-many-requests',
      );
    }
    if (e.code == 'invalid-email') {
      return const AuthException(
        'That email address does not look right.',
        code: 'invalid-email',
      );
    }
    if (e.code == 'user-disabled') {
      return const AuthException(
        'This account has been disabled. Contact support.',
        code: 'user-disabled',
      );
    }
    if (e.code == 'user-token-expired' || e.code == 'requires-recent-login') {
      return const AuthException(
        'Your session expired. Please sign in again.',
        code: 'session-expired',
      );
    }

    switch (op) {
      case _AuthOp.signIn:
        // Firebase folds wrong-password / user-not-found into
        // invalid-credential (anti-enumeration), so one message covers all
        // three. Never echo `e.message` here — that is the long
        // "incorrect, malformed or has expired" sentence users were shown.
        if (e.code == 'invalid-credential' ||
            e.code == 'wrong-password' ||
            e.code == 'user-not-found' ||
            e.code == 'INVALID_LOGIN_CREDENTIALS') {
          return const AuthException(
            'Email or password is incorrect.',
            code: 'invalid-credential',
          );
        }
        return const AuthException(
          'Could not sign in. Please try again.',
          code: 'sign-in-failed',
        );

      case _AuthOp.register:
        switch (e.code) {
          case 'email-already-in-use':
            return const AuthException(
              'An account with this email already exists. Try signing in.',
              code: 'email-already-in-use',
            );
          case 'weak-password':
            return const AuthException(
              'That password is too weak. Use at least 8 characters.',
              code: 'weak-password',
            );
          case 'operation-not-allowed':
            return const AuthException(
              'Email sign-up is unavailable right now. Contact support.',
              code: 'operation-not-allowed',
            );
          default:
            return const AuthException(
              'Could not create the account. Please try again.',
              code: 'register-failed',
            );
        }

      case _AuthOp.passwordReset:
        // A reset link cannot be sent to an address that has no account, and
        // here saying so is helpful rather than a privacy leak.
        if (e.code == 'user-not-found' ||
            e.code == 'invalid-credential' ||
            e.code == 'INVALID_LOGIN_CREDENTIALS') {
          return const AuthException(
            'No account found with this email.',
            code: 'user-not-found',
          );
        }
        return const AuthException(
          'Could not send the reset link. Please try again.',
          code: 'reset-failed',
        );
    }
  }
}

/// See [AuthRepositoryImpl._mapFirebaseError].
enum _AuthOp { signIn, register, passwordReset }
