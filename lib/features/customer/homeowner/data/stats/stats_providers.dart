import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../budget/data/budget_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../../presentation/providers/design_providers.dart';
import 'customer_stats.dart';

/// The single place customer-dashboard statistics are computed.
///
/// Every number the dashboard shows comes from one of these providers,
/// each backed by an existing live data source — there are no screen-local
/// calculations and no placeholder values anywhere in this layer:
///
/// | Metric        | Source                                   |
/// |---------------|------------------------------------------|
/// | Purchases     | `customerOrdersProvider` (Firestore)     |
/// | Saved designs | `savedDesignsProvider` (Supabase)        |
/// | Wishlist      | `wishlistCountProvider` (Firestore)      |
/// | Budget        | `budgetPlanProvider` (`users/{uid}` doc) |
/// | Recent feed   | orders + saved designs, sorted by time   |

/// Purchases — non-cancelled orders (see [countPurchases] for the rule and
/// why it matches the supplier screens).
final purchaseCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(customerOrdersProvider).whenData(countPurchases);
});

/// Saved room designs, as a count.
final savedDesignCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(savedDesignsProvider).whenData((designs) => designs.length);
});

/// The combined snapshot the dashboard consumes.
final customerStatsProvider = Provider<CustomerStats>((ref) {
  return CustomerStats(
    purchases: ref.watch(purchaseCountProvider),
    savedDesigns: ref.watch(savedDesignCountProvider),
    // Wishlist state is local-first: its synchronous count is already the
    // honest value while it hydrates (0), so no loading state applies.
    wishlist: AsyncData(ref.watch(wishlistCountProvider)),
    budget: ref.watch(budgetPlanProvider),
  );
});

/// Recent Activity — orders and saved designs merged by real recency.
///
/// Error handling: a source that failed outright (and never produced a
/// value) makes the whole feed untrustworthy, so its error is surfaced
/// for the UI to show a retry state instead of a silently partial list.
/// A source that failed but still holds a last-good value keeps the feed
/// alive with that value.
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
  // At least one source has not produced a value yet → still loading.
  if (orders.valueOrNull == null || designs.valueOrNull == null) {
    return const AsyncLoading();
  }

  return AsyncData(buildRecentActivity(
    orders: orders.valueOrNull!,
    designs: designs.valueOrNull!,
    now: DateTime.now(),
  ));
});
