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
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _gemini = AppConfig.geminiApiKey.isNotEmpty
        ? GeminiChatService(apiKey: AppConfig.geminiApiKey)
        : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      Future.microtask(() => _showStyleDialog());
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  static const _styles = [
    ('Modern', Icons.apartment, 'Clean lines, neutral colors, minimal'),
    ('Classic', Icons.chair, 'Elegant, ornate details, timeless'),
    ('Minimalist', Icons.crop_square, 'Simple, uncluttered, functional'),
    ('Bohemian', Icons.palette, 'Colorful, eclectic, free-spirited'),
    ('Scandinavian', Icons.ac_unit, 'Light, cozy, natural materials'),
    ('Industrial', Icons.factory, 'Raw, exposed, urban aesthetic'),
  ];

  static const _rooms = [
    ('Living Room', Icons.weekend),
    ('Bedroom', Icons.bed),
    ('Kitchen', Icons.countertops),
    ('Bathroom', Icons.bathtub),
    ('Dining Room', Icons.table_bar),
    ('Home Office', Icons.computer),
  ];

  void _showStyleDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Choose Your Style',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _styles.length,
            itemBuilder: (_, i) {
              final s = _styles[i];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() => _selectedStyle = s.$1);
                  Navigator.pop(ctx);
                  _showRoomDialog();
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(s.$2, color: AppColors.accent, size: 28),
                      const SizedBox(height: 6),
                      Text(s.$1,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showRoomDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Which Room?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.6,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _rooms.length,
            itemBuilder: (_, i) {
              final r = _rooms[i];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() => _selectedRoom = r.$1);
                  Navigator.pop(ctx);
                  _startChat();
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(r.$2, color: AppColors.accent, size: 28),
                      const SizedBox(height: 6),
                      Text(r.$1,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
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
          if (_selectedStyle != null)
            TextButton.icon(
              onPressed: _showStyleDialog,
              icon: const Icon(Icons.style, color: Colors.white, size: 18),
              label: Text(_selectedStyle!,
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 12)),
            ),
        ],
      ),
      child: Column(
        children: [
          // Chat area
          Expanded(
            child: _msgs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
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
                              size: 40, color: AppColors.accent),
                        ),
                        const SizedBox(height: 16),
                        Text('AI Design Assistant',
                            style: GoogleFonts.poppins(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const SizedBox(height: 8),
                        Text('Select a style to get started',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.7))),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _showStyleDialog,
                          icon: const Icon(Icons.style),
                          label: const Text('Choose Style'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
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

          // Input bar
          if (_selectedStyle != null)
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
