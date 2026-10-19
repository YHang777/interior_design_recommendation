import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../budget/data/budget_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../../presentation/providers/design_providers.dart';
import 'customer_stats.dart';

final purchaseCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(customerOrdersProvider).whenData(countPurchases);
});

final savedDesignCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(savedDesignsProvider).whenData((designs) => designs.length);
});

final customerStatsProvider = Provider<CustomerStats>((ref) {
  return CustomerStats(
    purchases: ref.watch(purchaseCountProvider),
    savedDesigns: ref.watch(savedDesignCountProvider),
    wishlist: AsyncData(ref.watch(wishlistCountProvider)),
    budget: ref.watch(budgetPlanProvider),
  );
});

final recentActivityProvider =
    Provider<AsyncValue<List<ActivityEntry>>>((ref) {
  final orders = ref.watch(customerOrdersProvider);
  final designs = ref.watch(savedDesignsProvider);

  if (orders.hasError && orders.valueOrNull == null) {
    return AsyncError(orders.error!, orders.stackTrace ?? StackTrace.current);
  }
  if (designs.hasError && designs.valueOrNull == null) {
    return AsyncError(designs.error!, designs.stackTrace ?? StackTrace.current);
  }
  if (orders.valueOrNull == null || designs.valueOrNull == null) {
    return const AsyncLoading();
  }

  return AsyncData(buildRecentActivity(
    orders: orders.valueOrNull!,
    designs: designs.valueOrNull!,
    now: DateTime.now(),
  ));
});
