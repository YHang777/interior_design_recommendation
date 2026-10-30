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

Future<void> showChatQuickSelectSheet(
  BuildContext context, {
  required String? style,
  required String? room,
  required List<String> styles,
  required List<String> rooms,
  List<String> fillers = const [],
  required ValueChanged<String?> onStyle,
  required ValueChanged<String?> onRoom,
  required ValueChanged<String> onPrompt,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ChatQuickSelectSheet(
      style: style,
      room: room,
      styles: styles,
      rooms: rooms,
      fillers: fillers,
      onStyle: onStyle,
      onRoom: onRoom,
      onPrompt: onPrompt,
    ),
  );
}

class ChatQuickSelectSheet extends ConsumerStatefulWidget {
  const ChatQuickSelectSheet({
    super.key,
    required this.style,
    required this.room,
    required this.styles,
    required this.rooms,
    this.fillers = const [],
    required this.onStyle,
    required this.onRoom,
    required this.onPrompt,
  });

  final String? style;
  final String? room;
  final List<String> styles;
  final List<String> rooms;
  final List<String> fillers;
  final ValueChanged<String?> onStyle;
  final ValueChanged<String?> onRoom;
  final ValueChanged<String> onPrompt;

  @override
  ConsumerState<ChatQuickSelectSheet> createState() =>
      _ChatQuickSelectSheetState();
}

class _ChatQuickSelectSheetState extends ConsumerState<ChatQuickSelectSheet> {
  late String? _style = widget.style;
  late String? _room = widget.room;

  @override
  Widget build(BuildContext context) {
    final chips = buildProactiveChips(
      _inputs(ref),
      fillers: widget.fillers,
      max: 12,
    );
    final prompts = [
      for (final chip in chips)
        if (chip.kind == ProactiveChipKind.prompt) chip,
    ];
    final actions = [
      for (final chip in chips)
        if (chip.kind == ProactiveChipKind.action) chip,
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          shrinkWrap: true,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Quick actions',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close,
                      size: 20, color: AppColors.textSecondary),
                ),
              ],
            ),
            _section('Design style'),
            _wrap([
              for (final option in widget.styles)
                _selectChip(
                  label: option,
                  selected: _style == option,
                  onTap: () => _pickStyle(option),
                ),
            ]),
            _section('Room type'),
            _wrap([
              for (final option in widget.rooms)
                _selectChip(
                  label: option,
                  selected: _room == option,
                  onTap: () => _pickRoom(option),
                ),
            ]),
            if (prompts.isNotEmpty) ...[
              _section('Try asking'),
              _wrap([
                for (final chip in prompts)
                  _promptChip(chip.label, () {
                    widget.onPrompt(chip.prompt ?? chip.label);
                    Navigator.pop(context);
                  }),
              ]),
            ],
            if (actions.isNotEmpty) ...[
              _section('Jump to'),
              for (final chip in actions) _actionRow(chip),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(
          title.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.textHint,
          ),
        ),
      );

  Widget _wrap(List<Widget> children) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: children,
      );

  Widget _selectChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? Colors.white : AppColors.textSecondary,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.surfaceElevated,
      side: BorderSide(
        color: selected ? AppColors.accent : AppColors.border,
        width: selected ? 1.5 : 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _promptChip(String label, VoidCallback onTap) {
    return ActionChip(
      avatar: const Icon(Icons.auto_awesome,
          size: 14, color: AppColors.accent),
      label: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      onPressed: onTap,
      backgroundColor: AppColors.surfaceElevated,
      side: const BorderSide(color: AppColors.border, width: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _actionRow(ProactiveChip chip) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.pop(context);
            _navigate(chip.path);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_iconFor(chip.path),
                      size: 17, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    chip.label,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textHint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String? path) {
    if (path == null) return Icons.north_east;
    if (path.contains('cart')) return Icons.shopping_cart_outlined;
    if (path.contains('budget')) return Icons.account_balance_wallet_outlined;
    if (path == '/design') return Icons.room_preferences_outlined;
    return Icons.north_east;
  }

  void _pickStyle(String option) {
    setState(() => _style = _style == option ? null : option);
    widget.onStyle(_style);
  }

  void _pickRoom(String option) {
    setState(() => _room = _room == option ? null : option);
    widget.onRoom(_room);
  }

  void _navigate(String? path) {
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
