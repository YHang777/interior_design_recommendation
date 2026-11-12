import 'dart:math';
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../models/room_design.dart';
import '../../ar/data/glb_generator.dart' show FloorFinishType;
import '../../ar/data/room_finishes.dart' show FinishSelection;
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
  ui.Image? image,
  Rect? dst,
  List<Offset>? tex,
  IconData? icon,
  Color? tint,
});

// Photo asset for a placement: explicit path first, catalog by name second.
String? _spritePathFor(FurniturePlacement f) {
  final explicit = f.imageAsset;
  if (explicit != null && explicit.isNotEmpty) return explicit;
  for (final c in roomCatalog) {
    if (c.iconName == f.iconName) return c.imageAsset;
  }
  return null;
}

int _chan(double v) {
  final r = v.round();
  return r < 0 ? 0 : (r > 255 ? 255 : r);
}

// Scale a colour's channels — k > 1 warms it toward the light, k < 1 is
// the shading/AO falloff.
Color _scale(Color c, double k) => Color.fromRGBO(
      _chan(c.r * 255 * k),
      _chan(c.g * 255 * k),
      _chan(c.b * 255 * k),
      c.a,
    );

// One plan-space light for the whole room: north-west, fixed, so walls,
// the floor pool and furniture shadows all agree.
const _lightPlan = Offset(-0.38, -0.92);

// Street View style standing renderer: the camera is the walker (eye 150 cm,
// yaw = controller heading), so you look at the room from inside it. Only
// this file changes when a real 3D/VR renderer takes over the pose stream.
class WalkthroughPainter extends CustomPainter {
  WalkthroughPainter({
    required this.controller,
    this.ghost,
    this.sprites = const {},
    this.finishes,
  });

  final WalkthroughController controller;

  /// Settled footprint preview shown while placing — green, drawn over
  /// everything so the drop spot always reads.
  final FurniturePlacement? ghost;

  /// imageAsset path → decoded photo, loaded by the screen. Missing entries
  /// fall back to an icon card (or a box when too close to project).
  final Map<String, ui.Image> sprites;

