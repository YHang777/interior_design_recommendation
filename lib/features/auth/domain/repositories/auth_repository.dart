import '../../data/models/app_user.dart';

/// Abstract contract for authentication operations.
///
/// Implementations:
/// - [MockAuthRepository] — for development without Firebase
/// - [AuthRepositoryImpl] — production Firebase Auth + Firestore
abstract class IAuthRepository {
  /// Stream of auth state changes. Emits null when signed out.
  Stream<AppUser?> authStateChanges();

  /// Sign in with email and password.
  /// Throws [AuthException] on failure.
  Future<AppUser> login(String email, String password);

  /// Create a new account. Role defaults to [UserRole.homeowner] for
  /// standard registration.
  Future<AppUser> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? address,
  });

  /// Updates the signed-in user's public profile in Firestore and returns
  /// the refreshed [AppUser]. Suppliers pass `businessName`/`businessPhone`/
  /// `businessAddress` so their storefront identity stays in sync.
  Future<AppUser> updateProfile({
    required String name,
    String? phone,
    String? address,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
  });

  /// Sign out the current user.
  Future<void> logout();

  /// Send a password reset email.
  Future<void> sendPasswordResetEmail(String email);

  /// Get the currently signed-in user, or null.
  Future<AppUser?> getCurrentUser();

  /// Resend the email verification.
  Future<void> resendVerificationEmail();

  /// Check if the current user's email is verified.
  Future<bool> isEmailVerified();
}

/// Custom exception for auth errors with user-friendly messages.
class AuthException implements Exception {
  final String message;
  final String? code;

  const AuthException(this.message, {this.code});

  @override
  String toString() => 'AuthException: $message';
}
