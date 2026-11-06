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
//
// floorY only anchors green when [floorYTrusted] — an untrusted estimate
// (loose/table-height lock, no probe) is demoted: the payload's lowest
// horizontal plane inside the strict below-camera band becomes the
// reference, else the per-plane band decides. That is the never-float
// guarantee: a table 0.7 m under a standing phone can never paint green.
enum OverlayZoneKind { floor, wall, mask, drop }

OverlayZoneKind overlayZoneOf({
  required int planeType,
  required double centerY,
  double? floorY,
  double? cameraY,
  double? lowestPlaneY,
  bool floorYTrusted = false,
}) {
  if (planeType == 2) return OverlayZoneKind.wall;
  if (planeType != 1) return OverlayZoneKind.drop;
  const elevatedGapM = 0.3;
  const plausibleMinM = 0.85;
  const plausibleMaxM = 2.4;

  if (floorY != null && floorYTrusted) {
    // A payload plane slightly below the trusted anchor pulls the reference
    // down (the real floor re-appeared under a stale estimate); anything
    // further below is noise the anchor already beat. No live camera-band
    // check — the height was proven when trust was earned (keeps a crouching
    // phone painting a proven floor).
    final ref = (lowestPlaneY != null &&
            lowestPlaneY < floorY &&
            floorY - lowestPlaneY <= 0.5)
        ? lowestPlaneY
        : floorY;
    return centerY > ref + elevatedGapM
        ? OverlayZoneKind.mask
        : OverlayZoneKind.floor;
  }

  // No trusted anchor: never trust floorY alone. The payload's lowest
  // horizontal plane is the floor candidate, but it must sit in the strict
  // below-camera band — and without a camera height nothing may paint.
  final ref = lowestPlaneY;
  if (ref != null) {
    if (cameraY == null) return OverlayZoneKind.drop;
    final below = cameraY - ref;
    if (below < plausibleMinM || below > plausibleMaxM) {
      return OverlayZoneKind.mask;
    }
    return centerY > ref + elevatedGapM
        ? OverlayZoneKind.mask
        : OverlayZoneKind.floor;
  }

  // Nothing corroborates — fall back to the same strict below-camera band
  // the scan coach counts as plausible floor, so the overlay and the coach
  // agree on when green may appear. floorY is deliberately ignored here.
  if (cameraY != null) {
    final below = cameraY - centerY;
    return below >= plausibleMinM && below <= plausibleMaxM
        ? OverlayZoneKind.floor
        : OverlayZoneKind.mask;
  }
  return OverlayZoneKind.drop;
}

// Render-only floor quad at [floorY] under the camera when ARCore has no
// floor-zone plane near that height (probe-corrected floor while the real
// floor was never detected). Placement never sees it — callers keep it out
// of the zone lists they gate on.
PlaneQuad? syntheticFloorQuad({
  required double? floorY,
  required Vector3? cameraPos,
  required List<PlaneQuad> existing,
}) {
  if (floorY == null || cameraPos == null) return null;
  for (final q in existing) {
    if (q.kind == PlaneQuadKind.floor &&
        (q.center.y - floorY).abs() <= 0.15) {
      return null; // ARCore already paints the floor at that height
    }
  }
  return PlaneQuad(
    center: Vector3(cameraPos.x, floorY, cameraPos.z),
    yaw: 0,
    extentX: 3.0,
    extentZ: 3.0,
    vertical: false,
    kind: PlaneQuadKind.floor,
  );
}

