import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../models/chat_session.dart';
import '../../../../../../models/product.dart';
import 'robot_avatar.dart';
import 'robot_chat_panel.dart';

/// Draggable floating robot overlay.
///
/// Wraps [child] in a `Stack`: the child stays scrollable underneath while
/// the robot floats above it. Tapping the robot opens the Q&A sheet; a pan
/// repositions it (the arena's ~18px slop is the tap-vs-drag threshold —
/// same recognizer pair as the room-planner's `_FurnitureTile`). Position
/// lives in this State's fields and is clamped to the host box minus
/// [bottomClearance], so the robot can never hide under the floating nav
/// pill or off-screen.
///
/// The Q&A transcript also lives here, so closing and reopening the sheet
/// within a screen visit keeps the conversation — it deliberately never
/// touches the AI tab's saved-chat store.
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

  /// The screen body this robot floats over. Keep it reference-stable:
  /// during a drag only this Stack rebuilds, and the identical-widget fast
  /// path then skips rebuilding the (potentially heavy) scroll view.
  final Widget child;

  /// Catalogue context sent with every question.
  final List<Product> products;

  /// Non-null on the product detail screen — switches the panel to the
  /// single-product framing (title, banner, chips).
  final Product? focusProduct;

  /// Space reserved at the bottom (e.g. `kFloatingNavBarClearance` on the
  /// marketplace, where the shell's `extendBody` lets content run under
  /// the floating nav pill).
  final double bottomClearance;

  final String? title;
  final List<String>? quickQuestions;
  final double robotSize;
  final double edgeMargin;

  @override
  State<RobotAssistantHost> createState() => _RobotAssistantHostState();
}

class _RobotAssistantHostState extends State<RobotAssistantHost> {
  /// Latest known host bounds, refreshed each build — gesture callbacks
  /// between builds clamp against this.
  Size _bounds = Size.zero;

  /// Committed position (`null` until first layout → default anchor).
  Offset? _pos;

  /// Live drag offset; `null` when not dragging.
  Offset? _live;

  /// Q&A transcript for this screen visit — survives sheet reopen.
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

  /// Commit-on-end: same cost model as the planner tile — no per-frame
  /// parent rebuilds with committed state, and a cancelled drag (no
  /// DragEnd) still commits.
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
      // Without this the sheet caps at 9/16 of the screen, which beats
      // the sheet's own height budget.
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

/// Sizes the Q&A sheet from the sheet's OWN MediaQuery (the builder runs
/// once, but this widget's `build` re-registers on every keyboard change):
/// fixed 70% height when the keyboard is closed, shrinking to keep the
/// composer above the keyboard, with the keyboard inset padded so total
/// height never exceeds the viewport.
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
