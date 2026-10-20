import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/order.dart';
import '../../../../models/product.dart';
import '../../../../models/room_design.dart';
import '../../budget/data/budget_estimates.dart';
import '../../budget/data/budget_plan.dart';
import '../../budget/data/budget_providers.dart';
import '../../marketplace/presentation/providers/marketplace_providers.dart';
import '../presentation/providers/design_providers.dart';

const kChatStateCartLines = 8;
const kChatStatePlacedItems = 10;
const kChatStateOrders = 3;
const kChatStateNameClip = 48;

String _clip(String value, int max) {
  final t = value.trim();
  if (t.length <= max) return t;
  return t.substring(0, max);
}

(int estimateRm, int remainingRm)? budgetEstimate({
  required BudgetPlan budget,
  required List<Product> products,
}) {
  if (products.isEmpty) return null;
  final estimate = estimateTotal(
    buildEstimateLines(products, ecoFriendly: budget.ecoFriendly),
  );
  return (estimate, budget.budgetRm - estimate);
}

Map<String, Object?>? buildChatStateJson({
  required List<CartRow> cartRows,
  required int cartCount,
  required int cartSubtotal,
  required BudgetPlan? budget,
  int? estimateRm,
  int? remainingRm,
  required List<Order> orders,
  required RoomDesign? plan,
  required int pendingPlacements,
  int? wishlistCount,
}) {
  final sections = <String, Object?>{};

  if (cartRows.isNotEmpty) {
    sections['cart'] = {
      'items': [
        for (final row in cartRows.take(kChatStateCartLines))
          {
            'productId': row.live.id,
            'name': _clip(row.live.name, kChatStateNameClip),
            'qty': row.effectiveQty,
            'lineTotal': row.live.price * row.effectiveQty,
          },
      ],
      'itemCount': cartCount,
      'subtotal': cartSubtotal,
    };
  }

  if (plan != null) {
    sections['plan'] = {
      if (plan.name.trim().isNotEmpty) 'name': _clip(plan.name, 60),
      if (plan.roomType.trim().isNotEmpty) 'roomType': _clip(plan.roomType, 40),
      'widthCm': plan.widthCm.round(),
      'heightCm': plan.heightCm.round(),
      if (plan.furniture.isNotEmpty)
        'placed': [
          for (final item in plan.furniture.take(kChatStatePlacedItems))
            {
              'name': _clip(item.name, kChatStateNameClip),
              'wCm': item.width.round(),
              'hCm': item.height.round(),
            },
        ],
      if (pendingPlacements > 0) 'pendingPlacements': pendingPlacements,
    };
  } else if (pendingPlacements > 0) {
    sections['plan'] = {'pendingPlacements': pendingPlacements};
  }

  if (budget != null) {
    sections['budget'] = {
      'capRm': budget.budgetRm,
      'room': _clip(budget.room, 40),
      'ecoFriendly': budget.ecoFriendly,
      if (estimateRm != null) 'estimateRm': estimateRm,
      if (remainingRm != null) 'remainingRm': remainingRm,
    };
  }

  if (orders.isNotEmpty) {
    final newest = [...orders]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    sections['orders'] = [
      for (final order in newest.take(kChatStateOrders))
        {
          'orderNumber': _clip(order.orderNumber, 64),
          'status': _clip(order.status.name, 32),
          'total': order.total,
          'itemCount':
              order.items.fold<int>(0, (sum, item) => sum + item.quantity),
          'placedAt': order.createdAt.toUtc().toIso8601String(),
        },
    ];
  }

  if (wishlistCount != null && wishlistCount > 0) {
    sections['wishlistCount'] = wishlistCount;
  }

  return sections.isEmpty ? null : sections;
}

final chatStatePayloadProvider = Provider<Map<String, Object?>?>((ref) {
  final budget = ref.watch(budgetPlanProvider).valueOrNull;
  final products =
      ref.watch(marketplaceProductsProvider).valueOrNull ?? const <Product>[];

  int? estimateRm;
  int? remainingRm;
  final estimate = budget == null
      ? null
      : budgetEstimate(budget: budget, products: products);
  if (estimate != null) {
    estimateRm = estimate.$1;
    remainingRm = estimate.$2;
  }

  final plans = ref.watch(savedDesignsProvider).valueOrNull ?? const [];

  return buildChatStateJson(
    cartRows: ref.watch(cartRowsProvider),
    cartCount: ref.watch(cartCountProvider),
    cartSubtotal: ref.watch(cartTotalProvider),
    budget: budget,
    estimateRm: estimateRm,
    remainingRm: remainingRm,
    orders: ref.watch(customerOrdersProvider).valueOrNull ?? const [],
    plan: plans.isNotEmpty ? plans.first : null,
    pendingPlacements: ref.watch(pendingChatPlacementsProvider).length,
    wishlistCount: ref.watch(wishlistCountProvider),
  );
});
