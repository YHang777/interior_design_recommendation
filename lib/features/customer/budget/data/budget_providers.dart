import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import 'budget_plan.dart';
import 'budget_repository.dart';

// ─── Repository ───────────────────────────────────────────────────────────────

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  return BudgetRepository(FirebaseFirestore.instance);
});

// ─── The store both screens read ─────────────────────────────────────────────

final budgetPlanProvider = StreamProvider<BudgetPlan?>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null || uid.isEmpty) return Stream.value(null);
  return ref.watch(budgetRepositoryProvider).watchBudget(uid);
});
