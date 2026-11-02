import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

enum PlaneQuadKind { floor, wall }

// One plane outline to draw. For a horizontal quad, extentX spans
// the [yaw] direction and extentZ the in-plane perpendicular; for a vertical
// one, extentX is the width along (cos yaw, 0, -sin yaw) and extentZ the
// height along world up ([yaw] is the outward-normal yaw). When [polygon]
// carries ARCore's true outline it wins over the rectangle.
class PlaneQuad {
  const PlaneQuad({
    required this.center,
    required this.yaw,
    required this.extentX,
    required this.extentZ,
    required this.vertical,
    required this.kind,
    this.polygon = const [],
  });

  final Vector3 center;

  final double yaw;

  final double extentX;

  final double extentZ;

  final bool vertical;

  final PlaneQuadKind kind;

  // World-space outline; empty → build the rectangle from center/extents.
  final List<Vector3> polygon;
}

List<Vector3> planeQuadCorners(PlaneQuad quad) {
  if (quad.polygon.length >= 3) return _idealizedPolygon(quad);
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

// ARCore's fitted normal carries a small tilt that barely shows up close but
// grows with distance — the far edge of a floor polygon climbs off the real
// floor ("inclined at the back, floating"). The rectangle path was always
// level; snap true polygons onto the ideal surface the rectangle describes:
// floors to a constant height, walls onto the vertical plane through the
// center with the telemetry yaw. Placement ray tests share this, so a table
// top is probed flat too.
List<Vector3> _idealizedPolygon(PlaneQuad quad) {
  final c = quad.center;
  if (!quad.vertical) {
    return [for (final v in quad.polygon) Vector3(v.x, c.y, v.z)];
  }
  final n = Vector3(math.sin(quad.yaw), 0, math.cos(quad.yaw));
  return [for (final v in quad.polygon) v - n * n.dot(v - c)];
}

// Which overlay zone a telemetry plane belongs to — geometric, not
// class-based: drawing used to require the memory's `floor` class (≥1.0 m),
// so sub-gate floor fragments classified `unknown` were dropped and the
// overlay stayed blank while the scan coach's coverage bar moved. Any
// floor-level horizontal plane is floor zone, any vertical plane is wall
// zone, anything clearly above the floor is a furniture mask. Placement
// gates are untouched — zones say "detected", the reticle says "placeable".
enum OverlayZoneKind { floor, wall, mask, drop }

OverlayZoneKind overlayZoneOf({
  required int planeType,
  required double centerY,
  double? floorY,
  double? cameraY,
}) {
  if (planeType == 2) return OverlayZoneKind.wall;
  if (planeType != 1) return OverlayZoneKind.drop;
  const elevatedGapM = 0.3;
  if (floorY != null) {
    return centerY > floorY + elevatedGapM
        ? OverlayZoneKind.mask
        : OverlayZoneKind.floor;
  }
  // Floor height not established yet — fall back to the same strict
  // below-camera band the scan coach counts as plausible floor, so the
  // overlay and the coach agree on when green may appear.
  if (cameraY != null) {
    final below = cameraY - centerY;
    const plausibleMinM = 0.85;
    const plausibleMaxM = 2.4;
    return below >= plausibleMinM && below <= plausibleMaxM
        ? OverlayZoneKind.floor
        : OverlayZoneKind.mask;
  }
  return OverlayZoneKind.drop;
}

// Per-plane vertex smoothing for the overlay. Round 2 dropped geometry EMA
// to kill pose lag; the pose now rides the same frame as the camera, so the
// only lag left would be on plane outlines themselves — which barely move.
// Raw per-frame ARCore vertices jitter a centimetre or two and read as
// corners/edges floating off the surface. Length changes (ARCore re-fits an
// outline) reset instead of blending mismatched rings.
List<Vector3> emaPolygon(List<Vector3>? prev, List<Vector3> next,
    {double alpha = 0.35}) {
  if (prev == null || prev.length != next.length || next.length < 3) {
    return next;
  }
  return [for (var i = 0; i < next.length; i++) prev[i] * (1 - alpha) + next[i] * alpha];
}

// Telemetry payload → world-space points; anything not a clean xyz triplet
// list collapses to empty so callers fall back to the rectangle.
List<Vector3> polygonFromFlat(List<double> flat) {
  if (flat.length < 9 || flat.length % 3 != 0) return const [];
  return [
    for (var i = 0; i + 2 < flat.length; i += 3)
      Vector3(flat[i], flat[i + 1], flat[i + 2]),
  ];
}

Vector3? _polygonNormal(List<Vector3> pts) {
  for (var i = 1; i + 1 < pts.length; i++) {
    final n = (pts[i] - pts[0]).cross(pts[i + 1] - pts[0]);
    if (n.length2 > 1e-12) return n..normalize();
  }
  return null;
}

bool _pointInPolygon(Vector3 p, List<Vector3> pts, Vector3 normal) {
  // Ray-cast in the plane's own 2D basis.
  final ref = normal.y.abs() < 0.9 ? Vector3(0, 1, 0) : Vector3(0, 0, 1);
  final u = ref.cross(normal)..normalize();
  final v = normal.cross(u);
  final dx = p - pts[0];
  final px = u.dot(dx);
  final py = v.dot(dx);
  var inside = false;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i] - pts[0];
    final b = pts[(i + 1) % pts.length] - pts[0];
    final ax = u.dot(a);
    final ay = v.dot(a);
    final bx = u.dot(b);
    final by = v.dot(b);
    if ((ay > py) != (by > py)) {
      final x = ax + (py - ay) / (by - ay) * (bx - ax);
      if (px < x) inside = !inside;
    }
  }
  return inside;
}

