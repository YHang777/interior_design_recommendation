import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../budget/data/budget_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../../data/chat_proactive_chips.dart';
import '../../data/chat_state_context.dart';
import '../providers/design_providers.dart';

class ChatProactiveChipBar extends ConsumerWidget {
  const ChatProactiveChipBar({
    super.key,
    required this.onPrompt,
    this.fillers = const [],
  });

  final ValueChanged<String> onPrompt;
  final List<String> fillers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chips = buildProactiveChips(_inputs(ref), fillers: fillers);
    if (chips.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final chip in chips)
            _chip(chip, () {
              if (chip.kind == ProactiveChipKind.prompt) {
                onPrompt(chip.prompt ?? chip.label);
                return;
              }
              _navigate(context, chip.path);
            }),
        ],
      ),
    );
  }

  Widget _chip(ProactiveChip chip, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(
        chip.label,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
      selected: false,
      onSelected: (_) => onTap(),
      backgroundColor: AppColors.surfaceElevated,
      side: const BorderSide(color: AppColors.border, width: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  void _navigate(BuildContext context, String? path) {
    if (path == null) return;
    final router = GoRouter.of(context);
    if (path == '/design' || path == '/marketplace') {
      router.go(path);
    } else {
      router.push(path);
    }
  }

  ProactiveInputs _inputs(WidgetRef ref) {
    final budget = ref.watch(budgetPlanProvider).valueOrNull;
    final products =
        ref.watch(marketplaceProductsProvider).valueOrNull ?? const [];
    final estimate = budget == null
        ? null
        : budgetEstimate(budget: budget, products: products);
    final plans = ref.watch(savedDesignsProvider).valueOrNull ?? const [];
    final orders = ref.watch(customerOrdersProvider).valueOrNull ?? const [];
    final newest = [...orders]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ProactiveInputs(
      cartCount: ref.watch(cartCountProvider),
      cartSubtotal: ref.watch(cartTotalProvider),
      budget: budget,
      estimateRm: estimate?.$1,
      plan: plans.isNotEmpty ? plans.first : null,
      pendingPlacements: ref.watch(pendingChatPlacementsProvider).length,
      latestOrderStatus: newest.isEmpty ? null : newest.first.status.name,
      wishlistCount: ref.watch(wishlistCountProvider),
    );
  }
}
