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

/// The signed-in customer's saved budget plan, live.
///
/// - `AsyncData(plan)`  — a plan exists (dashboard shows its `budgetRm`).
/// - `AsyncData(null)`  — loaded, but nothing saved yet (dashboard shows a
///   dash; the planner starts empty). Also the value while signed out.
/// - `AsyncLoading`     — waiting for the first snapshot.
/// - `AsyncError`       — the read failed (dashboard shows a dash, never a
///   fabricated figure).
///
/// The planner screen writes through [budgetRepositoryProvider]; this
/// stream is the single source of truth afterwards, so the dashboard's
/// Budget tile and the planner always agree.
final budgetPlanProvider = StreamProvider<BudgetPlan?>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null || uid.isEmpty) return Stream.value(null);
  return ref.watch(budgetRepositoryProvider).watchBudget(uid);
});