// True when the segment camera→target pierces [quad]'s surface before
// reaching the target — furniture sitting between the camera and the tap.
// The pierce must clear [marginM] short of the target so a tap landing ON
// the surface stays the other gates' business, not this one's.
bool segmentBlockedByQuad({
  required Vector3 origin,
  required Vector3 target,
  required PlaneQuad quad,
  double marginM = 0.12,
}) {
  final points = planeQuadCorners(quad);
  if (points.length < 3) return false;
  final dir = target - origin;
  final dist = dir.length;
  if (dist < 1e-6) return false;
  dir.normalize();
  final normal = _polygonNormal(points);
  if (normal == null) return false;
  final denom = normal.dot(dir);
  if (denom.abs() < 1e-6) return false;
  final t = normal.dot(points[0] - origin) / denom;
  if (t <= 0.02 || t >= dist - marginM) return false;
  return _pointInPolygon(origin + dir * t, points, normal);
}

// One merged path per placement zone, assembled from already-projected
// screen polygons: fragments union into a single zone (uniform tint, no
// double-alpha seams), furniture holes punch out of both zones, and the
// floor never paints over a wall — ARCore's floor polygons creep a few cm
// up the wall base, which is exactly what "detection runs onto the wall"
// looks like. Wall wins the seam: [floor] is clipped by [wall], walls are
// drawn whole (minus holes). Null = nothing to draw for that zone.
class OverlayZones {
  const OverlayZones({this.floor, this.wall});

  final Path? floor;

  final Path? wall;
}

OverlayZones buildOverlayZones({
  required List<List<Offset>> floors,
  required List<List<Offset>> walls,
  required List<List<Offset>> masks,
}) {
  Path? merge(List<List<Offset>> polys) {
    Path? out;
    for (final p in polys) {
      if (p.length < 3) continue;
      final path = Path()..addPolygon(p, true);
      out = out == null ? path : Path.combine(PathOperation.union, out, path);
    }
    return out;
  }

  var floorZone = merge(floors);
  var wallZone = merge(walls);
  final holes = merge(masks);
  if (floorZone != null && wallZone != null) {
    floorZone = Path.combine(PathOperation.difference, floorZone, wallZone);
  }
  if (holes != null) {
    if (floorZone != null) {
      floorZone = Path.combine(PathOperation.difference, floorZone, holes);
    }
    if (wallZone != null) {
      wallZone = Path.combine(PathOperation.difference, wallZone, holes);
    }
  }
  return OverlayZones(floor: floorZone, wall: wallZone);
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