  /// The design's matched finishes (AI material scan / planner). Null keeps
  /// the classic cream look — showroom rooms and pre-finish designs.
  final FinishSelection? finishes;

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
      List<Color>? fillGradient,
      double blur = 0,
      double depthBias = 0,
    }) {
      final cam = [for (final c in corners) toCam(c.$1, c.$2)];
      final clipped = clipNear(cam);
      if (clipped.length < 3) return;
      final path = polyPath(clipped);
      if (path == null) return;
      final depth =
          clipped.fold<double>(0, (s, p) => s + p.z) / clipped.length +
              depthBias;
      Offset? labelPos;
      if (label != null && labelAnchor != null) {
        labelPos = project(toCam(labelAnchor.$1, labelAnchor.$2));
      }
      var fillPaint = Paint()..color = fill;
      if (fillGradient != null && fillGradient.length >= 2) {
        final b = path.getBounds();
        if (b.width >= 1 && b.height >= 1) {
          fillPaint = Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: fillGradient,
            ).createShader(b);
        }
      }
      if (blur > 0) {
        fillPaint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      }
      into.add((
        depth: depth,
        path: path,
        fill: fillPaint,
        stroke: Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
        labelPos: labelPos,
        label: label,
        labelColor: labelColor,
        image: null,
        dst: null,
        tex: null,
        icon: null,
        tint: null,
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

    // One placement → its best drawable: photo floor decal (rug), photo
    // billboard (most pieces), icon card (no photo), box only when too
    // close to project. Ghost style tints everything accent.
    void enqueuePiece(
      List<_Face> into,
      FurniturePlacement f, {
      bool ghostStyle = false,
    }) {
      final fw = footprintW(f);
      final fh = footprintH(f);
      final h = heightCmForFurniture(f.iconName);
      if (h > 8) {
        // Drop shadow on the floor, cast away from _lightPlan; the depth
        // bias keeps it sorted under its own piece but over anything behind.
        final spread = h * 0.3;
        final c = Offset(
          f.x + fw / 2 - _lightPlan.dx * spread,
          f.y + fh / 2 - _lightPlan.dy * spread,
        );
        final hw = fw * 0.55;
        final hh = fh * 0.55;
        enqueue(
          into,
          [
            (Offset(c.dx - hw, c.dy - hh), 0.0),
            (Offset(c.dx + hw, c.dy - hh), 0.0),
            (Offset(c.dx + hw, c.dy + hh), 0.0),
            (Offset(c.dx - hw, c.dy + hh), 0.0),
          ],
          fill: Colors.black.withValues(alpha: ghostStyle ? 0.10 : 0.16),
          stroke: Colors.transparent,
          blur: 8,
          depthBias: fw / 2 + fh / 2 + spread + 2,
        );
      }
      final center = Offset(f.x + fw / 2, f.y + fh / 2);
      final camC = toCam(center, h / 2);
      final imgPath = _spritePathFor(f);
      final img = imgPath == null ? null : sprites[imgPath];
      final labelPos = project(toCam(center, h + 14));
      final labelColor =
          ghostStyle ? AppColors.accentDark : AppColors.textPrimary;
      Paint strokeOf(Color c, double w) => Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = w;
      final clearStroke = Paint()..color = Colors.transparent;

      if (img != null && h <= 8) {
        // Flat piece (rug): texture laid on the floor, needs the whole
        // footprint in front of the near plane or the mapping explodes.
        final corners = [
          Offset(f.x, f.y),
          Offset(f.x + fw, f.y),
          Offset(f.x + fw, f.y + fh),
          Offset(f.x, f.y + fh),
        ];
        final camPts = [for (final c in corners) toCam(c, 0.0)];
        if (camPts.every((p) => p.z >= nearClip)) {
          final proj = [for (final p in camPts) project(p)!];
          final path = polyPath(camPts);
          if (path != null) {
            into.add((
              // +40 bias: floor pieces sort behind standing furniture.
              depth:
                  camPts.fold<double>(0, (s, p) => s + p.z) / camPts.length +
                      40,
              path: path,
              fill: Paint()..color = Colors.transparent,
              stroke: ghostStyle
                  ? strokeOf(AppColors.accent, 2)
                  : clearStroke,
              labelPos: labelPos,
              label: f.name,
              labelColor: labelColor,
              image: img,
              dst: Rect.fromPoints(proj[0], proj[2]),
              tex: proj,
              icon: null,
              tint: ghostStyle ? AppColors.accent : null,
            ));
          }
        }
        return;
      }

      final s = project(camC);
      if (img != null) {
        if (s != null && camC.z >= nearClip * 1.5) {
          final dst = Rect.fromCenter(
            center: s,
            width: fw / camC.z * focal,
            height: h / camC.z * focal,
          );
          into.add((
            depth: camC.z,
            path: Path()..addRect(dst),
            fill: Paint()..color = Colors.transparent,
            stroke: ghostStyle ? strokeOf(AppColors.accent, 2) : clearStroke,
            labelPos: labelPos,
            label: f.name,
            labelColor: labelColor,
            image: img,
            dst: dst,
            tex: null,
            icon: null,
            tint: ghostStyle ? AppColors.accent : null,
          ));
          return;
        }
        // Too close to project as a sprite — geometry below clips correctly.
      } else if (s != null && camC.z >= nearClip * 1.5) {
        final dst = Rect.fromCenter(
          center: s,
          width: fw / camC.z * focal,
          height: h / camC.z * focal,
        );
        into.add((
          depth: camC.z,
          path: Path()..addRect(dst),
          fill: Paint()..color = Colors.white.withValues(alpha: 0.95),
          stroke: ghostStyle
              ? strokeOf(AppColors.accent, 2)
              : strokeOf(AppColors.border, 1.2),
          labelPos: labelPos,
          label: f.name,
          labelColor: labelColor,
          image: null,
          dst: dst,
          tex: null,
          icon: iconForFurniture(f.iconName),
          tint: ghostStyle ? AppColors.accent : null,
        ));
        return;
      }

      enqueueBox(
        into,
        [
          Offset(f.x, f.y),
          Offset(f.x + fw, f.y),
          Offset(f.x + fw, f.y + fh),
          Offset(f.x, f.y + fh),
        ],
        h,
        side: ghostStyle
            ? AppColors.accent.withValues(alpha: 0.3)
            : AppColors.primary.withValues(alpha: 0.5),
        top: ghostStyle
            ? AppColors.accent.withValues(alpha: 0.5)
            : AppColors.primary.withValues(alpha: 0.75),
        stroke: ghostStyle
            ? AppColors.accent
            : AppColors.primary.withValues(alpha: 0.85),
        strokeWidth: ghostStyle ? 2 : 1.2,
        label: f.name,
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
    // Vignette so the space past the outline reads as depth, not paper.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          size.center(Offset.zero),
          size.shortestSide * 0.72,
          [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.16),
          ],
        ),
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

    var sumX = 0.0;
    var sumY = 0.0;
    for (final w in outline) {
      sumX += w.dx;
      sumY += w.dy;
    }
    final centroid = Offset(sumX / outline.length, sumY / outline.length);

    // ── Floor + grid ──
    final floorPath = polyPath(clipNear([for (final w in outline) toCam(w, 0.0)]));
    if (floorPath != null) {
      final floorBase = finishes == null
          ? const Color(0xFFFFFBF5)
          : Color(finishes!.floorColorArgb);
      canvas.drawPath(floorPath, Paint()..color = floorBase);
      canvas.save();
      canvas.clipPath(floorPath);
      // Light pooling under the room centre, drawn before the grid so the
      // metric lines stay crisp on top of it.
      final pool = project(toCam(centroid, 0.0));
      if (pool != null) {
        final r = (size.width * 0.5).clamp(80.0, 400.0).toDouble();
        canvas.drawCircle(
          pool,
          r,
          Paint()
            ..shader = ui.Gradient.radial(
              pool,
              r,
              [
                Colors.white.withValues(alpha: 0.20),
                Colors.transparent,
              ],
            ),
        );
      }
      final minor = Paint()
        ..color = finishes == null
            ? const Color(0xFFE8E4DB)
            : Color.lerp(floorBase, Colors.black, 0.10)!
        ..strokeWidth = 0.6;
      final major = Paint()
        ..color = finishes == null
            ? const Color(0xFFD4CFC4)
            : Color.lerp(floorBase, Colors.black, 0.18)!
        ..strokeWidth = 1;
      void worldLine(Offset a, Offset b, Paint paint) {
        final seg = clipSegment(toCam(a, 0.0), toCam(b, 0.0));
        if (seg.length < 2) return;
        final p1 = project(seg[0]);
        final p2 = project(seg[1]);
        if (p1 == null || p2 == null) return;
        canvas.drawLine(p1, p2, paint);
      }

      final finish = finishes;
      if (finish == null) {
        for (var x = 0.0; x <= ctl.roomW; x += 50) {
          worldLine(Offset(x, 0), Offset(x, ctl.roomH),
              x % 100 == 0 ? major : minor);
        }
        for (var y = 0.0; y <= ctl.roomH; y += 50) {
          worldLine(Offset(0, y), Offset(ctl.roomW, y),
              y % 100 == 0 ? major : minor);
        }
      } else {
        // Finished floors trade the metric grid for their own seams.
        switch (finish.floorType) {
          case FloorFinishType.woodPlanks:
            for (var y = 0.0; y <= ctl.roomH; y += 80) {
              worldLine(Offset(0, y), Offset(ctl.roomW, y), major);
            }
          case FloorFinishType.parquet:
            for (var x = 0.0; x <= ctl.roomW; x += 60) {
              worldLine(Offset(x, 0), Offset(x, ctl.roomH), minor);
            }
            for (var y = 0.0; y <= ctl.roomH; y += 60) {
              worldLine(Offset(0, y), Offset(ctl.roomW, y), minor);
            }
          case FloorFinishType.ceramicTiles:
            for (var x = 0.0; x <= ctl.roomW; x += 100) {
              worldLine(Offset(x, 0), Offset(x, ctl.roomH), major);
            }
            for (var y = 0.0; y <= ctl.roomH; y += 100) {
              worldLine(Offset(0, y), Offset(ctl.roomW, y), major);
            }
          case FloorFinishType.cement:
            break; // polished cement — no seams
        }
      }
      // Contact shadow along the wall line — the inner half of this stroke
      // survives the clip and reads as the dark seam where floor meets wall.
      canvas.drawPath(
        floorPath,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.14)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 30
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.restore();
    }

    // ── Ceiling ──
    final faces = <_Face>[];
    enqueue(
      faces,
      [for (final w in outline) (w, wallHeight)],
      fill: const Color(0xFFF4F1E9),
      stroke: const Color(0xFFE4DFD4),
      fillGradient: const [Color(0xFFF7F4EC), Color(0xFFEDEAE1)],
    );

    // ── Walls (each segment as a quad, lit by orientation + floor AO) ──
    final wallBase = finishes == null
        ? const Color(0xFFE9E3D6)
        : Color(finishes!.wallColorArgb);
    for (var i = 0; i < outline.length; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % outline.length];
      final d = b - a;
      final len = d.distance;
      var nx = 0.0;
      var ny = 0.0;
      if (len > 1e-6) {
        nx = -d.dy / len;
        ny = d.dx / len;
        // Orient the normal into the room so both sides of a seam agree.
        final mx = (a.dx + b.dx) / 2 - centroid.dx;
        final my = (a.dy + b.dy) / 2 - centroid.dy;
        if (nx * mx + ny * my < 0) {
          nx = -nx;
          ny = -ny;
        }
      }
      final shade = (0.94 + 0.10 * (nx * _lightPlan.dx + ny * _lightPlan.dy))
          .clamp(0.8, 1.06)
          .toDouble();
      enqueue(
        faces,
        [(a, 0.0), (b, 0.0), (b, wallHeight), (a, wallHeight)],
        fill: _scale(wallBase, shade),
        stroke: const Color(0xFFD6CFC0),
        // Darker at the floor line: the ambient-occlusion seam every real
        // room shows where the wall meets the ground.
        fillGradient: [
          _scale(wallBase, shade),
          _scale(wallBase, shade * 0.9),
        ],
      );
    }

    // ── Furniture ──
    for (final f in ctl.furniture) {
      enqueuePiece(faces, f);
    }

    faces.sort((a, b) => b.depth.compareTo(a.depth));
    for (final face in faces) {
      _drawFace(canvas, face);
      _drawLabel(canvas, face, size);
    }

    // ── Ghost last so the drop spot never hides behind a piece ──
    final g = ghost;
    if (g != null) {
      final ghostFaces = <_Face>[];
      enqueuePiece(ghostFaces, g, ghostStyle: true);
      ghostFaces.sort((a, b) => b.depth.compareTo(a.depth));
      for (final face in ghostFaces) {
        _drawFace(canvas, face);
        _drawLabel(canvas, face, size);
      }
    }

    _paintCompass(canvas, size, ctl.heading);
  }

  void _drawFace(Canvas canvas, _Face face) {
    final img = face.image;
    final dst = face.dst;
    if (img != null && dst != null) {
      final paint = Paint()..filterQuality = FilterQuality.low;
      final tint = face.tint;
      if (tint != null) {
        paint.colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
      }
      final tex = face.tex;
      if (tex != null && tex.length == 4) {
        // Floor piece: affine-map the photo onto the projected footprint.
        canvas.save();
        canvas.clipPath(face.path);
        final src = Rect.fromLTWH(
            0, 0, img.width.toDouble(), img.height.toDouble());
        final t0 = tex[0];
        final u = tex[1] - t0;
        final v = tex[3] - t0;
        canvas.transform(Float64List.fromList([
          u.dx / src.width, u.dy / src.width, 0, 0,
          v.dx / src.height, v.dy / src.height, 0, 0,
          0, 0, 1, 0,
          t0.dx, t0.dy, 0, 1,
        ]));
        canvas.drawImageRect(img, src, Rect.fromLTWH(0, 0, src.width, src.height), paint);
        canvas.restore();
        canvas.drawPath(face.path, face.stroke);
      } else {
        canvas.drawImageRect(
            img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, paint);
        canvas.drawRect(dst, face.stroke);
      }
      return;
    }
    final icon = face.icon;
    if (icon != null && dst != null) {
      final rrect =
          RRect.fromRectAndRadius(dst, const Radius.circular(10));
      final tint = face.tint;
      canvas.drawRRect(
          rrect,
          Paint()
            ..color = tint != null
                ? tint.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.95));
      canvas.drawRRect(rrect, face.stroke);
      final glyph = (dst.shortestSide * 0.52).clamp(16.0, 96.0).toDouble();
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: glyph,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: tint ?? AppColors.primary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset(dst.center.dx - tp.width / 2, dst.center.dy - tp.height / 2));
      return;
    }
    canvas.drawPath(face.path, face.fill);
    canvas.drawPath(face.path, face.stroke);
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
