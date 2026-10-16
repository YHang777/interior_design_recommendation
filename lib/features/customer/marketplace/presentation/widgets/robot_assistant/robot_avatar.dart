import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';

/// Cute theme-colored robot drawn in Flutter (CustomPaint) — no image
/// assets, crisp at any size.
///
/// One controller drives a gentle idle loop: a ±3px vertical bob plus a
/// periodic blink. Animations stop entirely when the OS reports reduced
/// motion ([MediaQuery.disableAnimationsOf]) — the robot stays a static,
/// still-tappable pose.
class RobotAvatar extends StatefulWidget {
  const RobotAvatar({super.key, this.size = 64});

  final double size;

  @override
  State<RobotAvatar> createState() => _RobotAvatarState();
}

class _RobotAvatarState extends State<RobotAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion → hold the static pose. Idempotent, so re-runs on
    // dependency changes are harmless.
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
      _ctrl.value = 0;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final animating = _ctrl.isAnimating;
        final bob = animating ? math.sin(t * 2 * math.pi) * 3.0 : 0.0;
        // Eyes close for the last ~8% of each cycle — a blink that reads
        // as one beat without a second controller.
        final blinking = animating && t > 0.92;
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _RobotPainter(bobOffset: bob, blinking: blinking),
        );
      },
    );
  }
}

class _RobotPainter extends CustomPainter {
  const _RobotPainter({required this.bobOffset, required this.blinking});

  final double bobOffset;
  final bool blinking;

  @override
  void paint(Canvas canvas, Size size) {
    // Design on a 64×64 grid, scaled to the actual size.
    final s = size.width / 64;
    canvas.save();
    canvas.scale(s);

    final accent = AppColors.accent;
    final accentLight = AppColors.accentLight;
    final ink = AppColors.primary;

    // Grounded shadow — stays put while the body bobs, and tightens as
    // the robot rises (reads as lift).
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18 + (bobOffset / 3) * 0.06);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(32, 60),
        width: 30,
        height: 6 + bobOffset * 0.2,
      ),
      shadowPaint,
    );

    canvas.save();
    canvas.translate(0, bobOffset);

    final bodyGradient = LinearGradient(
      colors: [accent, accentLight],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    // Antenna (drawn first so the head tucks its base).
    final antennaPaint = Paint()
      ..color = ink
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(32, 15), const Offset(32, 7), antennaPaint);
    canvas.drawCircle(const Offset(32, 5.5), 3, Paint()..color = accentLight);

    // Arms.
    final armPaint = Paint()..color = accent;
    canvas.drawCircle(const Offset(9, 47), 4.5, armPaint);
    canvas.drawCircle(const Offset(55, 47), 4.5, armPaint);

    // Body with nameplate stripe.
    final bodyRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(13, 38, 38, 20),
      const Radius.circular(10),
    );
    canvas.drawRRect(bodyRect, Paint()..shader = bodyGradient.createShader(bodyRect.outerRect));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(20, 45, 24, 6),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    // Head.
    final headRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(14, 14, 36, 27),
      const Radius.circular(12),
    );
    canvas.drawRRect(headRect, Paint()..shader = bodyGradient.createShader(headRect.outerRect));

    // Face panel.
    final faceRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(18, 17, 28, 21),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      faceRect,
      Paint()..color = Colors.white.withValues(alpha: 0.93),
    );

    // Blush.
    final blush = Paint()..color = accent.withValues(alpha: 0.25);
    canvas.drawCircle(const Offset(22, 32), 2, blush);
    canvas.drawCircle(const Offset(42, 32), 2, blush);

    // Eyes — open circles, or short closed lines while blinking.
    final eyePaint = Paint()..color = ink;
    if (blinking) {
      final eyeLine = Paint()
        ..color = ink
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(24, 25), const Offset(30, 25), eyeLine);
      canvas.drawLine(const Offset(34, 25), const Offset(40, 25), eyeLine);
    } else {
      canvas.drawCircle(const Offset(27, 25), 3, eyePaint);
      canvas.drawCircle(const Offset(37, 25), 3, eyePaint);
    }

    // Smile.
    final smilePaint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      const Rect.fromLTWH(27.5, 27, 9, 8),
      0.15 * math.pi,
      0.7 * math.pi,
      false,
      smilePaint,
    );

    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RobotPainter oldDelegate) =>
      oldDelegate.bobOffset != bobOffset || oldDelegate.blinking != blinking;
}