// True when the yawed rect samples inside any polygon, comes within
// [clearanceM] of an outline, or a polygon vertex lands inside the rect —
// the cell-blocking test that punches finish tiles around detected objects.
// Rect and polygons must share one coordinate frame.
bool rectHitsPolygons({
  required Vector3 center,
  required double yaw,
  required double widthM,
  required double depthM,
  required List<List<Vector3>> polygons,
  double clearanceM = 0.05,
}) {
  if (polygons.isEmpty || widthM <= 0 || depthM <= 0) return false;
  final samples =
      _orientedRectSamples(center, yaw, widthM, depthM, inflateM: 0);
  final c = math.cos(yaw);
  final s = math.sin(yaw);
  final halfW = widthM / 2 + clearanceM;
  final halfD = depthM / 2 + clearanceM;
  final clearance2 = clearanceM * clearanceM;
  for (final pts in polygons) {
    if (pts.length < 3) continue;
    final n = _polygonNormal(pts);
    if (n == null) continue;
    for (final sample in samples) {
      if (_pointInPolygon(sample, pts, n)) return true;
      final np = _nearestOnOutlineXZ(sample, pts);
      final dx = sample.x - np.x;
      final dz = sample.z - np.z;
      if (dx * dx + dz * dz < clearance2) return true;
    }
    // A small hole fully inside the cell has no sample inside it — catch
    // its own vertices landing in the (clearance-inflated) rect instead.
    for (final v in pts) {
      final dx = v.x - center.x;
      final dz = v.z - center.z;
      final lx = dx * c - dz * s;
      final lz = dx * s + dz * c;
      if (lx.abs() <= halfW && lz.abs() <= halfD) return true;
    }
  }
  return false;
}

