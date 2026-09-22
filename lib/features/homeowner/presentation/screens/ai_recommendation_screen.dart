import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../config/app_config.dart';
import '../../../../../services/gemini_service.dart';
import '../../../../shared/widgets/gradient_scaffold.dart';

class AiRecommendationScreen extends ConsumerStatefulWidget {
  const AiRecommendationScreen({super.key});

  @override
  ConsumerState<AiRecommendationScreen> createState() =>
      _AiRecommendationScreenState();
}

class _AiRecommendationScreenState
    extends ConsumerState<AiRecommendationScreen> {
  final _msgCtrl = TextEditingController();
  final _msgs = <_ChatMsg>[];
  final _scrollCtrl = ScrollController();
  String? _selectedStyle;
  String? _selectedRoom;
  late final GeminiChatService? _gemini;

  @override
  void initState() {
    super.initState();
    _gemini = AppConfig.geminiApiKey.isNotEmpty
        ? GeminiChatService(apiKey: AppConfig.geminiApiKey)
        : null;
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  static const _styles = [
    ('Modern', Icons.apartment),
    ('Classic', Icons.chair),
    ('Minimalist', Icons.crop_square),
    ('Bohemian', Icons.palette),
    ('Scandinavian', Icons.ac_unit),
    ('Industrial', Icons.factory),
  ];

  static const _rooms = [
    ('Living Room', Icons.weekend),
    ('Bedroom', Icons.bed),
    ('Kitchen', Icons.countertops),
    ('Bathroom', Icons.bathtub),
    ('Dining Room', Icons.table_bar),
    ('Home Office', Icons.computer),
  ];

  bool get _readyToChat => _selectedStyle != null && _selectedRoom != null;

  void _selectStyle(String style) {
    setState(() => _selectedStyle = style);
    // If room already selected, start the chat
    if (_selectedRoom != null) _startChat();
  }

  void _selectRoom(String room) {
    setState(() => _selectedRoom = room);
    // If style already selected, start the chat
    if (_selectedStyle != null) _startChat();
  }

  void _startChat() {
    setState(() {
      _msgs.add(_ChatMsg(
        sender: 'AI',
        text:
            'I will recommend $_selectedStyle designs for your $_selectedRoom. Ask me anything!',
      ));
    });
  }

  void _sendMessage() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _msgs.add(_ChatMsg(sender: 'You', text: text));
      _msgs.add(_ChatMsg(sender: 'AI', text: '...'));
    });
    _msgCtrl.clear();

    final gemini = _gemini;
    if (gemini != null && gemini.isConfigured) {
      gemini.sendMessage(text).then((reply) {
        setState(() {
          _msgs.removeLast();
          _msgs.add(_ChatMsg(sender: 'AI', text: reply));
        });
      }).catchError((e) {
        setState(() {
          _msgs.removeLast();
          _msgs.add(_ChatMsg(
              sender: 'AI', text: 'Sorry, something went wrong: $e'));
        });
      });
    } else {
      Future.delayed(const Duration(milliseconds: 600), () {
        setState(() {
          _msgs.removeLast();
          _msgs.add(_ChatMsg(
              sender: 'AI',
              text:
                  'Here is a $_selectedStyle recommendation for your $_selectedRoom: Try a neutral color palette with accent furniture pieces. Would you like specific product suggestions?'));
        });
      });
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: Text(
            _selectedStyle != null
                ? '$_selectedStyle Design'
                : 'AI Recommendations',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        actions: [
          if (_selectedStyle != null && _selectedRoom != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _selectedStyle = null;
                _selectedRoom = null;
                _msgs.clear();
              }),
              icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
              label: Text('Change',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 12)),
            ),
        ],
      ),
      child: Column(
        children: [
          // Inline selection or chat
          Expanded(
            child: _msgs.isEmpty
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
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
                              Text('AI Design Assistant',
                                  style: GoogleFonts.poppins(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary)),
                              const SizedBox(height: 6),
                              Text(
                                  _selectedStyle == null
                                      ? 'Choose your preferred style'
                                      : 'Now pick a room',
                                  style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Step 1: Style selection
                        Text('Design Style',
                            style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1.5,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: _styles.length,
                          itemBuilder: (_, i) {
                            final s = _styles[i];
                            final selected = _selectedStyle == s.$1;
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _selectStyle(s.$1),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.accent.withValues(alpha: 0.1)
                                      : AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.accent
                                        : AppColors.border,
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(s.$2,
                                        color: selected
                                            ? AppColors.accent
                                            : AppColors.textSecondary,
                                        size: 26),
                                    const SizedBox(height: 6),
                                    Text(s.$1,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: selected
                                                ? AppColors.accent
                                                : AppColors.textPrimary)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),

                        // Step 2: Room selection (visible after style chosen)
                        if (_selectedStyle != null) ...[
                          const SizedBox(height: 24),
                          Text('Room Type',
                              style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 12),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 1.8,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: _rooms.length,
                            itemBuilder: (_, i) {
                              final r = _rooms[i];
                              final selected = _selectedRoom == r.$1;
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _selectRoom(r.$1),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.accent.withValues(alpha: 0.1)
                                        : AppColors.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.accent
                                          : AppColors.border,
                                      width: selected ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(r.$2,
                                          color: selected
                                              ? AppColors.accent
                                              : AppColors.textSecondary,
                                          size: 22),
                                      const SizedBox(width: 8),
                                      Text(r.$1,
                                          style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: selected
                                                  ? AppColors.accent
                                                  : AppColors.textPrimary)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) => _buildBubble(_msgs[i]),
                  ),
          ),

          // Input bar (only when chat is active)
          if (_readyToChat)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.background,
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
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12),
                        ),
                        onSubmitted: (_) => _sendMessage(),
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

  Widget _buildBubble(_ChatMsg msg) {
    final isAI = msg.sender == 'AI';
    final isLoading = msg.text == '...';

    return Align(
      alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
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
        child: isLoading
            ? SizedBox(
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
              )
            : Text(msg.text,
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: isAI ? AppColors.textPrimary : Colors.white,
                    height: 1.4)),
      ),
    );
  }
}

class _ChatMsg {
  final String sender;
  final String text;
  _ChatMsg({required this.sender, required this.text});
}
