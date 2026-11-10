import 'package:flutter/material.dart';

import '../../../../../core/utils/boot_trace.dart';
import '../../data/plane_overlay_math.dart';

// Class-colored placement zones projected from the plane memory — true
// ARCore polygons when telemetry supplies them, rectangles otherwise.
// Two unmistakable zones: floor = solid green, wall = blue with diagonal
// hatching (architectural convention), so floor tiles / wall tiles /
// furniture placement reads at a glance. Furniture-classified quads pass in
// as [masks] and are punched out of both zones; the floor is additionally
// clipped by the wall zone so detection can never run up the wall.
// Zone paths are expensive (Skia path booleans over every polygon), so a
// snapshot can hand its cache here: paints of the SAME snapshot at the SAME
// viewport with the SAME viewProjection reuse the Paths instead of
// recomputing them. vp is part of the key — a camera move must reproject
// the world-space quads even when the viewport size is unchanged, or the
// paint freezes on screen and slides with the preview. The cache belongs to
// exactly one snapshot's quad/vp/masks set — never share it across sets.
class OverlayZoneCache {
  Size? size;
  Matrix4? vp;
  Path? floor;
  Path? wall;
}

class PlaneOverlay extends StatelessWidget {
  const PlaneOverlay({
    super.key,
    required this.viewProjection,
    required this.quads,
    this.masks = const [],
    this.zoneCache,
  });

  final Matrix4 viewProjection;

  final List<PlaneQuad> quads;

  final List<PlaneQuad> masks;

  final OverlayZoneCache? zoneCache;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: PlaneOverlayPainter(
            viewProjection, quads, masks, zoneCache),
      ),
    );
  }
}

class PlaneOverlayPainter extends CustomPainter {
  PlaneOverlayPainter(this.viewProjection, this.quads, this.masks,
      [this.zoneCache]);

  final Matrix4 viewProjection;

  final List<PlaneQuad> quads;

  final List<PlaneQuad> masks;

  // Owned by the snapshot; see OverlayZoneCache.
  final OverlayZoneCache? zoneCache;

  // Path-boolean painting over 6 ms eats into the frame budget — log it
  // (once per 2 s across all painter instances) so traces show it.
  static DateTime? _lastSlowPaintAt;

  @override
  void paint(Canvas canvas, Size size) {
    final slowWatch = Stopwatch()..start();
    final cache = zoneCache;
    late final OverlayZones zones;
    if (cache != null &&
        cache.size == size &&
        cache.vp == viewProjection) {
      // Same snapshot, same viewport, same matrices: reuse the Paths.
      zones = OverlayZones(floor: cache.floor, wall: cache.wall);
    } else {
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
      // Boolean cost scales with polygon count — cull off-screen/dust and
      // cap each zone so a long scan can't stall the frame on the union.
      zones = buildOverlayZones(
        floors: boundZonePolys(floors, size, 14),
        walls: boundZonePolys(walls, size, 10),
        masks: boundZonePolys(holes, size, 12),
      );
      if (cache != null) {
        cache
          ..size = size
          ..vp = viewProjection
          ..floor = zones.floor
          ..wall = zones.wall;
      }
    }

    final floorPath = zones.floor;
    if (floorPath != null) {
      canvas.drawPath(
        floorPath,
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0x3D4CAF50),
      );
      // A near-camera floor fills the frame; a heavy outline over a huge
      // path reads as a harsh floating edge. Calm alpha, and skip the
      // stroke entirely when the zone owns most of the viewport.
      final bounds = floorPath.getBounds();
      final dominates = bounds.width > size.width * 0.7 &&
          bounds.height > size.height * 0.7;
      if (!dominates) {
        canvas.drawPath(
          floorPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0x6666BB6A),
        );
      }
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
    final ms = slowWatch.elapsedMilliseconds;
    if (ms >= 6) {
      final now = DateTime.now();
      final last = _lastSlowPaintAt;
      if (last == null || now.difference(last) > const Duration(seconds: 2)) {
        _lastSlowPaintAt = now;
        BootTrace.log('ar-screen: slow paint ${ms}ms '
            'quads=${quads.length} masks=${masks.length}');
      }
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
  bool shouldRepaint(PlaneOverlayPainter oldDelegate) =>
      oldDelegate.viewProjection != viewProjection ||
      oldDelegate.quads != quads ||
      oldDelegate.masks != masks;
}
