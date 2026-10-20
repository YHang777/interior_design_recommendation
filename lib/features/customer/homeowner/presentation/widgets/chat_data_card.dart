import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../models/chat_session.dart';
import '../../../../../models/room_design.dart';
import '../../../budget/data/budget_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../../data/chat_state_context.dart';
import '../providers/design_providers.dart';
import 'chat_card_actions.dart';

class ChatDataCard extends ConsumerWidget {
  const ChatDataCard({super.key, required this.topic});

  final ChatDataTopic topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = switch (topic) {
      ChatDataTopic.cart => _cartBody(ref),
      ChatDataTopic.budget => _budgetBody(ref),
      ChatDataTopic.plan => _planBody(ref),
      ChatDataTopic.orders => _ordersBody(ref),
      ChatDataTopic.wishlist => _wishlistBody(ref),
    };

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: body),
          TextButton(
            onPressed: () => _open(context, ref),
            child: Text(
              'Open',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    final actions = ChatCardActions(context: context, ref: ref);
    switch (topic) {
      case ChatDataTopic.cart:
        actions.openCart();
      case ChatDataTopic.budget:
        actions.openBudget();
      case ChatDataTopic.plan:
        actions.openPlan();
      case ChatDataTopic.orders:
        actions.openOrders();
      case ChatDataTopic.wishlist:
        actions.openWishlist();
    }
  }

  Widget _line(String text, {bool strong = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            color: strong ? AppColors.textPrimary : AppColors.textSecondary,
            height: 1.3,
          ),
        ),
      );

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      );

  Widget _cartBody(WidgetRef ref) {
    final rows = ref.watch(cartRowsProvider);
    final count = ref.watch(cartCountProvider);
    final subtotal = ref.watch(cartTotalProvider);
    final lines = <Widget>[
      if (rows.isEmpty)
        _line('Your cart is empty.')
      else
        ...[
          for (final row in rows.take(5))
            _line(
              '${row.live.name} ×${row.effectiveQty} — '
              '${Formatters.myr(row.live.price * row.effectiveQty)}',
            ),
          if (rows.length > 5) _line('+${rows.length - 5} more'),
          _line(
            '$count item${count == 1 ? '' : 's'} · ${Formatters.myr(subtotal)}',
            strong: true,
          ),
        ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [_title('Your cart'), ...lines],
    );
  }

  Widget _budgetBody(WidgetRef ref) {
    final budget = ref.watch(budgetPlanProvider).valueOrNull;
    if (budget == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _title('Your budget'),
          _line('No budget set yet.'),
        ],
      );
    }
    final products =
        ref.watch(marketplaceProductsProvider).valueOrNull ?? const [];
    final estimate = budgetEstimate(budget: budget, products: products);
    final lines = <Widget>[
      _line('Cap ${Formatters.myr(budget.budgetRm)} for ${budget.room}'
          '${budget.ecoFriendly ? ' · eco-friendly' : ''}',
          strong: true),
      if (estimate != null) ...[
        _line('Catalogue median estimate ${Formatters.myr(estimate.$1)}'),
        _line(estimate.$2 >= 0
            ? 'Under cap by ${Formatters.myr(estimate.$2)}'
            : 'Over cap by ${Formatters.myr(estimate.$2.abs())}'),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [_title('Your budget'), ...lines],
    );
  }

  Widget _planBody(WidgetRef ref) {
    final plans = ref.watch(savedDesignsProvider).valueOrNull ?? const [];
    final pending = ref.watch(pendingChatPlacementsProvider).length;
    final plan = plans.isNotEmpty ? plans.first : null;
    final lines = <Widget>[];
    if (plan == null) {
      lines.add(_line('No saved room plan yet.'));
    } else {
      lines.add(_line(
        '${plan.name} · ${_roomLabel(plan)} · '
        '${plan.widthCm.round()}×${plan.heightCm.round()} cm',
        strong: true,
      ));
      for (final item in plan.furniture.take(5)) {
        lines.add(_line(
          '${item.name} ${item.width.round()}×${item.height.round()} cm',
        ));
      }
      if (plan.furniture.length > 5) {
        lines.add(_line('+${plan.furniture.length - 5} more'));
      }
    }
    if (pending > 0) {
      lines.add(_line(
        '$pending item${pending == 1 ? '' : 's'} waiting to be placed',
        strong: true,
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [_title('Your room plan'), ...lines],
    );
  }

  Widget _ordersBody(WidgetRef ref) {
    final orders = ref.watch(customerOrdersProvider).valueOrNull ?? const [];
    final newest = [...orders]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final lines = <Widget>[
      if (newest.isEmpty)
        _line('No orders yet.')
      else
        for (final order in newest.take(3))
          _line(
            '${Formatters.formatOrderNumber(order.orderNumber)} '
            '${order.status.label} — ${Formatters.myr(order.total)}',
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [_title('Your recent orders'), ...lines],
    );
  }

  Widget _wishlistBody(WidgetRef ref) {
    final count = ref.watch(wishlistCountProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _title('Your wishlist'),
        _line(count == 0
            ? 'Nothing saved yet.'
            : '$count saved item${count == 1 ? '' : 's'}',
            strong: count > 0),
      ],
    );
  }

  String _roomLabel(RoomDesign plan) {
    const labels = {
      'living_room': 'Living room',
      'bedroom': 'Bedroom',
      'kitchen': 'Kitchen',
      'bathroom': 'Bathroom',
      'dining_room': 'Dining room',
      'home_office': 'Home office',
    };
    return labels[plan.roomType] ?? plan.roomType;
  }
}
