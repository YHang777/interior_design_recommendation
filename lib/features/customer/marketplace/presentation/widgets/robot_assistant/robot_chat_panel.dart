import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/router/route_names.dart';
import '../../../../../../core/utils/formatters.dart';
import '../../../../../../core/utils/user_errors.dart';
import '../../../../../../models/chat_session.dart';
import '../../../../../../models/product.dart';
import '../../../../../../shared/widgets/app_feedback.dart';
import '../../../../../../shared/widgets/filter_chip_bar.dart';
import '../../../../homeowner/data/chat_product_mapper.dart';
import '../../../../homeowner/data/datasources/chat_datasource.dart';
import '../../../../homeowner/presentation/providers/design_providers.dart';
import '../../../../homeowner/presentation/widgets/chat_suggestion_card.dart';
import '../../providers/marketplace_providers.dart';

const List<String> kProductDetailQuickQuestions = [
  'Is it in stock?',
  'What are the dimensions?',
  'How much is delivery?',
  'Is the seller verified?',
  'Is it eco-friendly?',
];

const List<String> kMarketplaceQuickQuestions = [
  "What's on sale?",
  'Show me eco-friendly picks',
  'What fits a small living room?',
];

const String kFitHomeQuestion = 'Does it fit my home?';

class RobotChatPanel extends ConsumerStatefulWidget {
  const RobotChatPanel({
    super.key,
    required this.title,
    this.focusProduct,
    required this.products,
    required this.quickQuestions,
    required this.messages,
    required this.onMessagesChanged,
  });

  final String title;

  final Product? focusProduct;

  final List<Product> products;

  final List<String> quickQuestions;

  final List<ChatMessage> messages;

  final VoidCallback onMessagesChanged;

  @override
  ConsumerState<RobotChatPanel> createState() => _RobotChatPanelState();
}

class _RobotChatPanelState extends ConsumerState<RobotChatPanel> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _sending = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _fillInput(String prompt) {
    setState(() {
      _msgCtrl.text = prompt;
      _msgCtrl.selection =
          TextSelection.collapsed(offset: _msgCtrl.text.length);
    });
  }

  ChatSession? _householdSession() {
    final history = ref.read(chatHistoryProvider);
    final active = history.activeSession;
    if (active != null && (active.style != null || active.room != null)) {
      return active;
    }
    for (final s in history.sessions) {
      if (s.style != null || s.room != null) return s;
    }
    return null;
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    var transcript = <ChatTurn>[
      for (final m in widget.messages) ChatTurn(role: m.role, text: m.text),
      ChatTurn(role: 'user', text: text),
    ];
    if (transcript.length > 20) {
      transcript = transcript.sublist(transcript.length - 20);
    }

    widget.messages.add(
      ChatMessage(role: 'user', text: text, createdAt: DateTime.now()),
    );
    widget.onMessagesChanged();
    _msgCtrl.clear();
    setState(() => _sending = true);
    _scrollToBottom();

    try {
      final home = _householdSession();
      final result = await ref.read(chatDatasourceProvider).send(
            messages: transcript,
            style: home?.style,
            room: home?.room,
            products: productsToChatContext(widget.products),
          );
      if (!mounted) return;
      final live =
          ref.read(marketplaceProductsProvider).valueOrNull ?? const [];
      widget.messages.add(ChatMessage(
        role: 'model',
        text: result.reply,
        createdAt: DateTime.now(),
        suggestions: hydrateChatSuggestions(result.suggestions, live),
      ));
      widget.onMessagesChanged();
    } catch (e) {
      if (!mounted) return;
      widget.messages.add(ChatMessage(
        role: 'model',
        text: userMessage(e,
            fallback: 'Sorry, something went wrong. Please try again.'),
        createdAt: DateTime.now(),
      ));
      widget.onMessagesChanged();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _addToCart(ChatSuggestionSnapshot suggestion) {
    final products =
        ref.read(marketplaceProductsProvider).valueOrNull ?? const [];
    Product? live;
    for (final p in products) {
      if (p.id == suggestion.productId) {
        live = p;
        break;
      }
    }
    final product = live;
    if (product == null || !product.isActive || product.isOutOfStock) {
      showAppSnackbar(context, 'That item is no longer available.');
      return;
    }
    ref.read(cartProvider.notifier).addItem(product);
    showAddedToCartSnack(
      context,
      '${product.name} added to cart',
      onViewCart: () => context.pushNamed(RouteNames.homeownerCart),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(chatHistoryProvider);
    final messages = widget.messages;
    final focus = widget.focusProduct;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close,
                      size: 20, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (focus != null) _FocusBanner(product: focus),
          Expanded(
            child: messages.isEmpty && !_sending
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        focus != null
                            ? 'Ask me anything about this product.'
                            : 'Ask me anything about these products.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: messages.length + (_sending ? 1 : 0),
                    itemBuilder: (_, i) => i < messages.length
                        ? _buildBubble(messages[i])
                        : _buildTypingBubble(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilterChipBar<String>(
                  options: [kFitHomeQuestion, ...widget.quickQuestions],
                  selected: null,
                  onSelected: _fillInput,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('robot-chat-input'),
                          controller: _msgCtrl,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: focus != null
                                ? 'Ask about this product...'
                                : 'Ask about products...',
                            hintStyle: GoogleFonts.poppins(
                                color: AppColors.textHint, fontSize: 14),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.accent, AppColors.accentLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          key: const ValueKey('robot-chat-send'),
                          icon: const Icon(Icons.send,
                              color: Colors.white, size: 20),
                          onPressed: _send,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Message bubbles (cloned from the AI screen's look) ────────────────────

  Widget _buildBubble(ChatMessage msg) {
    final isAI = msg.role == 'model';
    final cards = msg.suggestions ?? const <ChatSuggestionSnapshot>[];

    return Align(
      alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          gradient: isAI
              ? LinearGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.08),
                    AppColors.accentLight.withValues(alpha: 0.04),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isAI ? null : AppColors.accent,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isAI ? 4 : 18),
            bottomRight: Radius.circular(isAI ? 18 : 4),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(msg.text,
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: isAI ? AppColors.textPrimary : Colors.white,
                    height: 1.4)),
            for (final s in cards)
              ChatSuggestionCard(
                suggestion: s,
                onAdd: () => _addToCart(s),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accent.withValues(alpha: 0.08),
              AppColors.accentLight.withValues(alpha: 0.04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: SizedBox(
          height: 20,
          width: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(3, (i) {
              return Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _FocusBanner extends StatelessWidget {
  const _FocusBanner({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined,
              size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            Formatters.myr(product.price),
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
