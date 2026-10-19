import '../../../../core/utils/user_errors.dart';
import '../../data/datasources/account_deletion_datasource.dart';
import '../../data/models/app_user.dart';

abstract class IAuthRepository {
  Stream<AppUser?> authStateChanges();

  Future<AppUser> login(String email, String password);

  Future<AppUser> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? address,
  });

  Future<AppUser> updateProfile({
    required String name,
    String? phone,
    String? address,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
  });

  Future<void> logout();

  Future<void> sendPasswordResetEmail(String email);

  Future<AppUser?> getCurrentUser();

  Future<void> resendVerificationEmail({
    required String email,
    required String uid,
  });

  Future<bool> isEmailVerified();

  Future<DeletionStatus> requestAccountDeletion(String confirmEmail);

  Future<DeletionStatus> cancelAccountDeletion();

  Future<DeletionStatus> fetchDeletionStatus();
}

class AuthException implements Exception, UserFacingException {
  final String message;
  final String? code;

  const AuthException(this.message, {this.code});

  @override
  String get userMessage => message;

  @override
  String toString() => 'AuthException: $message';
}
