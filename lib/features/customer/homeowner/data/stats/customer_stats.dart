import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/formatters.dart';
import '../../../../../models/order.dart';
import '../../../../../models/room_design.dart';
import '../../../budget/data/budget_plan.dart';

// ─── CustomerStats ────────────────────────────────────────────────────────────

class CustomerStats {
  const CustomerStats({
    required this.purchases,
    required this.savedDesigns,
    required this.wishlist,
    required this.budget,
  });

  final AsyncValue<int> purchases;

  final AsyncValue<int> savedDesigns;

  final AsyncValue<int> wishlist;

  final AsyncValue<BudgetPlan?> budget;

  String get budgetLabel {
    final rm = budget.valueOrNull?.budgetRm;
    if (rm == null) return 'RM —';
    return Formatters.myr(rm);
  }
}

// ─── Purchases ────────────────────────────────────────────────────────────────

int countPurchases(List<Order> orders) =>
    orders.where((o) => o.status != OrderStatus.cancelled).length;

// ─── Recent Activity ──────────────────────────────────────────────────────────

enum ActivityKind {
  orderPlaced,
  orderConfirmed,
  orderReadyForCollection,
  orderCollected,
  orderCancelled,
  designSaved,
}

class ActivityEntry {
  const ActivityEntry({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.timestamp,
  });

  final ActivityKind kind;

  final String title;

  final String subtitle;

  final DateTime timestamp;
}

ActivityKind _kindForStatus(OrderStatus status) => switch (status) {
      OrderStatus.pending => ActivityKind.orderPlaced,
      OrderStatus.confirmed => ActivityKind.orderConfirmed,
      OrderStatus.waitingCollection => ActivityKind.orderReadyForCollection,
      OrderStatus.collected => ActivityKind.orderCollected,
      OrderStatus.cancelled => ActivityKind.orderCancelled,
    };

String _verbForStatus(OrderStatus status) => switch (status) {
      OrderStatus.pending => 'placed',
      OrderStatus.confirmed => 'confirmed',
      OrderStatus.waitingCollection => 'is ready for collection',
      OrderStatus.collected => 'collected',
      OrderStatus.cancelled => 'cancelled',
    };

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

String relativeTimeLabel(DateTime at, DateTime now) {
  final diff = now.difference(at);
  if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inHours < 48) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return Formatters.shortDate(at);
}
