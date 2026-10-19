import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show debugPrint;
import '../../../../core/utils/boot_trace.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/account_deletion_datasource.dart';
import '../datasources/firebase_auth_datasource.dart';
import '../datasources/firestore_user_datasource.dart';
import '../datasources/verification_email_datasource.dart';
import '../models/app_user.dart';

class AuthRepositoryImpl implements IAuthRepository {
  final FirebaseAuthDatasource _authDatasource;
  final FirestoreUserDatasource _firestoreDatasource;
  final VerificationEmailDatasource _verificationDatasource;
  final AccountDeletionDatasource _deletionDatasource;

  AuthRepositoryImpl({
    required FirebaseAuthDatasource authDatasource,
    required FirestoreUserDatasource firestoreDatasource,
    required VerificationEmailDatasource verificationDatasource,
    AccountDeletionDatasource? deletionDatasource,
  })  : _authDatasource = authDatasource,
        _firestoreDatasource = firestoreDatasource,
        _verificationDatasource = verificationDatasource,
        _deletionDatasource = deletionDatasource ?? AccountDeletionDatasource();

  String? _profileFetchUid;
  Future<AppUser>? _profileFetch;

  @override
  Stream<AppUser?> authStateChanges() {
    return _authDatasource.authStateChanges().asyncMap((fbUser) async {
      if (fbUser == null) {
        await BootTrace.log('authState: signed out');
        return null;
      }
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

      const verificationStatus = 'none';

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

      try {
        await _verificationDatasource.sendVerificationEmail(
          email: email,
          uid: fbUser.uid,
        );
      } catch (e) {
        debugPrint('[verify] initial send failed (Resend can retry): $e');
      }

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

  @override
  Future<DeletionStatus> requestAccountDeletion(String confirmEmail) {
    return _deletionDatasource.requestDeletion(confirmEmail: confirmEmail);
  }

  @override
  Future<DeletionStatus> cancelAccountDeletion() {
    return _deletionDatasource.cancelDeletion();
  }

  @override
  Future<DeletionStatus> fetchDeletionStatus() {
    return _deletionDatasource.fetchDeletionStatus();
  }

  Future<AppUser> _buildAppUser(fb.User fbUser) {
    final inFlight = _profileFetch;
    if (inFlight != null && _profileFetchUid == fbUser.uid) {
      return inFlight;
    }
    final fetch = _fetchAppUser(fbUser);
    _profileFetchUid = fbUser.uid;
    _profileFetch = fetch;
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

  AuthException _mapFirebaseError(
    fb.FirebaseAuthException e, {
    required _AuthOp op,
  }) {
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

enum _AuthOp { signIn, register, passwordReset }
