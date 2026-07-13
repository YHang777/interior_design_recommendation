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
        title: const Text('Choose Your Style'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _styles.map((s) {
              return ListTile(
                leading: Icon(s.$2, color: AppColors.primary),
                title: Text(s.$1,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                subtitle: Text(s.$3,
                    style: GoogleFonts.poppins(fontSize: 12)),
                onTap: () {
                  setState(() => _selectedStyle = s.$1);
                  Navigator.pop(ctx);
                  _showRoomDialog();
                },
              );
            }).toList(),
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
        title: const Text('Which Room?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _rooms.map((r) {
            return ListTile(
              leading: Icon(r.$2, color: AppColors.secondary),
              title: Text(r.$1, style: GoogleFonts.poppins()),
              onTap: () {
                setState(() => _selectedRoom = r.$1);
                Navigator.pop(ctx);
                _startChat();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _startChat() {
    setState(() {
      _msgs.add(_ChatMsg(
        sender: 'AI',
        text: 'I will recommend $_selectedStyle designs for your $_selectedRoom. Ask me anything!',
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

    if (_gemini != null && _gemini!.isConfigured) {
      _gemini!.sendMessage(text).then((reply) {
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
              text: 'Here is a $_selectedStyle recommendation for your $_selectedRoom: Try a neutral color palette with accent furniture pieces. Would you like specific product suggestions?'));
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
            style: GoogleFonts.poppins()),
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
                        const Icon(Icons.psychology,
                            size: 64, color: Colors.white),
                        const SizedBox(height: 16),
                        Text('AI Design Assistant',
                            style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const SizedBox(height: 8),
                        Text('Select a style to get started',
                            style: GoogleFonts.poppins(
                                color: Colors.white.withValues(alpha: 0.8))),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _showStyleDialog,
                          icon: const Icon(Icons.style),
                          label: const Text('Choose Style'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) => _buildBubble(_msgs[i]),
                  ),
          ),

          // Input bar
          if (_selectedStyle != null)
            Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Ask about designs...',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send,
                        color: AppColors.secondary),
                    onPressed: _sendMessage,
                  ),
                ],
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
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isAI ? Colors.brown.shade50 : Colors.brown.shade100,
          borderRadius: BorderRadius.circular(18),
        ),
        child: isLoading
            ? const SizedBox(
                height: 18,
                width: 30,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : Text(msg.text,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.brown.shade900)),
      ),
    );
  }
}

class _ChatMsg {
  final String sender;
  final String text;
  _ChatMsg({required this.sender, required this.text});
}
