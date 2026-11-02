import 'package:flutter/material.dart';

import '../../data/plane_overlay_math.dart';

// Class-colored placement zones projected from the plane memory — true
// ARCore polygons when telemetry supplies them, rectangles otherwise.
// Two unmistakable zones: floor = solid green, wall = blue with diagonal
// hatching (architectural convention), so floor tiles / wall tiles /
// furniture placement reads at a glance. Furniture-classified quads pass in
// as [masks] and are punched out of both zones; the floor is additionally
// clipped by the wall zone so detection can never run up the wall.
class PlaneOverlay extends StatelessWidget {
  const PlaneOverlay({
    super.key,
    required this.viewProjection,
    required this.quads,
    this.masks = const [],
  });

  final Matrix4 viewProjection;

  final List<PlaneQuad> quads;

  final List<PlaneQuad> masks;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _PlaneOverlayPainter(viewProjection, quads, masks),
      ),
    );
  }
}

class _PlaneOverlayPainter extends CustomPainter {
  _PlaneOverlayPainter(this.viewProjection, this.quads, this.masks);

  final Matrix4 viewProjection;

  final List<PlaneQuad> quads;

  final List<PlaneQuad> masks;

  @override
  void paint(Canvas canvas, Size size) {
    final floors = <List<Offset>>[];
    final walls = <List<Offset>>[];
    final holes = <List<Offset>>[];
    for (final quad in quads) {
      final pts = projectPlaneQuad(
        viewProjection: viewProjection,
        quad: quad,
        viewport: size,
      );
      if (pts == null) continue;
      if (quad.kind == PlaneQuadKind.floor) {
        floors.add(pts);
      } else {
        walls.add(pts);
      }
    }
    for (final mask in masks) {
      final pts = projectPlaneQuad(
        viewProjection: viewProjection,
        quad: mask,
        viewport: size,
      );
      if (pts != null) holes.add(pts);
    }
    final zones =
        buildOverlayZones(floors: floors, walls: walls, masks: holes);

    final floorPath = zones.floor;
    if (floorPath != null) {
      canvas.drawPath(
        floorPath,
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0x3D4CAF50),
      );
      canvas.drawPath(
        floorPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xB366BB6A),
      );
    }

    final wallPath = zones.wall;
    if (wallPath != null) {
      canvas.drawPath(
        wallPath,
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0x4D2196F3),
      );
      _drawHatch(canvas, wallPath);
      canvas.drawPath(
        wallPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xCC42A5F5),
      );
    }
  }

  // 45° diagonal lines clipped to the wall outline — walls read as walls
  // even next to the green floor at a glance. Line count is capped so a
  // full-screen wall can't flood the frame with draw calls.
  void _drawHatch(Canvas canvas, Path path) {
    final bounds = path.getBounds();
    if (bounds.width <= 0 || bounds.height <= 0) return;
    const maxLines = 140;
    var step = 14.0;
    final span = bounds.width + bounds.height;
    if (span / step > maxLines) step = span / maxLines;
    final paint = Paint()
      ..color = const Color(0x6642A5F5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.clipPath(path);
    for (var x = bounds.left - bounds.height; x < bounds.left + bounds.width;
        x += step) {
      canvas.drawLine(
        Offset(x, bounds.top),
        Offset(x + bounds.height, bounds.top + bounds.height),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlaneOverlayPainter oldDelegate) =>
      oldDelegate.viewProjection != viewProjection ||
      oldDelegate.quads != quads ||
      oldDelegate.masks != masks;
}
