import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

enum PlaneQuadKind { floor, wall }

// One smoothed plane rectangle to draw. For a horizontal quad, extentX spans
// the [yaw] direction and extentZ the in-plane perpendicular; for a vertical
// one, extentX is the width along (cos yaw, 0, -sin yaw) and extentZ the
// height along world up ([yaw] is the outward-normal yaw).
class PlaneQuad {
  const PlaneQuad({
    required this.center,
    required this.yaw,
    required this.extentX,
    required this.extentZ,
    required this.vertical,
    required this.kind,
  });

  final Vector3 center;

  final double yaw;

  final double extentX;

  final double extentZ;

  final bool vertical;

  final PlaneQuadKind kind;
}

List<Vector3> planeQuadCorners(PlaneQuad quad) {
  final c = quad.center;
  final cosY = math.cos(quad.yaw);
  final sinY = math.sin(quad.yaw);
  // Both quads span extentX along a horizontal in-plane axis; extentZ runs
  // along the in-plane perpendicular (horizontal for floors, up for walls).
  final ux = cosY;
  final uz = -sinY;
  final vx = quad.vertical ? 0.0 : sinY;
  final vy = quad.vertical ? 1.0 : 0.0;
  final vz = quad.vertical ? 0.0 : cosY;
  final halfX = quad.extentX / 2;
  final halfZ = quad.extentZ / 2;

  Vector3 corner(double sx, double sz) => Vector3(
        c.x + ux * halfX * sx + vx * halfZ * sz,
        c.y + vy * halfZ * sz,
        c.z + uz * halfX * sx + vz * halfZ * sz,
      );

  return [corner(1, 1), corner(1, -1), corner(-1, -1), corner(-1, 1)];
}

// Projects world points to screen offsets through [viewProjection], clipping
// the polygon at the near plane so quads that stretch past the camera (the
// floor underfoot) still draw. Null when nothing is in front of the camera.
List<Offset>? projectWorldPolygon({
  required Matrix4 viewProjection,
  required List<Vector3> points,
  required Size viewport,
}) {
  if (points.length < 3) return null;
  const wMin = 0.05;
  final clip = <Vector4>[
    for (final p in points)
      Vector4(p.x, p.y, p.z, 1.0)..applyMatrix4(viewProjection),
  ];
  final kept = <Vector4>[];
  for (var i = 0; i < clip.length; i++) {
    final cur = clip[i];
    final nxt = clip[(i + 1) % clip.length];
    final curIn = cur.w >= wMin;
    final nxtIn = nxt.w >= wMin;
    if (curIn) kept.add(cur);
    if (curIn != nxtIn) {
      final t = (wMin - cur.w) / (nxt.w - cur.w);
      kept.add(Vector4(
        cur.x + (nxt.x - cur.x) * t,
        cur.y + (nxt.y - cur.y) * t,
        cur.z + (nxt.z - cur.z) * t,
        wMin,
      ));
    }
  }
  if (kept.length < 3) return null;
  return [
    for (final p in kept)
      Offset(
        (p.x / p.w + 1) / 2 * viewport.width,
        (1 - p.y / p.w) / 2 * viewport.height,
      ),
  ];
}

List<Offset>? projectPlaneQuad({
  required Matrix4 viewProjection,
  required PlaneQuad quad,
  required Size viewport,
}) =>
    projectWorldPolygon(
      viewProjection: viewProjection,
      points: planeQuadCorners(quad),
      viewport: viewport,
    );
