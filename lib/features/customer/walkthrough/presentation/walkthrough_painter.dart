import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../models/room_design.dart';
import '../../scanner/data/furniture_catalog.dart';
import '../../scanner/data/room_fit.dart';
import 'walkthrough_controller.dart';

typedef _P3 = ({double x, double y, double z});

typedef _Face = ({
  double depth,
  Path path,
  Paint fill,
  Paint stroke,
  Offset? labelPos,
  String? label,
  Color labelColor,
});

// Street View style standing renderer: the camera is the walker (eye 150 cm,
// yaw = controller heading), so you look at the room from inside it. Only
// this file changes when a real 3D/VR renderer takes over the pose stream.
class WalkthroughPainter extends CustomPainter {
  WalkthroughPainter({required this.controller, this.ghost});

  final WalkthroughController controller;

  /// Settled footprint preview shown while placing — green, drawn over
  /// everything so the drop spot always reads.
  final FurniturePlacement? ghost;

  static const eyeHeight = 150.0;
  static const wallHeight = 250.0;
  static const nearClip = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final ctl = controller;
    // width * 0.7 ≈ 72° horizontal FOV at zoom 1; zoom narrows/widens it.
    final focal = size.width * 0.7 * ctl.zoom;
    final cx = size.width / 2;
    final cy = size.height * 0.42;
    final cosH = cos(ctl.heading);
    final sinH = sin(ctl.heading);

    _P3 toCam(Offset p, double z) {
      final dx = p.dx - ctl.walker.dx;
      final dy = p.dy - ctl.walker.dy;
      return (
        x: -dx * sinH + dy * cosH,
        y: z - eyeHeight,
        z: dx * cosH + dy * sinH,
      );
    }

    Offset? project(_P3 p) {
      if (p.z < nearClip) return null;
      return Offset(cx + p.x / p.z * focal, cy - p.y / p.z * focal);
    }

    // Sutherland–Hodgman against the near plane: walls and boxes that
    // straddle the camera must clip, not explode off-screen.
    List<_P3> clipNear(List<_P3> poly) {
      final out = <_P3>[];
      for (var i = 0; i < poly.length; i++) {
        final cur = poly[i];
        final nxt = poly[(i + 1) % poly.length];
        final curIn = cur.z >= nearClip;
        final nxtIn = nxt.z >= nearClip;
        if (curIn) out.add(cur);
        if (curIn != nxtIn) {
          final t = (nearClip - cur.z) / (nxt.z - cur.z);
          out.add((
            x: cur.x + (nxt.x - cur.x) * t,
            y: cur.y + (nxt.y - cur.y) * t,
            z: nearClip,
          ));
        }
      }
      return out;
    }

    List<_P3> clipSegment(_P3 a, _P3 b) {
      final aIn = a.z >= nearClip;
      final bIn = b.z >= nearClip;
      if (aIn && bIn) return [a, b];
      if (!aIn && !bIn) return const [];
      final t = (nearClip - a.z) / (b.z - a.z);
      final m = (
        x: a.x + (b.x - a.x) * t,
        y: a.y + (b.y - a.y) * t,
        z: nearClip,
      );
      return aIn ? [a, m] : [m, b];
    }

    Path? polyPath(List<_P3> cam) {
      final pts = <Offset>[];
      for (final p in cam) {
        final s = project(p);
        if (s != null) pts.add(s);
      }
      if (pts.length < 3) return null;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final o in pts.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      return path..close();
    }

    void enqueue(
      List<_Face> into,
      List<(Offset, double)> corners, {
      required Color fill,
      required Color stroke,
      double strokeWidth = 1,
      String? label,
      (Offset, double)? labelAnchor,
      Color labelColor = AppColors.textPrimary,
    }) {
      final cam = [for (final c in corners) toCam(c.$1, c.$2)];
      final clipped = clipNear(cam);
      if (clipped.length < 3) return;
      final path = polyPath(clipped);
      if (path == null) return;
      final depth = clipped.fold<double>(0, (s, p) => s + p.z) / clipped.length;
      Offset? labelPos;
      if (label != null && labelAnchor != null) {
        labelPos = project(toCam(labelAnchor.$1, labelAnchor.$2));
      }
      into.add((
        depth: depth,
        path: path,
        fill: Paint()..color = fill,
        stroke: Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
        labelPos: labelPos,
        label: label,
        labelColor: labelColor,
      ));
    }

    void enqueueBox(
      List<_Face> into,
      List<Offset> footprint,
      double h, {
      required Color side,
      required Color top,
      required Color stroke,
      double strokeWidth = 1,
      String? label,
      Color labelColor = AppColors.textPrimary,
    }) {
      for (var i = 0; i < footprint.length; i++) {
        final a = footprint[i];
        final b = footprint[(i + 1) % footprint.length];
        enqueue(into, [(a, 0.0), (b, 0.0), (b, h), (a, h)],
            fill: side, stroke: stroke, strokeWidth: strokeWidth);
      }
      var sumX = 0.0;
      var sumY = 0.0;
      for (final p in footprint) {
        sumX += p.dx;
        sumY += p.dy;
      }
      final center = Offset(sumX / footprint.length, sumY / footprint.length);
      enqueue(
        into,
        [for (final p in footprint) (p, h)],
        fill: top,
        stroke: stroke,
        strokeWidth: strokeWidth,
        label: label,
        labelAnchor: label == null ? null : (center, h + 14),
        labelColor: labelColor,
      );
    }

