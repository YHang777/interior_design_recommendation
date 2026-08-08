import 'package:cloud_firestore/cloud_firestore.dart';

/// Thin wrapper around Firestore room_designs collection.
/// Mirrors [FirestoreUserDatasource] pattern.
class RoomDesignDatasource {
  final FirebaseFirestore _firestore;
  static const String _collection = 'room_designs';

  RoomDesignDatasource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Creates a new design document.
  Future<void> createDesign({
    required String designId,
    required Map<String, dynamic> data,
  }) {
    return _firestore.collection(_collection).doc(designId).set({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Updates an existing design document.
  Future<void> updateDesign(
    String designId,
    Map<String, dynamic> data,
  ) {
    return _firestore.collection(_collection).doc(designId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a design document.
  Future<void> deleteDesign(String designId) {
    return _firestore.collection(_collection).doc(designId).delete();
  }

  /// Fetches all designs for a user.
  /// Sorted client-side by updatedAt.
  Future<QuerySnapshot> getDesigns(String userId) {
    return _firestore
        .collection(_collection)
        .where('userId', isEqualTo: userId)
        .get();
  }

  /// Watches a user's designs for real-time updates.
  /// Sorted client-side by updatedAt to avoid requiring a composite index.
  Stream<QuerySnapshot> watchDesigns(String userId) {
    return _firestore
        .collection(_collection)
        .where('userId', isEqualTo: userId)
        .snapshots();
  }

  /// Fetches a single design by id.
  Future<DocumentSnapshot> getDesign(String designId) {
    return _firestore.collection(_collection).doc(designId).get();
  }
}
