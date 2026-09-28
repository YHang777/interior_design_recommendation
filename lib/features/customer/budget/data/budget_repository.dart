import 'package:cloud_firestore/cloud_firestore.dart';

import 'budget_plan.dart';

/// Firestore access for the signed-in customer's budget plan.
///
/// Storage: a single `budgetPlan` map field ON the user document
/// `users/{uid}` — deliberately NOT a `users/{uid}/budget` subcollection.
///
/// Why: Firestore security rules do not cascade. The deployed rules match
/// `users/{uid}` with `allow read, write: if isOwner(uid)`, which covers
/// reads/writes of that document (including new map fields) but would NOT
/// cover a subcollection — subcollections need their own match block, which
/// is why `cart` and `wishlist` have explicit rules and a budget path would
/// not pass until rules were redeployed. Writing the field therefore works
/// with the rules exactly as they exist today, and stays inside the
/// owner-only user subtree.
///
/// Profile updates (`DocumentReference.update` with explicit fields) merge
/// and never touch `budgetPlan`; registration creates a brand-new doc for a
/// brand-new uid, so nothing clobbers it either.
class BudgetRepository {
  BudgetRepository(this._db);

  final FirebaseFirestore _db;

  static const String _usersCol = 'users';
  static const String _field = 'budgetPlan';

  /// Live plan for [uid]. Emits `null` until the user saves one (and for a
  /// user document that does not exist yet).
  Stream<BudgetPlan?> watchBudget(String uid) {
    return _db.collection(_usersCol).doc(uid).snapshots().map((snap) {
      final raw = snap.data()?[_field];
      if (raw is! Map<String, dynamic>) return null;
      return BudgetPlan.fromJson(raw);
    });
  }

  /// Merges the plan into the user document. `set(..., merge: true)` is used
  /// instead of `update` so a write never fails on a missing user document
  /// and never rewrites the other profile fields.
  Future<void> saveBudget(String uid, BudgetPlan plan) {
    return _db
        .collection(_usersCol)
        .doc(uid)
        .set({_field: plan.toJson()}, SetOptions(merge: true));
  }
}
