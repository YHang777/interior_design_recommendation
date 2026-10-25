import '../../../../models/room_design.dart';
import '../../budget/data/budget_plan.dart';

enum ProactiveChipKind { prompt, action }

class ProactiveChip {
  const ProactiveChip({
    required this.label,
    required this.kind,
    this.prompt,
    this.path,
  });

  final String label;
  final ProactiveChipKind kind;
  final String? prompt;
  final String? path;
}

class ProactiveInputs {
  const ProactiveInputs({
    required this.cartCount,
    required this.cartSubtotal,
    required this.budget,
    required this.estimateRm,
    required this.plan,
    required this.pendingPlacements,
    required this.latestOrderStatus,
    required this.wishlistCount,
  });

  final int cartCount;
  final int cartSubtotal;
  final BudgetPlan? budget;
  final int? estimateRm;
  final RoomDesign? plan;
  final int pendingPlacements;
  final String? latestOrderStatus;
  final int wishlistCount;
}

bool planHasLighting(RoomDesign? plan) {
  if (plan == null) return false;
  for (final item in plan.furniture) {
    final haystack = '${item.name} ${item.iconName}'.toLowerCase();
    if (haystack.contains('lamp') || haystack.contains('light')) return true;
  }
  return false;
}

String _roomWord(RoomDesign plan) {
  const labels = {
    'living_room': 'living room',
    'bedroom': 'bedroom',
    'kitchen': 'kitchen',
    'bathroom': 'bathroom',
    'dining_room': 'dining room',
    'home_office': 'home office',
  };
  return labels[plan.roomType] ?? 'room';
}

List<ProactiveChip> buildProactiveChips(
  ProactiveInputs inputs, {
  List<String> fillers = const [],
  int max = 3,
}) {
  final chips = <ProactiveChip>[];
  final budget = inputs.budget;
  final plan = inputs.plan;
  final planEmpty = plan == null || plan.furniture.isEmpty;

  if (inputs.pendingPlacements > 0) {
    chips.add(const ProactiveChip(
      label: 'Place pending items',
      kind: ProactiveChipKind.action,
      path: '/design',
    ));
  }

  if (inputs.cartCount > 0) {
    chips.add(ProactiveChip(
      label: 'Review my cart (${inputs.cartCount})',
      kind: ProactiveChipKind.action,
      path: '/marketplace/cart',
    ));
  }

  if (budget != null) {
    final over = (inputs.estimateRm != null && inputs.estimateRm! > budget.budgetRm) ||
        inputs.cartSubtotal > budget.budgetRm;
    chips.add(over
        ? const ProactiveChip(
            label: "I'm over budget",
            kind: ProactiveChipKind.prompt,
            prompt: "I'm over my budget — what should I change?",
          )
        : const ProactiveChip(
            label: 'What else fits my budget?',
            kind: ProactiveChipKind.prompt,
            prompt: 'What else could I add that still fits my budget?',
          ));
  }

  if (planEmpty && inputs.cartCount > 0) {
    chips.add(const ProactiveChip(
      label: 'Plan my room with these',
      kind: ProactiveChipKind.prompt,
      prompt: 'Help me plan my room with the items in my cart.',
    ));
  } else if (plan != null && !planHasLighting(plan)) {
    chips.add(ProactiveChip(
      label: 'Lighting for my ${_roomWord(plan)}',
      kind: ProactiveChipKind.prompt,
      prompt: 'My ${_roomWord(plan)} plan has no lighting yet — what should I add?',
    ));
  }

  final status = inputs.latestOrderStatus;
  if (status == 'waitingCollection' || status == 'confirmed') {
    chips.add(const ProactiveChip(
      label: "Where's my order?",
      kind: ProactiveChipKind.prompt,
      prompt: "Where's my latest order?",
    ));
  }

  if (budget == null) {
    chips.add(const ProactiveChip(
      label: 'Set my budget',
      kind: ProactiveChipKind.action,
      path: '/budget',
    ));
  }

  if (inputs.wishlistCount >= 3) {
    chips.add(const ProactiveChip(
      label: 'Compare my saved items',
      kind: ProactiveChipKind.prompt,
      prompt: 'Compare the items I saved — which should I pick?',
    ));
  }

  final out = chips.take(max).toList();
  for (final filler in fillers) {
    if (out.length >= max) break;
    if (out.any((c) => c.label == filler)) continue;
    out.add(ProactiveChip(
      label: filler,
      kind: ProactiveChipKind.prompt,
      prompt: filler,
    ));
  }
  return out;
}
