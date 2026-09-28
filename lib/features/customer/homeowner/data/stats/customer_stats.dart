import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/formatters.dart';
import '../../../../../models/order.dart';
import '../../../../../models/room_design.dart';
import '../../../budget/data/budget_plan.dart';

// ─── CustomerStats ────────────────────────────────────────────────────────────

/// One snapshot of everything the customer dashboard renders.
///
/// Every metric keeps its [AsyncValue] so the UI can honestly distinguish
/// loading ('…'), error ('—') and real data — including a real `0`. Nothing
/// in here is ever seeded with placeholder numbers.
class CustomerStats {
  const CustomerStats({
    required this.purchases,
    required this.savedDesigns,
    required this.wishlist,
    required this.budget,
  });

  /// Non-cancelled orders placed by the signed-in customer.
  final AsyncValue<int> purchases;

  /// Saved room designs (Supabase `room_designs` for this user).
  final AsyncValue<int> savedDesigns;

  /// Wishlist products. Not rendered on the dashboard today, kept here so
  /// other screens (or a future admin view) get it from the same place.
  final AsyncValue<int> wishlist;

  /// The persisted budget plan. `value == null` means "never saved" (or
  /// signed out) — render a dash, never a fake figure.
  final AsyncValue<BudgetPlan?> budget;

  /// Budget to display: `RM 4,200` once saved, `RM —` when unset.
  /// Callers should still gate on [budget]'s loading/error states first.
  String get budgetLabel {
    final rm = budget.valueOrNull?.budgetRm;
    if (rm == null) return 'RM —';
    return Formatters.myr(rm);
  }
}

// ─── Purchases ────────────────────────────────────────────────────────────────

/// Purchases = orders that were NOT cancelled.
///
/// This matches the house rule used by the supplier screens
/// (`revenueOrders` in `supplier_providers.dart`): a cancelled order is
/// refunded and never counts as sold, so both sides of the marketplace
/// agree on what an order count means. Pending/confirmed/shipped/delivered
/// all count — the customer did buy them.
int countPurchases(List<Order> orders) =>
    orders.where((o) => o.status != OrderStatus.cancelled).length;

// ─── Recent Activity ──────────────────────────────────────────────────────────

/// What kind of real event a feed row represents. Icons/colors are mapped
/// from this in the presentation layer, never stored here.
enum ActivityKind {
  orderPlaced,
  orderConfirmed,
  orderShipped,
  orderDelivered,
  orderCancelled,
  designSaved,
}

/// One real event for the dashboard's Recent Activity feed.
class ActivityEntry {
  const ActivityEntry({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.timestamp,
  });

  final ActivityKind kind;

  /// e.g. "Order ORD-20260902-4821 shipped".
  final String title;

  /// e.g. "3 items · RM 420" or "Living Room design".
  final String subtitle;

  /// The moment the event actually happened (from data, never "now").
  final DateTime timestamp;
}

ActivityKind _kindForStatus(OrderStatus status) => switch (status) {
      OrderStatus.pending => ActivityKind.orderPlaced,
      OrderStatus.confirmed => ActivityKind.orderConfirmed,
      OrderStatus.shipped => ActivityKind.orderShipped,
      OrderStatus.delivered => ActivityKind.orderDelivered,
      OrderStatus.cancelled => ActivityKind.orderCancelled,
    };

String _verbForStatus(OrderStatus status) => switch (status) {
      // A pending order's history entry is the moment it was placed.
      OrderStatus.pending => 'placed',
      OrderStatus.confirmed => 'confirmed',
      OrderStatus.shipped => 'shipped',
      OrderStatus.delivered => 'delivered',
      OrderStatus.cancelled => 'cancelled',
    };

/// Builds the Recent Activity feed from real events only:
///
/// - one row per order showing its LATEST status event (timestamp taken
///   from `statusHistory[currentStatus]`, falling back to `createdAt`),
/// - one row per saved design (its `createdAt`).
///
/// Sorted newest-first, capped at [limit]. Returns an empty list when
/// there is nothing to show — callers must render an empty state rather
/// than invent rows.
List<ActivityEntry> buildRecentActivity({
  required List<Order> orders,
  required List<RoomDesign> designs,
  required DateTime now,
  int limit = 6,
}) {
  final entries = <ActivityEntry>[];

  for (final o in orders) {
    entries.add(ActivityEntry(
      kind: _kindForStatus(o.status),
      title: 'Order ${Formatters.formatOrderNumber(o.orderNumber)} '
          '${_verbForStatus(o.status)}',
      subtitle: '${o.items.length} item${o.items.length == 1 ? '' : 's'} '
          '· ${Formatters.myr(o.total)}',
      timestamp: o.statusHistory[o.status.name] ?? o.createdAt,
    ));
  }

  for (final d in designs) {
    entries.add(ActivityEntry(
      kind: ActivityKind.designSaved,
      title: 'Saved “${d.name}”',
      subtitle: '${d.roomTypeLabel} design',
      timestamp: d.createdAt,
    ));
  }

  entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return entries.take(limit).toList();
}

/// Compact relative timestamp: "Just now", "5m ago", "2h ago",
/// "Yesterday", "3d ago", then an absolute date. [now] is injected so the
/// function is deterministic in tests.
String relativeTimeLabel(DateTime at, DateTime now) {
  // Future timestamps (clock skew between devices) read as "Just now"
  // rather than a confusing "in 3h".
  final diff = now.difference(at);
  if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inHours < 48) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return Formatters.shortDate(at);
}
