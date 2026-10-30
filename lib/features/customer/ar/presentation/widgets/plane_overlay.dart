import 'package:flutter/material.dart';

import '../../data/plane_overlay_math.dart';

// Smoothed, class-colored plane quads projected from the plane memory —
// replaces SceneView's raw ARCore polygons so the floor/wall streams render
// as steady rectangles (green floor, blue walls) instead of flickering blobs.
class PlaneOverlay extends StatelessWidget {
  const PlaneOverlay({
    super.key,
    required this.viewProjection,
    required this.quads,
  });

  final Matrix4 viewProjection;

  final List<PlaneQuad> quads;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _PlaneOverlayPainter(viewProjection, quads),
      ),
    );
  }
}

class _PlaneOverlayPainter extends CustomPainter {
  _PlaneOverlayPainter(this.viewProjection, this.quads);

  final Matrix4 viewProjection;

  final List<PlaneQuad> quads;

  @override
  void paint(Canvas canvas, Size size) {
    for (final quad in quads) {
      final pts = projectPlaneQuad(
        viewProjection: viewProjection,
        quad: quad,
        viewport: size,
      );
      if (pts == null) continue;
      final floor = quad.kind == PlaneQuadKind.floor;
      final path = Path()..addPolygon(pts, true);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = floor ? const Color(0x3D4CAF50) : const Color(0x3D2196F3),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = floor ? const Color(0xB366BB6A) : const Color(0xB342A5F5),
      );
    }
  }

  @override
  bool shouldRepaint(_PlaneOverlayPainter oldDelegate) =>
      oldDelegate.viewProjection != viewProjection ||
      oldDelegate.quads != quads;
}
