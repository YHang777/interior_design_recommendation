import 'package:cloud_firestore/cloud_firestore.dart';

import 'budget_plan.dart';

class BudgetRepository {
  BudgetRepository(this._db);

  final FirebaseFirestore _db;

  static const String _usersCol = 'users';
  static const String _field = 'budgetPlan';

  Stream<BudgetPlan?> watchBudget(String uid) {
    return _db.collection(_usersCol).doc(uid).snapshots().map((snap) {
      final raw = snap.data()?[_field];
      if (raw is! Map<String, dynamic>) return null;
      return BudgetPlan.fromJson(raw);
    });
  }

  Future<void> saveBudget(String uid, BudgetPlan plan) {
    return _db
        .collection(_usersCol)
        .doc(uid)
        .set({_field: plan.toJson()}, SetOptions(merge: true));
  }
}
