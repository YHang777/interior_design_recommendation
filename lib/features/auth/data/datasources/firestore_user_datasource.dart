import 'package:cloud_firestore/cloud_firestore.dart';

/// Thin wrapper around Firestore users collection.
class FirestoreUserDatasource {
  final FirebaseFirestore _firestore;
  static const String _collection = 'users';

  FirestoreUserDatasource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Fetches a user document by uid.
  Future<DocumentSnapshot> getUser(String uid) {
    return _firestore.collection(_collection).doc(uid).get();
  }

  /// Creates a user document after registration.
  Future<void> createUser({
    required String uid,
    required Map<String, dynamic> data,
  }) {
    return _firestore.collection(_collection).doc(uid).set({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Updates a user document.
  Future<void> updateUser(String uid, Map<String, dynamic> data) {
    return _firestore.collection(_collection).doc(uid).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Watches a user document for real-time updates.
  Stream<DocumentSnapshot> watchUser(String uid) {
    return _firestore.collection(_collection).doc(uid).snapshots();
  }
}
