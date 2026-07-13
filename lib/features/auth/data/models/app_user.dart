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
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isHomeowner => role == UserRole.homeowner;
  bool get isSupplier => role == UserRole.supplier;

  /// Creates from Firestore document + Firebase Auth user.
  factory AppUser.fromFirestore({
    required String uid,
    required String email,
    required Map<String, dynamic> data,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      name: data['name'] as String? ?? '',
      role: UserRole.fromString(data['role'] as String? ?? 'homeowner'),
      phone: data['phone'] as String?,
      address: data['address'] as String?,
      profilePicture: data['profilePicture'] as String?,
      createdAt: (data['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as dynamic)?.toDate() ?? DateTime.now(),
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
      'updatedAt': DateTime.now(),
    };
  }

  AppUser copyWith({
    String? name,
    String? phone,
    String? address,
    String? profilePicture,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      name: name ?? this.name,
      role: role,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      profilePicture: profilePicture ?? this.profilePicture,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() =>
      'AppUser(uid: $uid, email: $email, name: $name, role: $role)';
}
