import 'dart:async';
import '../../domain/repositories/auth_repository.dart';
import '../models/app_user.dart';

/// In-memory mock auth repository for development without Firebase.
///
/// Test accounts:
/// - test@homeowner.com / password123 → homeowner
/// - test@supplier.com / password123 → supplier (simulates admin-created)
class MockAuthRepository implements IAuthRepository {
  final StreamController<AppUser?> _authStateController =
      StreamController<AppUser?>.broadcast();

  AppUser? _currentUser;

  // In-memory user store
  final Map<String, _MockUserRecord> _users = {
    'test@homeowner.com': _MockUserRecord(
      password: 'password123',
      appUser: AppUser(
        uid: 'mock-homeowner-uid',
        email: 'test@homeowner.com',
        name: 'John Doe',
        role: UserRole.homeowner,
        phone: '+60 12-345 6789',
        address: 'Kuala Lumpur, Malaysia',
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        updatedAt: DateTime.now(),
      ),
      emailVerified: true,
    ),
    'test@supplier.com': _MockUserRecord(
      password: 'password123',
      appUser: AppUser(
        uid: 'mock-supplier-uid',
        email: 'test@supplier.com',
        name: 'ABC Home Supplies',
        role: UserRole.supplier,
        phone: '+60 12-987 6543',
        address: 'Penang, Malaysia',
        createdAt: DateTime.now().subtract(const Duration(days: 60)),
        updatedAt: DateTime.now(),
      ),
      emailVerified: true,
    ),
  };

  @override
  Stream<AppUser?> authStateChanges() => _authStateController.stream;

  @override
  Future<AppUser?> getCurrentUser() async => _currentUser;

  @override
  Future<AppUser> login(String email, String password) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    final record = _users[email.toLowerCase().trim()];

    if (record == null) {
      throw const AuthException(
        'No account found with this email',
        code: 'user-not-found',
      );
    }

    if (record.password != password) {
      throw const AuthException(
        'Incorrect password',
        code: 'wrong-password',
      );
    }

    if (!record.emailVerified) {
      throw const AuthException(
        'Please verify your email first. Check your inbox.',
        code: 'email-not-verified',
      );
    }

    _currentUser = record.appUser;
    _authStateController.add(_currentUser);
    return _currentUser!;
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
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 1000));

    final normalizedEmail = email.toLowerCase().trim();

    if (_users.containsKey(normalizedEmail)) {
      throw const AuthException(
        'An account with this email already exists',
        code: 'email-already-in-use',
      );
    }

    // Suppliers are trusted on registration (see AuthRepositoryImpl for the
    // TODO about a future admin approval flow).
    const verificationStatus = 'verified';
    final newUser = AppUser(
      uid: 'mock-uid-${DateTime.now().millisecondsSinceEpoch}',
      email: normalizedEmail,
      name: name,
      role: role,
      phone: phone,
      address: address,
      verificationStatus: verificationStatus,
      businessName: role == UserRole.supplier ? name : null,
      businessPhone: role == UserRole.supplier ? phone : null,
      businessAddress: role == UserRole.supplier ? address : null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _users[normalizedEmail] = _MockUserRecord(
      password: password,
      appUser: newUser,
      emailVerified: false, // Must verify email
    );

    return newUser;
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
    final current = _currentUser;
    if (current == null) {
      throw const AuthException('You are not signed in', code: 'not-signed-in');
    }
    final updated = current.copyWith(
      name: name,
      phone: phone,
      address: address,
      businessName: businessName,
      businessPhone: businessPhone,
      businessAddress: businessAddress,
    );
    final previousRecord = _users[current.email]!;
    _currentUser = updated;
    _users[current.email] = _MockUserRecord(
      password: previousRecord.password,
      appUser: updated,
      emailVerified: previousRecord.emailVerified,
    );
    _authStateController.add(updated);
    return updated;
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _currentUser = null;
    _authStateController.add(null);
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!_users.containsKey(email.toLowerCase().trim())) {
      // Don't reveal whether the email exists (security best practice)
      return;
    }
    // In production, sends email. Mock just succeeds silently.
  }

  @override
  Future<void> resendVerificationEmail({
    required String email,
    required String uid,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    // Mock convenience: "resending" marks the record verified so the login
    // gate passes — mirrors clicking the real email link.
    final record = _users[email.toLowerCase().trim()];
    if (record != null) {
      record.emailVerified = true;
    }
  }

  @override
  Future<bool> isEmailVerified() async {
    if (_currentUser == null) return false;
    final record = _users[_currentUser!.email];
    return record?.emailVerified ?? false;
  }

  /// Mock helper: mark the current user's email as verified.
  void simulateEmailVerification() {
    if (_currentUser == null) return;
    final record = _users[_currentUser!.email];
    if (record != null) {
      record.emailVerified = true;
    }
  }

  /// Clean up the stream controller.
  void dispose() {
    _authStateController.close();
  }
}

class _MockUserRecord {
  final String password;
  final AppUser appUser;
  bool emailVerified;

  _MockUserRecord({
    required this.password,
    required this.appUser,
    this.emailVerified = false,
  });
}
