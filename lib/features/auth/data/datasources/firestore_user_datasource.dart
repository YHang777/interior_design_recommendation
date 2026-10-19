import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreUserDatasource {
  final FirebaseFirestore _firestore;
  static const String _collection = 'users';

  FirestoreUserDatasource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<DocumentSnapshot> getUser(String uid) {
    return _firestore.collection(_collection).doc(uid).get();
  }

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

  Future<void> updateUser(String uid, Map<String, dynamic> data) {
    return _firestore.collection(_collection).doc(uid).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<DocumentSnapshot> watchUser(String uid) {
    return _firestore.collection(_collection).doc(uid).snapshots();
  }
}
