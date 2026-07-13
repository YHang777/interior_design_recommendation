import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../../domain/repositories/auth_repository.dart';
import '../datasources/firebase_auth_datasource.dart';
import '../datasources/firestore_user_datasource.dart';
import '../models/app_user.dart';

/// Production auth repository using Firebase Auth + Firestore.
class AuthRepositoryImpl implements IAuthRepository {
  final FirebaseAuthDatasource _authDatasource;
  final FirestoreUserDatasource _firestoreDatasource;

  AuthRepositoryImpl({
    required FirebaseAuthDatasource authDatasource,
    required FirestoreUserDatasource firestoreDatasource,
  })  : _authDatasource = authDatasource,
        _firestoreDatasource = firestoreDatasource;

  @override
  Stream<AppUser?> authStateChanges() {
    return _authDatasource.authStateChanges().asyncMap((fbUser) async {
      if (fbUser == null) return null;
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
  }) async {
    try {
      final credential = await _authDatasource.createUserWithEmailAndPassword(
        email,
        password,
      );
      final fbUser = credential.user!;

      // Create Firestore document
      await _firestoreDatasource.createUser(
        uid: fbUser.uid,
        data: {
          'name': name,
          'email': email,
          'role': role.firestoreValue,
          'phone': phone ?? '',
          'address': '',
          'profilePicture': '',
        },
      );

      // Send verification email
      await _authDatasource.sendEmailVerification();

      final user = AppUser(
        uid: fbUser.uid,
        email: email,
        name: name,
        role: role,
        phone: phone,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      return user;
    } on fb.FirebaseAuthException catch (e) {
      throw _mapFirebaseError(e);
    }
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
  Future<void> resendVerificationEmail() async {
    await _authDatasource.sendEmailVerification();
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
