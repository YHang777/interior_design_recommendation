import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../models/chat_session.dart';
import '../../../../../../models/product.dart';
import 'robot_avatar.dart';
import 'robot_chat_panel.dart';

class RobotAssistantHost extends StatefulWidget {
  const RobotAssistantHost({
    super.key,
    required this.child,
    required this.products,
    this.focusProduct,
    this.bottomClearance = 0,
    this.title,
    this.quickQuestions,
    this.robotSize = 64,
    this.edgeMargin = 12,
  });

  final Widget child;

  final List<Product> products;

  final Product? focusProduct;

  final double bottomClearance;

  final String? title;
  final List<String>? quickQuestions;
  final double robotSize;
  final double edgeMargin;

  @override
  State<RobotAssistantHost> createState() => _RobotAssistantHostState();
}

class _RobotAssistantHostState extends State<RobotAssistantHost> {
  Size _bounds = Size.zero;

  Offset? _pos;

  Offset? _live;

  final List<ChatMessage> _messages = [];

  Offset get _defaultPos => Offset(
        _bounds.width - widget.robotSize - widget.edgeMargin,
        (_bounds.height - widget.bottomClearance - widget.robotSize) * 0.55,
      );

  Offset get _posNow => _live ?? _pos ?? _defaultPos;

  double _clampAxis(double v, double min, double max) =>
      max <= min ? min : v.clamp(min, max).toDouble();

  Offset _clamp(Offset p) => Offset(
        _clampAxis(p.dx, widget.edgeMargin,
            _bounds.width - widget.robotSize - widget.edgeMargin),
        _clampAxis(
            p.dy,
            widget.edgeMargin,
            _bounds.height -
                widget.bottomClearance -
                widget.robotSize -
                widget.edgeMargin),
      );

  void _onPanStart(DragStartDetails _) {
    setState(() => _live = _posNow);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() => _live = _clamp(_posNow + details.delta));
  }

  void _commitDrag() {
    if (_live == null) return;
    setState(() {
      _pos = _clamp(_posNow);
      _live = null;
    });
  }

  Future<void> _openChat() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RobotSheetFrame(
        child: RobotChatPanel(
          title: widget.title ??
              (widget.focusProduct != null
                  ? 'Ask about this product'
                  : 'Shopping assistant'),
          focusProduct: widget.focusProduct,
          products: widget.products,
          quickQuestions: widget.quickQuestions ??
              (widget.focusProduct != null
                  ? kProductDetailQuickQuestions
                  : kMarketplaceQuickQuestions),
          messages: _messages,
          onMessagesChanged: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _bounds = constraints.biggest;
      final p = _clamp(_posNow);
      return Stack(
        children: [
          widget.child,
          Positioned(
            left: p.dx,
            top: p.dy,
            child: RepaintBoundary(
              child: GestureDetector(
                key: const ValueKey('robot-assistant'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openChat(),
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: (_) => _commitDrag(),
                onPanCancel: _commitDrag,
                child: Semantics(
                  button: true,
                  label: 'Shopping assistant, ask about products',
                  child: Tooltip(
                    message: 'Ask about products',
                    child: RobotAvatar(size: widget.robotSize),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _RobotSheetFrame extends StatelessWidget {
  const _RobotSheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final available =
        (mq.size.height - keyboard - 24).clamp(280.0, mq.size.height);
    final height = math.min(mq.size.height * 0.7, available);
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(height: height, child: child),
    );
  }
}
