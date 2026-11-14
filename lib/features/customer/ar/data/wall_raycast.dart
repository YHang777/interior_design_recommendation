import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import 'plane_overlay_math.dart';

// Wall tiles used to need an ARCore vertical-plane hit of ≥0.8×1.5 m, but on
// plain walls ARCore reports only scraps (device round 5: 1.1×0.36 m) while
// the painted wall — cloud fits merged into a RoomWall — is plainly there.
// A tap now also casts against the painted walls the user can see.

({Vector3 origin, Vector3 dir})? screenRay(
    Matrix4 viewProjection, Offset px, Size viewport) {
  if (viewport.width <= 0 || viewport.height <= 0) return null;
  final inv = Matrix4.copy(viewProjection);
  if (inv.invert() == 0) return null;
  final nx = 2 * px.dx / viewport.width - 1;
  final ny = 1 - 2 * px.dy / viewport.height;
  Vector3? unproject(double z) {
    final v = Vector4(nx, ny, z, 1)..applyMatrix4(inv);
    if (v.w.abs() < 1e-12) return null;
    return Vector3(v.x / v.w, v.y / v.w, v.z / v.w);
  }

  final near = unproject(-1);
  final far = unproject(1);
  if (near == null || far == null) return null;
  final d = far - near;
  if (d.length < 1e-9) return null;
  return (origin: near, dir: d.normalized());
}

class WallRayHit {
  const WallRayHit(this.point, this.normal, this.distance, this.wall);

  final Vector3 point;

  // Horizontal, facing back toward the ray origin (the room side).
  final Vector3 normal;
  final double distance;
  final PlaneQuad wall;
}

WallRayHit? raycastWalls({
  required Vector3 origin,
  required Vector3 dir,
  required List<PlaneQuad> walls,
  double edgeMarginM = 0.05,
}) {
  WallRayHit? best;
  for (final w in walls) {
    if (!w.vertical) continue;
    var n = Vector3(math.sin(w.yaw), 0, math.cos(w.yaw));
    final denom = n.dot(dir);
    if (denom.abs() < 1e-6) continue;
    final t = n.dot(w.center - origin) / denom;
    if (t <= 0) continue;
    if (best != null && t >= best.distance) continue;
    final p = origin + dir * t;
    final u = Vector3(math.cos(w.yaw), 0, -math.sin(w.yaw));
    final corners = planeQuadCorners(w);
    if (corners.length < 3) continue;
    final poly = [
      for (final c in corners) Offset((c - w.center).dot(u), c.y),
    ];
    final q = Offset((p - w.center).dot(u), p.y);
    if (!_inside(poly, q) && !_nearEdge(poly, q, edgeMarginM)) continue;
    if (denom > 0) n = -n;
    best = WallRayHit(p, n, t, w);
  }
  return best;
}

bool _inside(List<Offset> poly, Offset p) {
  var c = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i];
    final b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      c = !c;
    }
  }
  return c;
}

bool _nearEdge(List<Offset> poly, Offset p, double m) {
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[j];
    final b = poly[i];
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-12) continue;
    var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    if ((p - (a + ab * t)).distance <= m) return true;
  }
  return false;
}

// Pose in ARCore's vertical-plane convention: local +Y = outward normal
// (what wallAnchorTransform reads), +X along the wall, +Z up.
Matrix4 wallHitPose(WallRayHit h) {
  final y = h.normal;
  final z = Vector3(0, 1, 0);
  final x = y.cross(z).normalized();
  return Matrix4(
    x.x, x.y, x.z, 0,
    y.x, y.y, y.z, 0,
    z.x, z.y, z.z, 0,
    h.point.x, h.point.y, h.point.z, 1,
  );
}
