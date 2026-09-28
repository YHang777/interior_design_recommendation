/// User role enum — determines routing and available features.
enum UserRole {
  homeowner,
  supplier;

  /// Parses from Firestore string value.
  static UserRole fromString(String role) {
    switch (role.toLowerCase()) {
      case 'supplier':
        return UserRole.supplier;
      case 'homeowner':
      default:
        return UserRole.homeowner;
    }
  }

  String get firestoreValue => name;
}

/// Domain model representing an authenticated user.
class AppUser {
  final String uid;
  final String email;
  final String name;
  final UserRole role;
  final String? phone;
  final String? address;
  final String? profilePicture;

  /// Admin-granted supplier verification: 'none' | 'pending' | 'verified' |
  /// 'rejected'.
  ///
  /// Every new account starts at 'none'. Only the admin backend may set
  /// 'verified', and only after the supplier has uploaded an IC and
  /// supporting documents and an admin has approved them — `firestore.rules`
  /// refuses any client write of 'verified', so this cannot be self-granted.
  /// Homeowners never see verification UI; the value only matters for
  /// suppliers, where it drives the "Verified" badge buyers see.
  final String verificationStatus;

  /// Supplier business profile (populated when [role] is supplier).
  final String? businessName;
  final String? businessPhone;
  final String? businessAddress;

  final DateTime createdAt;
  final DateTime updatedAt;

  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.phone,
    this.address,
    this.profilePicture,
    this.verificationStatus = 'none',
    this.businessName,
    this.businessPhone,
    this.businessAddress,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isHomeowner => role == UserRole.homeowner;
  bool get isSupplier => role == UserRole.supplier;
  bool get isVerified => verificationStatus == 'verified';

  /// Whether the supplier may submit (or re-submit) a verification
  /// application right now: only from 'none' (never applied) or 'rejected'
  /// (admin rejected — re-apply allowed). 'pending' is read-only while the
  /// admin reviews, and 'verified' is terminal.
  bool get canSubmitVerification =>
      verificationStatus == 'none' || verificationStatus == 'rejected';

  /// Creates from Firestore document + Firebase Auth user.
  factory AppUser.fromFirestore({
    required String uid,
    required String email,
    required Map<String, dynamic> data,
  }) {
    final role = UserRole.fromString(data['role'] as String? ?? 'homeowner');
    final name = data['name'] as String? ?? '';
    return AppUser(
      uid: uid,
      email: email,
      name: name,
      role: role,
      phone: data['phone'] as String?,
      address: data['address'] as String?,
      profilePicture: data['profilePicture'] as String?,
      // A stored status is always honoured — accounts written before this
      // feature keep whatever value they have (including 'verified' from
      // the old signup stamp). Only a doc that never got the field falls
      // back, and it falls back to 'none': never claim a verification that
      // was not granted.
      verificationStatus: data['verificationStatus']?.toString() ?? 'none',
      businessName: data['businessName']?.toString() ??
          (role == UserRole.supplier ? name : null),
      businessPhone: data['businessPhone']?.toString(),
      businessAddress: data['businessAddress']?.toString(),
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  /// Serializes to Firestore document.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'role': role.firestoreValue,
      'phone': phone ?? '',
      'address': address ?? '',
      'profilePicture': profilePicture ?? '',
      'verificationStatus': verificationStatus,
      'businessName': businessName ?? '',
      'businessPhone': businessPhone ?? '',
      'businessAddress': businessAddress ?? '',
      'updatedAt': DateTime.now(),
    };
  }

  AppUser copyWith({
    String? name,
    String? phone,
    String? address,
    String? profilePicture,
    String? verificationStatus,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      name: name ?? this.name,
      role: role,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      profilePicture: profilePicture ?? this.profilePicture,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      businessName: businessName ?? this.businessName,
      businessPhone: businessPhone ?? this.businessPhone,
      businessAddress: businessAddress ?? this.businessAddress,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() =>
      'AppUser(uid: $uid, email: $email, name: $name, role: $role)';
}

DateTime _toDate(dynamic value) {
  if (value is DateTime) return value;
  try {
    final toDate = value?.toDate;
    if (toDate is Function) {
      final parsed = value.toDate();
      if (parsed is DateTime) return parsed;
    }
  } catch (_) {}
  return DateTime.now();
}