// Per-plane vertex smoothing for the overlay. Round 2 dropped geometry EMA
// to kill pose lag; the pose now rides the same frame as the camera, so the
// only lag left would be on plane outlines themselves — which barely move.
// Raw per-frame ARCore vertices jitter a centimetre or two and read as
// corners/edges floating off the surface. Length changes (ARCore re-fits an
// outline) reset instead of blending mismatched rings.
List<Vector3> emaPolygon(List<Vector3>? prev, List<Vector3> next,
    {double alpha = 0.35, double resetShiftM = 0.15}) {
  if (prev == null || prev.length != next.length || next.length < 3) {
    return next;
  }
  // A jump past the reset shift is ARCore re-fitting the outline (or
  // relocalizing), not per-frame jitter — blending would drag the old wrong
  // ring toward the new one for seconds. Snap to the fresh ring so a
  // refocused view shows the correction immediately.
  final resetShift2 = resetShiftM * resetShiftM;
  for (var i = 0; i < next.length; i++) {
    if ((next[i] - prev[i]).length2 > resetShift2) return next;
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

// Nearest point on [pts]'s outline to [p], measured in the XZ plane.
Vector3 _nearestOnOutlineXZ(Vector3 p, List<Vector3> pts) {
  var best = Vector3(p.x, p.y, p.z);
  var bestD2 = double.infinity;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    final abx = b.x - a.x;
    final abz = b.z - a.z;
    final len2 = abx * abx + abz * abz;
    var t = 0.0;
    if (len2 > 1e-12) {
      t = ((p.x - a.x) * abx + (p.z - a.z) * abz) / len2;
      if (t < 0) {
        t = 0;
      } else if (t > 1) {
        t = 1;
      }
    }
    final cx = a.x + abx * t;
    final cz = a.z + abz * t;
    final dx = p.x - cx;
    final dz = p.z - cz;
    final d2 = dx * dx + dz * dz;
    if (d2 < bestD2) {
      bestD2 = d2;
      best = Vector3(cx, p.y, cz);
    }
  }
  return best;
}

Vector3 _polygonCentroidXZ(List<Vector3> pts) {
  var x = 0.0;
  var z = 0.0;
  for (final p in pts) {
    x += p.x;
    z += p.z;
  }
  return Vector3(x / pts.length, pts.first.y, z / pts.length);
}

// A tap grazing a detected object lands the item hugging the object's edge —
// it reads as floating on the object. Slide the point horizontally away from
// the nearest mask edge to exactly [clearanceM] (a tap inside the mask's
// outline slides out past it by [clearanceM]), keeping it inside a floor-zone
// quad, clear of every mask from [cameraPos], and inside the placement
// distance window. When the item's half extents and yaw are passed, the
// clearance is measured from the item's BODY (its support extent along the
// push direction), so a wide sofa slides far enough that its edge — not just
// its center — clears the object. Returns [point] unchanged when there is
// nothing to push away from or no valid landing exists — never worse than
// the raw tap.
Vector3 pushIntoFloorZone({
  required Vector3 point,
  required List<PlaneQuad> masks,
  required List<PlaneQuad> floorZones,
  required Vector3 cameraPos,
  double clearanceM = 0.3,
  double minDistanceM = 0.25,
  double maxDistanceM = 4.0,
  double? halfWidthM,
  double? halfDepthM,
  double? footprintYaw,
}) {
  if (masks.isEmpty || floorZones.isEmpty) return point;

  Vector3? nearest;
  var nearestD2 = double.infinity;
  for (final m in masks) {
    final pts = planeQuadCorners(m);
    if (pts.length < 3) continue;
    final np = _nearestOnOutlineXZ(point, pts);
    final dx = point.x - np.x;
    final dz = point.z - np.z;
    final d2 = dx * dx + dz * dz;
    if (d2 < nearestD2) {
      nearestD2 = d2;
      nearest = np;
    }
  }
  if (nearest == null) return point;

  var insideAny = false;
  for (final m in masks) {
    final pts = planeQuadCorners(m);
    if (pts.length < 3) continue;
    final n = _polygonNormal(pts);
    if (n != null && _pointInPolygon(point, pts, n)) {
      insideAny = true;
      break;
    }
  }

  // Outside: away from the nearest edge. Inside: out through the nearest
  // edge and beyond it by the clearance. Degenerate (on the outline, or a
  // point at the mask's center): radial from the mask center, then away
  // from the camera.
  var dirX = insideAny ? nearest.x - point.x : point.x - nearest.x;
  var dirZ = insideAny ? nearest.z - point.z : point.z - nearest.z;
  var len = math.sqrt(dirX * dirX + dirZ * dirZ);
  if (len < 1e-6) {
    Vector3? centerOf;
    for (final m in masks) {
      final pts = planeQuadCorners(m);
      if (pts.length < 3) continue;
      final n = _polygonNormal(pts);
      if (n != null && _pointInPolygon(point, pts, n)) {
        centerOf = _polygonCentroidXZ(pts);
        break;
      }
    }
    if (centerOf != null) {
      dirX = point.x - centerOf.x;
      dirZ = point.z - centerOf.z;
      len = math.sqrt(dirX * dirX + dirZ * dirZ);
    }
    if (len < 1e-6) {
      dirX = point.x - cameraPos.x;
      dirZ = point.z - cameraPos.z;
      len = math.sqrt(dirX * dirX + dirZ * dirZ);
      if (len < 1e-6) return point;
    }
  }

  // How far the item's BODY must stay from the outline along the push
  // direction: half the rect's support in that direction plus clearance.
  var need = clearanceM;
  final hasFootprint =
      halfWidthM != null && halfDepthM != null && footprintYaw != null;
  if (hasFootprint) {
    final ux = dirX / len;
    final uz = dirZ / len;
    final c = math.cos(footprintYaw);
    final s = math.sin(footprintYaw);
    // Local axes match FinishFootprint: +X = (cos, −sin), +Z = (sin, cos).
    final uDotAx = ux * c + uz * -s;
    final uDotAz = ux * s + uz * c;
    need = halfWidthM.abs() * uDotAx.abs() +
        halfDepthM.abs() * uDotAz.abs() +
        clearanceM;
  }
  if (!insideAny && nearestD2 >= need * need) return point;

  final dist = math.sqrt(nearestD2);
  final push = insideAny ? dist + need : need - dist;
  final candidate = Vector3(
    point.x + dirX / len * push,
    point.y,
    point.z + dirZ / len * push,
  );

  // Validate the landing: open floor under it, still clear of every mask,
  // unblocked from the camera, inside the distance window.
  if (hasFootprint) {
    if (!footprintFitsInZones(
      center: candidate,
      yaw: footprintYaw,
      widthM: halfWidthM * 2,
      depthM: halfDepthM * 2,
      floorZones: floorZones,
      masks: masks,
      maskClearanceM: clearanceM - 0.01,
    )) {
      return point;
    }
  } else {
    var onFloor = false;
    for (final zone in floorZones) {
      final pts = planeQuadCorners(zone);
      if (pts.length < 3) continue;
      final n = _polygonNormal(pts);
      if (n != null && _pointInPolygon(candidate, pts, n)) {
        onFloor = true;
        break;
      }
    }
    if (!onFloor) return point;
    for (final m in masks) {
      final pts = planeQuadCorners(m);
      if (pts.length < 3) continue;
      final n = _polygonNormal(pts);
      if (n != null && _pointInPolygon(candidate, pts, n)) return point;
      final np = _nearestOnOutlineXZ(candidate, pts);
      final dx = candidate.x - np.x;
      final dz = candidate.z - np.z;
      if (math.sqrt(dx * dx + dz * dz) < clearanceM - 0.01) return point;
    }
  }
  for (final m in masks) {
    if (segmentBlockedByQuad(origin: cameraPos, target: candidate, quad: m)) {
      return point;
    }
  }
  final camDist = (candidate - cameraPos).length;
  if (camDist < minDistanceM || camDist > maxDistanceM) return point;
  return candidate;
}

// Oriented-rectangle fit: the item's footprint (width × depth at [yaw],
// centered at [center] in XZ) must sit entirely on open floor — every sample
// inside at least one floor-zone polygon (union) and clear of every mask.
// Sample points (corners, edge midpoints, center) instead of exact polygon
// clipping: zones are unions of quads, and the sample union matches what
// pushIntoFloorZone already validates against. The floor check uses a rect
// deflated by [floorMarginM] so a footprint flush against a zone edge still
// passes; the mask check uses the full rect with [maskClearanceM] to keep
// the body off detected objects. Empty [floorZones] fails open — nothing
// there says the spot is bad.
bool footprintFitsInZones({
  required Vector3 center,
  required double yaw,
  required double widthM,
  required double depthM,
  required List<PlaneQuad> floorZones,
  List<PlaneQuad> masks = const [],
  double floorMarginM = 0.04,
  double maskClearanceM = 0.05,
}) {
  if (widthM <= 0 || depthM <= 0) return true;
  if (floorZones.isEmpty) return true;
  final full = _orientedRectSamples(center, yaw, widthM, depthM, inflateM: 0);
  final shrinkOk = floorMarginM * 2 < widthM && floorMarginM * 2 < depthM;
  final inset = shrinkOk
      ? _orientedRectSamples(center, yaw, widthM, depthM,
          inflateM: -floorMarginM)
      : full;
  for (final s in inset) {
    var onFloor = false;
    for (final zone in floorZones) {
      final pts = planeQuadCorners(zone);
      if (pts.length < 3) continue;
      final n = _polygonNormal(pts);
      if (n != null && _pointInPolygon(s, pts, n)) {
        onFloor = true;
        break;
      }
    }
    if (!onFloor) return false;
  }
  for (final m in masks) {
    final pts = planeQuadCorners(m);
    if (pts.length < 3) continue;
    final n = _polygonNormal(pts);
    if (n == null) continue;
    for (final s in full) {
      if (_pointInPolygon(s, pts, n)) return false;
      final np = _nearestOnOutlineXZ(s, pts);
      final dx = s.x - np.x;
      final dz = s.z - np.z;
      if (math.sqrt(dx * dx + dz * dz) < maskClearanceM) return false;
    }
  }
  return true;
}

// Nine sample points of the oriented rect: four corners, four edge
// midpoints, and the center. [inflateM] grows (positive) or shrinks
// (negative) the rect on both axes.
List<Vector3> _orientedRectSamples(
  Vector3 center,
  double yaw,
  double widthM,
  double depthM, {
  required double inflateM,
}) {
  final halfW = widthM / 2 + inflateM;
  final halfD = depthM / 2 + inflateM;
  if (halfW <= 0 || halfD <= 0) {
    return [Vector3(center.x, center.y, center.z)];
  }
  final axX = math.cos(yaw);
  final axZ = -math.sin(yaw);
  final azX = math.sin(yaw);
  final azZ = math.cos(yaw);
  Vector3 at(double sx, double sz) => Vector3(
        center.x + axX * halfW * sx + azX * halfD * sz,
        center.y,
        center.z + axZ * halfW * sx + azZ * halfD * sz,
      );
  return [
    at(1, 1),
    at(1, -1),
    at(-1, -1),
    at(-1, 1),
    at(0, 1),
    at(0, -1),
    at(1, 0),
    at(-1, 0),
    at(0, 0),
  ];
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
