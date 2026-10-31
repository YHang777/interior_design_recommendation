import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/user_errors.dart';
import '../../../../../models/chat_session.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/gradient_scaffold.dart';
import '../../../../../shared/widgets/page_heading.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../../data/chat_product_mapper.dart';
import '../../data/chat_state_answers.dart';
import '../../data/chat_state_context.dart';
import '../../data/datasources/chat_datasource.dart';
import '../providers/design_providers.dart';
import '../widgets/chat_card_actions.dart';
import '../widgets/chat_data_card.dart';
import '../widgets/chat_quick_select_sheet.dart';
import '../widgets/chat_suggestion_card.dart';
import '../widgets/chat_typing_bubble.dart';

class AiRecommendationScreen extends ConsumerStatefulWidget {
  const AiRecommendationScreen({super.key});

  @override
  ConsumerState<AiRecommendationScreen> createState() =>
      _AiRecommendationScreenState();
}

class _AiRecommendationScreenState
    extends ConsumerState<AiRecommendationScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _sending = false;

  String? _chipStyle;
  String? _chipRoom;

  static const _styles = [
    'Modern',
    'Classic',
    'Minimalist',
    'Bohemian',
    'Scandinavian',
    'Industrial',
  ];

  static const _rooms = [
    'Living Room',
    'Bedroom',
    'Kitchen',
    'Bathroom',
    'Dining Room',
    'Home Office',
  ];

  static const _promptSuggestions = [
    'Suggest a style for my living room',
    'What colors make a bedroom feel calm?',
    'Give me modern ideas for a small kitchen',
  ];

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String get _composedPhrase =>
      [_chipStyle, _chipRoom].whereType<String>().join(' ').trim();

  void _fillInputWithPhrase() {
    _msgCtrl.text = _composedPhrase;
    _msgCtrl.selection =
        TextSelection.collapsed(offset: _msgCtrl.text.length);
  }

  void _syncContextToSession() {
    final notifier = ref.read(chatHistoryProvider.notifier);
    notifier.setActiveContext(style: _chipStyle, room: _chipRoom);
  }

  void _fillSuggestion(String prompt) {
    setState(() {
      _msgCtrl.text = prompt;
      _msgCtrl.selection =
          TextSelection.collapsed(offset: _msgCtrl.text.length);
    });
  }

  void _startNewChat() {
    ref.read(chatHistoryProvider.notifier).startNewChat();
    setState(() {
      _chipStyle = null;
      _chipRoom = null;
      _msgCtrl.clear();
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    final historyNotifier = ref.read(chatHistoryProvider.notifier);
    final sessionId = historyNotifier.ensureActiveSession(
      style: _chipStyle,
      room: _chipRoom,
    );

    final session = ref.read(chatHistoryProvider).activeSession;
    var transcript = <ChatTurn>[
      for (final m in session?.messages ?? const <ChatMessage>[])
        ChatTurn(role: m.role, text: m.text),
      ChatTurn(role: 'user', text: text),
    ];
    if (transcript.length > 20) {
      transcript = transcript.sublist(transcript.length - 20);
    }

    historyNotifier.addMessage(sessionId, role: 'user', text: text);
    _msgCtrl.clear();
    setState(() => _sending = true);
    _scrollToBottom();

    final match = matchStateQuestion(text);
    final dataCard =
        match == null ? null : ChatDataCardRef(topic: match.topic);

    if (match != null && match.isPure) {
      historyNotifier.addMessage(
        sessionId,
        role: 'model',
        text: cannedLine(match.topic),
        dataCard: dataCard,
      );
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
      return;
    }

    try {
      final result = await ref.read(chatDatasourceProvider).send(
            messages: transcript,
            style: _chipStyle,
            room: _chipRoom,
            products: productsToChatContext(
              ref.read(marketplaceProductsProvider).valueOrNull ?? const [],
            ),
            state: ref.read(chatStatePayloadProvider),
          );
      if (!mounted) return;
      historyNotifier.addMessage(
        sessionId,
        role: 'model',
        text: result.reply,
        suggestions: hydrateChatSuggestions(
          result.suggestions,
          ref.read(marketplaceProductsProvider).valueOrNull ?? const [],
        ),
        dataCard: dataCard,
      );
    } catch (e) {
      if (!mounted) return;
      historyNotifier.addMessage(
        sessionId,
        role: 'model',
        text: userMessage(e,
            fallback: 'Sorry, something went wrong. Please try again.'),
        dataCard: dataCard,
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      if (animated) {
        _scrollCtrl.animateTo(target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      } else {
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  void _openHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ChatHistorySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(marketplaceProductsProvider);
    // Keeps budget/cart/orders/designs streams subscribed from mount so the
    // first send reads warm data instead of racing an unwatched stream.
    ref.watch(chatStatePayloadProvider);
    final history = ref.watch(chatHistoryProvider);

    ref.listen(chatHistoryProvider, (previous, next) {
      if (previous?.activeSessionId != next.activeSessionId) {
        _chipStyle = next.activeSession?.style;
        _chipRoom = next.activeSession?.room;
        _scrollToBottom(animated: false);
      }
    });

    final messages =
        history.activeSession?.messages ?? const <ChatMessage>[];

    return GradientScaffold(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: PageHeading(
              title: 'AI Design Assistant',
              actions: [
                IconButton(
                  tooltip: 'New chat',
                  onPressed: _startNewChat,
                  icon: const Icon(Icons.edit_note,
                      color: AppColors.textSecondary),
                ),
                IconButton(
                  tooltip: 'History',
                  onPressed: _openHistorySheet,
                  icon: const Icon(Icons.history,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: messages.isEmpty && !_sending
                ? _buildWelcome()
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

          _buildComposer(context),
        ],
      ),
    );
  }

  // ─── Welcome (no messages yet) ─────────────────────────────────────────────

  Widget _buildWelcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.accent.withValues(alpha: 0.15),
                        AppColors.accentLight.withValues(alpha: 0.08),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.psychology,
                      size: 36, color: AppColors.accent),
                ),
                const SizedBox(height: 14),
                Text('Welcome to the design assistant',
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Text(
                    'Ask about styles, rooms, or furniture picks — or start '
                    'with a suggestion below.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 28),
          for (final prompt in _promptSuggestions) ...[
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _fillSuggestion(prompt),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 18, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(prompt,
                          style: GoogleFonts.poppins(
                              fontSize: 13.5,
                              color: AppColors.textPrimary)),
                    ),
                    const Icon(Icons.north_east,
                        size: 16, color: AppColors.textHint),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─── Composer: quick actions live behind a sheet, not inline chips ─────────

  void _openQuickSelect() {
    showChatQuickSelectSheet(
      context,
      style: _chipStyle,
      room: _chipRoom,
      styles: _styles,
      rooms: _rooms,
      fillers: _promptSuggestions,
      onStyle: (value) {
        setState(() {
          _chipStyle = value;
          _fillInputWithPhrase();
        });
        _syncContextToSession();
      },
      onRoom: (value) {
        setState(() {
          _chipRoom = value;
          _fillInputWithPhrase();
        });
        _syncContextToSession();
      },
      onPrompt: _fillSuggestion,
    );
  }

  Widget _buildComposer(BuildContext context) {
    // With extendBody the shell's _BodyBuilder anchors the content bottom to
    // max(keyboard, nav bar height), so a constant bottom padding IS the gap:
    // 12px above the keyboard while it is open, 12px above the nav pill at
    // rest — no metrics reads, no stale jumps.
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: IconButton(
              key: const ValueKey('ai-quick-select'),
              tooltip: 'Quick actions',
              icon: const Icon(Icons.bolt, size: 20, color: AppColors.accent),
              onPressed: _openQuickSelect,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
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
                      controller: _msgCtrl,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Ask about designs...',
                        hintStyle: GoogleFonts.poppins(
                            color: AppColors.textHint, fontSize: 14),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 10),
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
                      icon: const Icon(Icons.send,
                          color: Colors.white, size: 20),
                      onPressed: _sendMessage,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Message bubbles ───────────────────────────────────────────────────────

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
            if (msg.dataCard != null)
              ChatDataCard(topic: msg.dataCard!.topic),
            for (final s in cards)
              ChatSuggestionCard(
                suggestion: s,
                actions: ChatCardActions(context: context, ref: ref),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingBubble() {
    return const ChatTypingBubble(
      statuses: [
        'Thinking…',
        'Gathering ideas that fit…',
        'Checking the catalogue…',
      ],
    );
  }
}

// ─── History sheet ────────────────────────────────────────────────────────────

class _ChatHistorySheet extends ConsumerWidget {
  const _ChatHistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(chatHistoryProvider);
    final sessions = history.sessions;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
              child: Row(
                children: [
                  Text('Chat history',
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
            ),
            if (sessions.isEmpty)
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: const EmptyState(
                    icon: Icons.forum_outlined,
                    title: 'No saved chats',
                    subtitle:
                        'Start a conversation and it will appear here.',
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                  itemCount: sessions.length,
                  itemBuilder: (_, i) =>
                      _ChatHistoryRow(session: sessions[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatHistoryRow extends ConsumerWidget {
  const _ChatHistoryRow({required this.session});

  final ChatSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            ref.read(chatHistoryProvider.notifier).openSession(session.id);
            Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_outline,
                      size: 18, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${session.messages.length} messages · '
                        '${_relativeTime(session.updatedAt)}',
                        style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete chat',
                  onPressed: () async {
                    final confirmed = await showConfirmDialog(
                      context,
                      title: 'Delete chat?',
                      message:
                          'This removes the saved conversation from this device.',
                      confirmLabel: 'Delete',
                      destructive: true,
                    );
                    if (confirmed) {
                      ref
                          .read(chatHistoryProvider.notifier)
                          .deleteSession(session.id);
                    }
                  },
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    final d = time.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }
}
