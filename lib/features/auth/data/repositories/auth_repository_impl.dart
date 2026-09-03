import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show debugPrint;
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

  @override
  Stream<AppUser?> authStateChanges() {
    return _authDatasource.authStateChanges().asyncMap((fbUser) async {
      if (fbUser == null) return null;
      // Unverified sign-ins are treated as signed out. This matches the
      // login() gate below AND fixes the post-register bounce race: the late
      // `User` emission from createUserWithEmailAndPassword (which lands
      // after register() has already signed out) would otherwise flip the
      // router away from the Verify-Email screen seconds after arrival.
      if (!fbUser.emailVerified) return null;
      return _buildAppUser(fbUser);
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
      final credential = await _authDatasource.signInWithEmailAndPassword(
        email,
        password,
      );
      final fbUser = credential.user!;

      if (!fbUser.emailVerified) {
        await _authDatasource.signOut();
        throw const AuthException(
          'Please verify your email first. Check your inbox.',
          code: 'email-not-verified',
        );
      }

      return _buildAppUser(fbUser);
    } on fb.FirebaseAuthException catch (e) {
      throw _mapFirebaseError(e);
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

      // Suppliers are trusted on registration so their listings are visible
      // to buyers immediately (buyer feeds filter on `verificationStatus`).
      // TODO(future): replace with an admin approval flow that flips
      // `verificationStatus` from 'pending' once moderation exists.
      const verificationStatus = 'verified';

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
      throw _mapFirebaseError(e);
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
    return _buildAppUser(fbUser);
  }

  @override
  Future<void> logout() => _authDatasource.signOut();

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _authDatasource.sendPasswordResetEmail(email);
    } on fb.FirebaseAuthException catch (e) {
      throw _mapFirebaseError(e);
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

  /// Fetches Firestore user document and builds AppUser.
  Future<AppUser> _buildAppUser(fb.User fbUser) async {
    final doc = await _firestoreDatasource.getUser(fbUser.uid);

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

  /// Maps FirebaseAuth error codes to user-friendly messages.
  AuthException _mapFirebaseError(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
        return const AuthException(
          'Incorrect password',
          code: 'wrong-password',
        );
      case 'user-not-found':
        return const AuthException(
          'No account found with this email',
          code: 'user-not-found',
        );
      case 'user-disabled':
        return const AuthException(
          'This account has been disabled',
          code: 'user-disabled',
        );
      case 'email-already-in-use':
        return const AuthException(
          'An account with this email already exists',
          code: 'email-already-in-use',
        );
      case 'invalid-email':
        return const AuthException(
          'Please enter a valid email address',
          code: 'invalid-email',
        );
      case 'operation-not-allowed':
        return const AuthException(
          'Email/password sign-in is not enabled',
          code: 'operation-not-allowed',
        );
      case 'weak-password':
        return const AuthException(
          'Password is too weak. Use at least 8 characters',
          code: 'weak-password',
        );
      case 'too-many-requests':
        return const AuthException(
          'Too many attempts. Please try again later.',
          code: 'too-many-requests',
        );
      case 'network-request-failed':
        return const AuthException(
          'Network error. Please check your connection.',
          code: 'network-error',
        );
      default:
        return AuthException(
          e.message ?? 'An unexpected error occurred',
          code: e.code,
        );
    }
  }
}