    // ── Backdrop ──
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEFECE4), Color(0xFFE7E3D9)],
        ).createShader(Offset.zero & size),
    );

    final outline = <Offset>[
      if (ctl.walls.length >= 3)
        ...ctl.walls
      else
        Offset.zero,
      if (ctl.walls.length < 3) ...[
        Offset(ctl.roomW, 0),
        Offset(ctl.roomW, ctl.roomH),
        Offset(0, ctl.roomH),
      ],
    ];

    // ── Floor + grid ──
    final floorPath = polyPath(clipNear([for (final w in outline) toCam(w, 0.0)]));
    if (floorPath != null) {
      canvas.drawPath(floorPath, Paint()..color = const Color(0xFFFFFBF5));
      canvas.save();
      canvas.clipPath(floorPath);
      final minor = Paint()
        ..color = const Color(0xFFE8E4DB)
        ..strokeWidth = 0.6;
      final major = Paint()
        ..color = const Color(0xFFD4CFC4)
        ..strokeWidth = 1;
      void worldLine(Offset a, Offset b, Paint paint) {
        final seg = clipSegment(toCam(a, 0.0), toCam(b, 0.0));
        if (seg.length < 2) return;
        final p1 = project(seg[0]);
        final p2 = project(seg[1]);
        if (p1 == null || p2 == null) return;
        canvas.drawLine(p1, p2, paint);
      }

      for (var x = 0.0; x <= ctl.roomW; x += 50) {
        worldLine(Offset(x, 0), Offset(x, ctl.roomH),
            x % 100 == 0 ? major : minor);
      }
      for (var y = 0.0; y <= ctl.roomH; y += 50) {
        worldLine(Offset(0, y), Offset(ctl.roomW, y),
            y % 100 == 0 ? major : minor);
      }
      canvas.restore();
    }

    // ── Ceiling ──
    final faces = <_Face>[];
    enqueue(
      faces,
      [for (final w in outline) (w, wallHeight)],
      fill: const Color(0xFFF4F1E9),
      stroke: const Color(0xFFE4DFD4),
    );

    // ── Walls (each segment as a quad) ──
    for (var i = 0; i < outline.length; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % outline.length];
      enqueue(
        faces,
        [(a, 0.0), (b, 0.0), (b, wallHeight), (a, wallHeight)],
        fill: const Color(0xFFE9E3D6),
        stroke: const Color(0xFFD6CFC0),
      );
    }

    // ── Furniture as extruded boxes ──
    for (final f in ctl.furniture) {
      final fw = footprintW(f);
      final fh = footprintH(f);
      enqueueBox(
        faces,
        [
          Offset(f.x, f.y),
          Offset(f.x + fw, f.y),
          Offset(f.x + fw, f.y + fh),
          Offset(f.x, f.y + fh),
        ],
        heightCmForFurniture(f.iconName),
        side: AppColors.primary.withValues(alpha: 0.5),
        top: AppColors.primary.withValues(alpha: 0.75),
        stroke: AppColors.primary.withValues(alpha: 0.85),
        strokeWidth: 1.2,
        label: f.name,
      );
    }

    faces.sort((a, b) => b.depth.compareTo(a.depth));
    for (final face in faces) {
      canvas.drawPath(face.path, face.fill);
      canvas.drawPath(face.path, face.stroke);
      _drawLabel(canvas, face, size);
    }

    // ── Ghost last so the drop spot never hides behind a box ──
    final g = ghost;
    if (g != null) {
      final gw = footprintW(g);
      final gh = footprintH(g);
      final ghostFaces = <_Face>[];
      enqueueBox(
        ghostFaces,
        [
          Offset(g.x, g.y),
          Offset(g.x + gw, g.y),
          Offset(g.x + gw, g.y + gh),
          Offset(g.x, g.y + gh),
        ],
        heightCmForFurniture(g.iconName),
        side: AppColors.accent.withValues(alpha: 0.3),
        top: AppColors.accent.withValues(alpha: 0.5),
        stroke: AppColors.accent,
        strokeWidth: 2,
        label: g.name,
        labelColor: AppColors.accentDark,
      );
      ghostFaces.sort((a, b) => b.depth.compareTo(a.depth));
      for (final face in ghostFaces) {
        canvas.drawPath(face.path, face.fill);
        canvas.drawPath(face.path, face.stroke);
        _drawLabel(canvas, face, size);
      }
    }

    _paintCompass(canvas, size, ctl.heading);
  }

  void _drawLabel(Canvas canvas, _Face face, Size size) {
    final at = face.labelPos;
    final text = face.label;
    if (at == null || text == null) return;
    if (at.dx < -80 || at.dx > size.width + 80 || at.dy < -40 || at.dy > size.height + 40) {
      return;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: face.labelColor,
        ),
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 150);
    tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
  }

  // North-up heading dial: needle along the walk direction, so turning in
  // place always shows where "forward" now points.
  void _paintCompass(Canvas canvas, Size size, double heading) {
    final c = Offset(size.width - 34, 90);
    canvas.drawCircle(
        c, 17, Paint()..color = Colors.white.withValues(alpha: 0.92));
    canvas.drawCircle(
      c,
      17,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.border,
    );
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(heading);
    final needle = Path()
      ..moveTo(9, 0)
      ..lineTo(-6, -5.5)
      ..lineTo(-6, 5.5)
      ..close();
    canvas.drawPath(needle, Paint()..color = AppColors.accent);
    canvas.restore();
    canvas.drawCircle(c, 2.5, Paint()..color = AppColors.accentDark);
  }

  @override
  // The screen rebuilds this painter only when the controller notifies (or
  // placement state changes), so any new instance means a real change.
  bool shouldRepaint(covariant WalkthroughPainter oldDelegate) => true;
}
