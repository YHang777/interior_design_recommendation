import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';

class ChatTypingBubble extends StatefulWidget {
  const ChatTypingBubble({
    super.key,
    this.statuses = const ['Thinking…'],
  });

  final List<String> statuses;

  @override
  State<ChatTypingBubble> createState() => _ChatTypingBubbleState();
}

class _ChatTypingBubbleState extends State<ChatTypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.statuses.length > 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
        if (!mounted) return;
        setState(() => _index = (_index + 1) % widget.statuses.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.statuses[_index % widget.statuses.length];
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey('chat-typing'),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _dot(i),
            ],
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                status,
                key: ValueKey(status),
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(int i) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = (_controller.value - i * 0.18 + 1) % 1;
        final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
        final eased = Curves.easeInOut.transform(wave);
        return Container(
          width: 5 + 2 * eased,
          height: 5 + 2 * eased,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.35 + 0.55 * eased),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
