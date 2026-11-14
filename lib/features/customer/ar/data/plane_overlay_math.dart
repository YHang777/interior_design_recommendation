import 'dart:math' as math;
import 'dart:ui';

import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:vector_math/vector_math_64.dart';

import 'placement_policy.dart';

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
    // Also shrink the ring slightly: ARCore outlines creep a few cm past
    // the physical floor edge (baseboard junction), and painted overlay has
    // no depth to hide behind the wall. A small centroid pull guarantees the
    // drawn shape never reaches past the raw outline it came from.
    const insetM = 0.04;
    var cx = 0.0;
    var cz = 0.0;
    for (final v in quad.polygon) {
      cx += v.x;
      cz += v.z;
    }
    cx /= quad.polygon.length;
    cz /= quad.polygon.length;
    return [
      for (final v in quad.polygon)
        () {
          final dx = v.x - cx;
          final dz = v.z - cz;
          final d = math.sqrt(dx * dx + dz * dz);
          final k = d <= insetM ? 0.0 : (d - insetM) / d;
          return Vector3(cx + dx * k, c.y, cz + dz * k);
        }(),
    ];
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

// The height floor paint is flattened onto: the trusted anchor, pulled down
// to a slightly lower payload plane (the real floor re-appearing under a
// stale estimate). Shared by zone classification and quad building so paint
// and gates can never disagree about where the floor is. When the cloud
// freshly corroborates floorY, a plane below it is stray (reflection
// ghost) and may not pull the height down — that pull masked the real
// floor planes on device.
double trustedOverlayRefY({
  required double floorY,
  double? lowestPlaneY,
  bool corroborateFloorY = false,
}) {
  if (corroborateFloorY) return floorY;
  return (lowestPlaneY != null &&
          lowestPlaneY < floorY &&
          floorY - lowestPlaneY <= 0.5)
      ? lowestPlaneY
      : floorY;
}

// Payload-lowest horizontal plane — the untrusted-floorY reference. A plane
// more than [maxBelowCameraM] under the phone is another storey (a courtyard
// over a balcony railing, a stairwell) and can never be the floor being
// stood on; letting it anchor turned every real floor plane into a mask.
// Subsumed planes are mask material, and a held plane far below the
// remembered floor is a stale ghost.
double? overlayLowestPlaneY({
  required List<ARPlaneInfo> planes,
  required Set<int> liveIds,
  double? floorY,
  double? cameraY,
  double maxBelowCameraM = 2.4,
}) {
  double? lowest;
  for (final p in planes) {
    if (p.planeType != 1 || p.subsumed || !p.centerY.isFinite) continue;
    if (cameraY != null && cameraY - p.centerY > maxBelowCameraM) continue;
    if (!liveIds.contains(p.id) &&
        floorY != null &&
        p.centerY < floorY - 0.5) {
      continue;
    }
    if (lowest == null || p.centerY < lowest) lowest = p.centerY;
  }
  return lowest;
}

const double minWallTopAboveFloorM = 1.4;
const double typicalPhoneHeightM = 1.4;

OverlayZoneKind overlayZoneOf({
  required int planeType,
  required double centerY,
  double? floorY,
  double? cameraY,
  double? lowestPlaneY,
  bool floorYTrusted = false,
  bool corroborateFloorY = false,
  bool floorYCameraBacked = true,
  double extentX = 0,
  double extentZ = 0,
}) {
  if (planeType == 2) {
    // A vertical plane only paints as wall once it is wall-sized — a
    // cabinet/shelf side with altitude is an object, not a wall. Defaults
    // fail closed so a caller that forgets extents drops instead of
    // painting wrongly.
    if (!ArPlacementPolicy.wallAreaQualifies(extentX, extentZ)) {
      return OverlayZoneKind.drop;
    }
    // Furniture sides (bed, nightstand, sofa back) are vertical too but
    // stop well below head height — device logs: walls top out at +1.7–2.1
    // m above the floor, furniture at +0.5–1.3 m. Low verticals are
    // objects: punched out, never painted as wall.
    final ref = floorY ?? (cameraY != null ? cameraY - typicalPhoneHeightM : null);
    if (ref != null && centerY + extentZ / 2 < ref + minWallTopAboveFloorM) {
      return OverlayZoneKind.mask;
    }
    return OverlayZoneKind.wall;
  }
  if (planeType != 1) return OverlayZoneKind.drop;
  // Above the reference = an object top (furniture mask); below = a lower
  // level that must never paint (flattening it up would float phantom
  // floor over a stairwell). Symmetric band around the proven height.
  const elevatedGapM = 0.2;
  const plausibleMinM = 0.85;
  const plausibleMaxM = 2.4;

  if (floorY != null && floorYTrusted) {
    // No live camera-band check — the height was proven when trust was
    // earned (keeps a crouching phone painting a proven floor).
    final ref = trustedOverlayRefY(
      floorY: floorY,
      lowestPlaneY: lowestPlaneY,
      corroborateFloorY: corroborateFloorY,
    );
    if (centerY > ref + elevatedGapM) return OverlayZoneKind.mask;
    if (centerY < ref - elevatedGapM) return OverlayZoneKind.drop;
    return OverlayZoneKind.floor;
  }

  // No trusted anchor: never trust floorY alone. The payload's lowest
  // horizontal plane is the floor candidate, but it must sit in the strict
  // below-camera band — and without a camera height nothing may paint.
  final ref = lowestPlaneY;
  if (ref != null) {
    // Elevated shapes stay masks even when the camera height is stale —
    // dropping them is how furniture ended up painted over.
    if (centerY > ref + elevatedGapM) return OverlayZoneKind.mask;
    // No camera height: a plane at floor level still paints (the memory
    // already remembers this floor); anything else drops.
    if (cameraY == null) {
      return (floorY != null &&
              floorYCameraBacked &&
              (centerY - floorY).abs() <= 0.3)
          ? OverlayZoneKind.floor
          : OverlayZoneKind.drop;
    }
    final below = cameraY - ref;
    if (below < plausibleMinM || below > plausibleMaxM) {
      return OverlayZoneKind.mask;
    }
    return centerY < ref - elevatedGapM
        ? OverlayZoneKind.drop
        : OverlayZoneKind.floor;
  }

  // Nothing corroborates — fall back to the same strict below-camera band
  // the scan coach counts as plausible floor, so the overlay and the coach
  // agree on when green may appear. floorY is deliberately ignored here.
  if (cameraY != null) {
    final below = cameraY - centerY;
    if (below > plausibleMaxM) return OverlayZoneKind.drop;
    return below >= plausibleMinM
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
    extentX: 2.0,
    extentZ: 2.0,
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
    {double alpha = 0.35, double resetShiftM = 0.08}) {
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

// Inside any zone, or within [gapM] of an outline — adjacent ARCore floor
// fragments rarely abut, and a footprint sample landing in the 5–10 cm
// seam between two real floor pieces must not fail placement ("too much
// fragment, can't place").
bool _pointOnZones(Vector3 p, List<PlaneQuad> zones, {double gapM = 0.06}) {
  var best2 = double.infinity;
  for (final zone in zones) {
    final pts = planeQuadCorners(zone);
    if (pts.length < 3) continue;
    final n = _polygonNormal(pts);
    if (n != null && _pointInPolygon(p, pts, n)) return true;
    final np = _nearestOnOutlineXZ(p, pts);
    final dx = p.x - np.x;
    final dz = p.z - np.z;
    final d2 = dx * dx + dz * dz;
    if (d2 < best2) best2 = d2;
  }
  return best2 <= gapM * gapM;
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
// its center — clears the object. [walls] add the second stage: a body
// straddling a wall-kind quad's plane slides onto the tap's own side of it
// (flush wall hugging is never pushed). Returns [point] unchanged when there
// is nothing to push away from or no valid landing exists — never worse than
// the raw tap.
Vector3 pushIntoFloorZone({
  required Vector3 point,
  required List<PlaneQuad> masks,
  required List<PlaneQuad> floorZones,
  required Vector3 cameraPos,
  List<PlaneQuad> walls = const [],
  double clearanceM = 0.3,
  double minDistanceM = 0.25,
  double maxDistanceM = 4.0,
  double? halfWidthM,
  double? halfDepthM,
  double? footprintYaw,
}) {
  if (floorZones.isEmpty) return point;
  var landing = point;
  if (masks.isNotEmpty) {
    landing = _pushOffMasks(
      point: landing,
      masks: masks,
      floorZones: floorZones,
      walls: walls,
      cameraPos: cameraPos,
      clearanceM: clearanceM,
      minDistanceM: minDistanceM,
      maxDistanceM: maxDistanceM,
      halfWidthM: halfWidthM,
      halfDepthM: halfDepthM,
      footprintYaw: footprintYaw,
    );
  }
  if (walls.isNotEmpty) {
    landing = _pushOffWalls(
      point: landing,
      masks: masks,
      floorZones: floorZones,
      walls: walls,
      cameraPos: cameraPos,
      clearanceM: clearanceM,
      minDistanceM: minDistanceM,
      maxDistanceM: maxDistanceM,
      halfWidthM: halfWidthM,
      halfDepthM: halfDepthM,
      footprintYaw: footprintYaw,
    );
  }
  return landing;
}

// The mask half of the push — see pushIntoFloorZone.
Vector3 _pushOffMasks({
  required Vector3 point,
  required List<PlaneQuad> masks,
  required List<PlaneQuad> floorZones,
  required Vector3 cameraPos,
  List<PlaneQuad> walls = const [],
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
      walls: walls,
      maskClearanceM: clearanceM - 0.01,
    )) {
      return point;
    }
  } else {
    if (!_pointOnZones(candidate, floorZones)) return point;
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

// The wall half of the push — see pushIntoFloorZone. A body straddling a
// wall-kind quad's plane ("my model is stuck in the wall plane") slides
// onto the tap's own side of the plane: the side the seed point is on,
// far enough that no corner is left inside the plane band. A body whose
// footprint is unknown only moves when its tap lands ON the plane — a tap
// near a wall is hugging, and hugging is legal. Falls back to the raw tap
// when the slid landing cannot pass the same validation as the mask push.
Vector3 _pushOffWalls({
  required Vector3 point,
  required List<PlaneQuad> masks,
  required List<PlaneQuad> floorZones,
  required List<PlaneQuad> walls,
  required Vector3 cameraPos,
  double clearanceM = 0.3,
  double minDistanceM = 0.25,
  double maxDistanceM = 4.0,
  double? halfWidthM,
  double? halfDepthM,
  double? footprintYaw,
}) {
  final hasFootprint =
      halfWidthM != null && halfDepthM != null && footprintYaw != null;
  final corners = hasFootprint
      ? _rectCornersXZ(point, footprintYaw, halfWidthM * 2, halfDepthM * 2)
      : [Vector3(point.x, point.y, point.z)];
  PlaneQuad? worst;
  var worstPush = 0.0;
  var worstSide = 1.0;
  for (final w in walls) {
    final range = _wallBodyRange(w, corners, point.y);
    if (range == null) continue;
    final collides = hasFootprint
        ? (range.minD < -straddleTolM && range.maxD > straddleTolM)
        : (range.minD > -straddleTolM && range.maxD < straddleTolM);
    if (!collides) continue;
    final nx = math.sin(w.yaw);
    final nz = math.cos(w.yaw);
    final side =
        (point.x - w.center.x) * nx + (point.z - w.center.z) * nz >= 0
            ? 1.0
            : -1.0;
    final push = side > 0 ? straddleTolM - range.minD : range.maxD + straddleTolM;
    if (push > worstPush) {
      worstPush = push;
      worst = w;
      worstSide = side;
    }
  }
  if (worst == null) return point;
  final candidate = Vector3(
    point.x + math.sin(worst.yaw) * worstSide * worstPush,
    point.y,
    point.z + math.cos(worst.yaw) * worstSide * worstPush,
  );
  if (hasFootprint) {
    if (!footprintFitsInZones(
      center: candidate,
      yaw: footprintYaw,
      widthM: halfWidthM * 2,
      depthM: halfDepthM * 2,
      floorZones: floorZones,
      masks: masks,
      walls: walls,
      maskClearanceM: clearanceM - 0.01,
    )) {
      return point;
    }
  } else {
    if (!_pointOnZones(candidate, floorZones)) return point;
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

// Straddle-only wall gate. A footprint that crosses a wall-kind quad's
// plane is stuck inside it the moment it lands — the misdetected-furniture
// case: the gap under the furniture reads as placeable floor and the model
// wedges into the face plane. Flush wall hugging is legal on purpose: a
// body entirely one side of the plane (touching within [straddleTolM])
// never bounces off a real wall. Quads whose base floats above the body's
// reach ([straddleBodyHeightM]) cannot collide and are ignored, and a
// crossing just past a fragment's detected end still counts
// ([straddleEndMarginM]) — ARCore stops where scanning stopped, not where
// the physical wall ends.
const straddleTolM = 0.02;
const straddleBodyHeightM = 1.8;
const straddleEndMarginM = 0.1;

List<Vector3> _rectCornersXZ(
    Vector3 center, double yaw, double widthM, double depthM) {
  final c = math.cos(yaw);
  final s = math.sin(yaw);
  final halfW = widthM / 2;
  final halfD = depthM / 2;
  Vector3 at(double sx, double sz) => Vector3(
        center.x + c * halfW * sx + s * halfD * sz,
        center.y,
        center.z + -s * halfW * sx + c * halfD * sz,
      );
  return [at(1, 1), at(1, -1), at(-1, -1), at(-1, 1)];
}

// Signed corner distances across [wall]'s vertical plane when the body can
// collide with it at all (vertical, within vertical reach, crossing the
// wall's run); null when the wall is irrelevant to this body.
({double minD, double maxD})? _wallBodyRange(
    PlaneQuad wall, List<Vector3> corners, double bodyAtY) {
  if (!wall.vertical) return null;
  final pts = planeQuadCorners(wall);
  if (pts.length < 3) return null;
  final ux = math.cos(wall.yaw);
  final uz = -math.sin(wall.yaw);
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  var minAlong = double.infinity;
  var maxAlong = double.negativeInfinity;
  for (final v in pts) {
    if (v.y < minY) minY = v.y;
    if (v.y > maxY) maxY = v.y;
    final along = (v.x - wall.center.x) * ux + (v.z - wall.center.z) * uz;
    if (along < minAlong) minAlong = along;
    if (along > maxAlong) maxAlong = along;
  }
  if (!minY.isFinite || !maxY.isFinite) return null;
  if (maxY < bodyAtY || minY > bodyAtY + straddleBodyHeightM) return null;
  final nx = math.sin(wall.yaw);
  final nz = math.cos(wall.yaw);
  var minD = double.infinity;
  var maxD = double.negativeInfinity;
  var cMin = double.infinity;
  var cMax = double.negativeInfinity;
  for (final c in corners) {
    final d = (c.x - wall.center.x) * nx + (c.z - wall.center.z) * nz;
    if (d < minD) minD = d;
    if (d > maxD) maxD = d;
    final along = (c.x - wall.center.x) * ux + (c.z - wall.center.z) * uz;
    if (along < cMin) cMin = along;
    if (along > cMax) cMax = along;
  }
  if (cMax < minAlong - straddleEndMarginM ||
      cMin > maxAlong + straddleEndMarginM) {
    return null;
  }
  return (minD: minD, maxD: maxD);
}

bool footprintStraddlesWall({
  required Vector3 center,
  required double yaw,
  required double widthM,
  required double depthM,
  required List<PlaneQuad> walls,
}) {
  if (walls.isEmpty || widthM <= 0 || depthM <= 0) return false;
  final corners = _rectCornersXZ(center, yaw, widthM, depthM);
  for (final w in walls) {
    final range = _wallBodyRange(w, corners, center.y);
    if (range == null) continue;
    if (range.minD < -straddleTolM && range.maxD > straddleTolM) return true;
  }
  return false;
}

// Oriented-rectangle fit: the item's footprint (width × depth at [yaw],
// centered at [center] in XZ) must sit entirely on open floor — every sample
// inside at least one floor-zone polygon (union) and clear of every mask.
// Sample points (corners, edge midpoints, center) instead of exact polygon
// clipping: zones are unions of quads, and the sample union matches what
// pushIntoFloorZone already validates against. The floor check uses a rect
// deflated by [floorMarginM] so a footprint flush against a zone edge still
// passes; the mask check uses the full rect with [maskClearanceM] to keep
// the body off detected objects. [walls] add the straddle gate — see
// footprintStraddlesWall. Empty [floorZones] fails open — nothing there
// says the spot is bad.
bool footprintFitsInZones({
  required Vector3 center,
  required double yaw,
  required double widthM,
  required double depthM,
  required List<PlaneQuad> floorZones,
  List<PlaneQuad> masks = const [],
  List<PlaneQuad> walls = const [],
  double floorMarginM = 0.04,
  double maskClearanceM = 0.05,
}) {
  if (widthM <= 0 || depthM <= 0) return true;
  if (floorZones.isEmpty && walls.isEmpty) return true;
  if (floorZones.isNotEmpty) {
    final full = _orientedRectSamples(center, yaw, widthM, depthM, inflateM: 0);
    final shrinkOk = floorMarginM * 2 < widthM && floorMarginM * 2 < depthM;
    final inset = shrinkOk
        ? _orientedRectSamples(center, yaw, widthM, depthM,
            inflateM: -floorMarginM)
        : full;
    for (final s in inset) {
      if (!_pointOnZones(s, floorZones)) return false;
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
  }
  return !footprintStraddlesWall(
    center: center,
    yaw: yaw,
    widthM: widthM,
    depthM: depthM,
    walls: walls,
  );
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

// Furniture-scale floating fragments — a misdetected desk/console/sofa
// face with a gap under it — stretch to the floor even past [maxDropM]:
// the gap is exactly where green read inside the wall area and models
// wedged into the plane. Wall-scale fragments and genuinely high ones
// keep [maxDropM]: a shelf face must never paint a phantom sheet below
// itself.
const _furnitureScaleHeightM = 1.5;
const _furnitureScaleMaxDropM = 0.75;

// ARCore wall fragments routinely stop 10–20 cm above the floor, which
// leaves exactly the green base strip at the wall foot — the floor−wall
// clip can't cut what the wall doesn't cover. Stretch a short wall down
// to [refY]; geometry that dips BELOW the floor (ARCore polygon
// overshoot, bottom-heavy RANSAC rects) is raised back onto it instead of
// passing through to paint as blue-on-green. A fragment floating well
// above (a shelf), a wall already reaching the floor, or a non-vertical
// quad pass through untouched.
PlaneQuad withWallBaseAt(PlaneQuad wall,
    {required double refY, double maxDropM = 0.45}) {
  if (!wall.vertical || !refY.isFinite) return wall;
  if (wall.polygon.length < 3) {
    final top = wall.center.y + wall.extentZ / 2;
    final bottom = wall.center.y - wall.extentZ / 2;
    if (top <= refY) {
      // Wholly below (extent-swap garbage): lift rigidly, keep height.
      return PlaneQuad(
        center: Vector3(wall.center.x, refY + wall.extentZ / 2, wall.center.z),
        yaw: wall.yaw,
        extentX: wall.extentX,
        extentZ: wall.extentZ,
        vertical: true,
        kind: wall.kind,
      );
    }
    if (bottom < refY) {
      // Dip: raise the bottom onto refY, keep the top.
      final newExtentZ = top - refY;
      return PlaneQuad(
        center: Vector3(wall.center.x, refY + newExtentZ / 2, wall.center.z),
        yaw: wall.yaw,
        extentX: wall.extentX,
        extentZ: newExtentZ,
        vertical: true,
        kind: wall.kind,
      );
    }
    if (bottom == refY) return wall;
    final drop = bottom - refY;
    final furnitureScale = wall.extentZ <= _furnitureScaleHeightM &&
        drop <= _furnitureScaleMaxDropM;
    if (!furnitureScale && drop > maxDropM) return wall;
    final newExtentZ = wall.extentZ + (bottom - refY);
    return PlaneQuad(
      center: Vector3(wall.center.x, refY + newExtentZ / 2, wall.center.z),
      yaw: wall.yaw,
      extentX: wall.extentX,
      extentZ: newExtentZ,
      vertical: true,
      kind: wall.kind,
    );
  }
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  for (final v in wall.polygon) {
    if (v.y < minY) minY = v.y;
    if (v.y > maxY) maxY = v.y;
  }
  if (!minY.isFinite || minY == refY) return wall;
  if (maxY <= refY) {
    // Wholly below: translate the whole ring up — cutting a wholly-below
    // ring at refY would collapse it to a line.
    final delta = refY - minY;
    return PlaneQuad(
      center: Vector3(wall.center.x, wall.center.y + delta, wall.center.z),
      yaw: wall.yaw,
      extentX: wall.extentX,
      extentZ: wall.extentZ,
      vertical: true,
      kind: wall.kind,
      polygon: [for (final v in wall.polygon) Vector3(v.x, v.y + delta, v.z)],
    );
  }
  if (minY > refY) {
    final drop = minY - refY;
    final furnitureScale = (maxY - minY) <= _furnitureScaleHeightM &&
        drop <= _furnitureScaleMaxDropM;
    if (!furnitureScale && drop > maxDropM) return wall;
  }
  // ARCore's bottom edge wobbles a few cm — snap the whole bottom row
  // (within 10 cm of the cut) flat onto the floor line. The clamp branch
  // cuts at refY+0.10 so every sub-floor vertex is raised.
  final rowCut = math.max(minY, refY) + 0.10;
  final newBottomY = refY;
  final delta = newBottomY - minY;
  return PlaneQuad(
    center: Vector3(wall.center.x, wall.center.y + delta, wall.center.z),
    yaw: wall.yaw,
    extentX: wall.extentX,
    extentZ: wall.extentZ,
    vertical: true,
    kind: wall.kind,
    polygon: [
      for (final v in wall.polygon)
        v.y <= rowCut ? Vector3(v.x, newBottomY, v.z) : v,
    ],
  );
}

// Greedy union of near-coplanar wall fragments into single clean
// rectangles — ARCore reports a wall as a row of small patches whose
// union reads as a stepped "tetris" silhouette. Compatible fragments
// (similar yaw, overlapping heights, footprints within 0.18 m) merge
// until nothing more combines; a merged wall deliberately drops the
// per-fragment outlines. Unmerged quads pass through with their polygon
// intact. Callers run withWallBaseAt BEFORE this so merged y-ranges
// already include the stretched bases.
List<PlaneQuad> mergeWallQuads(List<PlaneQuad> walls) {
  if (walls.length < 2) return List<PlaneQuad>.of(walls);
  final sorted = List<PlaneQuad>.of(walls)..sort(_wallMergeOrder);
  var groups = <List<PlaneQuad>>[
    for (final q in sorted) [q],
  ];
  var merged = true;
  while (merged) {
    merged = false;
    search:
    for (var i = 0; i < groups.length; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        if (_wallGroupsCompatible(groups[i], groups[j])) {
          groups[i] = [...groups[i], ...groups[j]];
          groups.removeAt(j);
          merged = true;
          break search;
        }
      }
    }
  }
  return [
    for (final g in groups) g.length == 1 ? g.single : _mergeWallGroup(g),
  ];
}

// Bounds mergeWallQuads' O(groups²·members²) search: a long scan piles up
// vertical fragments until that loop eats the frame. The biggest [max]
// footprints carry the silhouette; the painter drops off-screen ones after.
List<PlaneQuad> capWallQuads(List<PlaneQuad> walls, int max) {
  if (walls.length <= max) return walls;
  final sorted = List<PlaneQuad>.of(walls)
    ..sort((a, b) =>
        (b.extentX * b.extentZ).compareTo(a.extentX * a.extentZ));
  return sorted.sublist(0, max);
}

// Perpendicular runs meeting at a corner: ARCore's patch outlines stop
// short of the shared edge on at least one side, and the 0.26 rad merge cap
// can never bridge them, so the silhouette leaves a notch at every corner.
// Extend each run along its own line to the intersection of the two lines —
// only when BOTH ends are genuinely near it (within [maxGapM], so distant
// walls whose infinite lines happen to cross never stretch), the height
// ranges overlap, and each end joins at most once per pass. Y extents are
// untouched — withWallBaseAt already owns the vertical stretch. ARCore runs
// commonly end 0.5–0.8 m short of the corner, so the gap bound sits at 0.8;
// beyond that a break in the wall (door reveal, pillar) risks bridging.
List<PlaneQuad> joinWallCorners(List<PlaneQuad> walls,
    {double maxGapM = 0.8, double maxTrimM = 0.3}) {
  if (walls.length < 2) return List<PlaneQuad>.of(walls);
  final out = List<PlaneQuad>.of(walls);
  final yRange = [for (final q in out) _groupYRange([q])];
  final usedEnds = <int, Set<int>>{};
  for (var i = 0; i < out.length; i++) {
    for (var j = i + 1; j < out.length; j++) {
      final a = out[i];
      final b = out[j];
      if (!a.vertical || !b.vertical) continue;
      // Unoriented dihedral, as in wallFitConsistentWith: a hemisphere-
      // flipped yaw must still read as a right angle.
      final raw = wrapYaw(a.yaw - b.yaw).abs();
      final dihedral = raw <= math.pi / 2 ? raw : math.pi - raw;
      if ((dihedral - math.pi / 2).abs() > 0.30) continue;
      final ra = yRange[i];
      final rb = yRange[j];
      final overlap = (ra.$2 < rb.$2 ? ra.$2 : rb.$2) -
          (ra.$1 > rb.$1 ? ra.$1 : rb.$1);
      if (overlap < 0.05) continue;
      final uax = math.cos(a.yaw);
      final uaz = -math.sin(a.yaw);
      final ubx = math.cos(b.yaw);
      final ubz = -math.sin(b.yaw);
      final rcx = b.center.x - a.center.x;
      final rcz = b.center.z - a.center.z;
      final cross = uax * ubz - uaz * ubx;
      // cross = sin(dihedral); the gate above keeps it far from singular.
      final t = (rcx * ubz - rcz * ubx) / cross; // P = cA + t·uA
      final s = (rcx * uaz - rcz * uax) / cross; // P = cB + s·uB
      // Signed: positive = the run stops short of the corner, negative = it
      // pokes past it. A small overshoot is fit noise bleeding paint over
      // the adjacent wall and is cut back; a long one is a through-wall at
      // a T-junction and stays.
      final gapA = t.abs() - a.extentX / 2;
      final gapB = s.abs() - b.extentX / 2;
      if (gapA > maxGapM || gapB > maxGapM) continue;
      double adjust(double gap) =>
          (gap > 0.03 || (gap < -0.03 && gap >= -maxTrimM)) ? gap : 0.0;
      final adjA = adjust(gapA);
      final adjB = adjust(gapB);
      if (adjA == 0 && adjB == 0) continue;
      final endA = t > 0 ? 1 : -1;
      final endB = s > 0 ? 1 : -1;
      if (adjA != 0 && (usedEnds[i]?.contains(endA) ?? false)) continue;
      if (adjB != 0 && (usedEnds[j]?.contains(endB) ?? false)) continue;
      if (adjA != 0) {
        out[i] = _extendWallEnd(a, gap: adjA, end: endA);
        (usedEnds[i] ??= <int>{}).add(endA);
      }
      if (adjB != 0) {
        out[j] = _extendWallEnd(b, gap: adjB, end: endB);
        (usedEnds[j] ??= <int>{}).add(endB);
      }
    }
  }
  return out;
}

// Grow one end of a wall run along its own line by [gap]. A polygon-
// bearing outline moves only the vertices at that extreme, so the ARCore
// shape rides along instead of being replaced by the rectangle.
PlaneQuad _extendWallEnd(PlaneQuad q, {required double gap, required int end}) {
  final ux = math.cos(q.yaw);
  final uz = -math.sin(q.yaw);
  final center = Vector3(
    q.center.x + ux * gap / 2 * end,
    q.center.y,
    q.center.z + uz * gap / 2 * end,
  );
  List<Vector3> poly = q.polygon;
  if (gap < 0 && poly.length >= 3) {
    // Trim: clamp the outline at the corner line; vertices short of it keep
    // the ARCore shape.
    final limit = q.extentX / 2 + gap;
    poly = [
      for (final v in poly)
        () {
          final p = (v.x - q.center.x) * ux + (v.z - q.center.z) * uz;
          final over = p * end - limit;
          return over > 0 ? v - Vector3(ux * over * end, 0, uz * over * end) : v;
        }(),
    ];
  } else if (poly.length >= 3) {
    var minP = double.infinity;
    var maxP = double.negativeInfinity;
    for (final v in poly) {
      final p = (v.x - q.center.x) * ux + (v.z - q.center.z) * uz;
      if (p < minP) minP = p;
      if (p > maxP) maxP = p;
    }
    final span = maxP - minP;
    if (span > 0.05) {
      final tol = math.min(0.25, span * 0.3);
      final edge = end > 0 ? maxP - tol : minP + tol;
      poly = [
        for (final v in poly)
          if (end > 0
              ? (v.x - q.center.x) * ux + (v.z - q.center.z) * uz >= edge
              : (v.x - q.center.x) * ux + (v.z - q.center.z) * uz <= edge)
            v + Vector3(ux * gap * end, 0, uz * gap * end)
          else
            v,
      ];
    } else {
      // Degenerate outline: the grown rectangle is the fitted truth.
      poly = const [];
    }
  }
  return PlaneQuad(
    center: center,
    yaw: q.yaw,
    extentX: q.extentX + gap,
    extentZ: q.extentZ,
    vertical: q.vertical,
    kind: q.kind,
    polygon: poly,
  );
}

int _wallMergeOrder(PlaneQuad a, PlaneQuad b) {
  final byWidth = b.extentX.compareTo(a.extentX);
  if (byWidth != 0) return byWidth;
  final byX = a.center.x.compareTo(b.center.x);
  if (byX != 0) return byX;
  final byZ = a.center.z.compareTo(b.center.z);
  if (byZ != 0) return byZ;
  final byY = a.center.y.compareTo(b.center.y);
  if (byY != 0) return byY;
  return a.yaw.compareTo(b.yaw);
}

bool _wallGroupsCompatible(List<PlaneQuad> a, List<PlaneQuad> b) {
  if (a.isEmpty || b.isEmpty) return false;
  if (!a.every((q) => q.vertical) || !b.every((q) => q.vertical)) return false;
  // Exact pairwise spread over a∪b — checking only the two groups' current
  // yaws lets a widest-led chain (0 → 0.13 → 0.26 → 0.39 …) accumulate
  // unbounded total drift while every step stays ≤0.26.
  final all = [...a, ...b];
  for (var i = 0; i < all.length; i++) {
    for (var j = i + 1; j < all.length; j++) {
      if (wrapYaw(all[i].yaw - all[j].yaw).abs() > 0.26) return false;
    }
  }
  final ra = _groupYRange(a);
  final rb = _groupYRange(b);
  if (ra.$2 < rb.$1 - 0.05 || rb.$2 < ra.$1 - 0.05) return false;
  for (final qa in a) {
    for (final qb in b) {
      if (_wallFootprintGap(qa, qb) <= 0.18) return true;
    }
  }
  return false;
}

// The widest POLYGON-bearing member owns the merged frame — its yaw is
// ARCore telemetry, while rect-only synthetics are fits. All-synthetic
// groups fall back to the median (halves worst-case error vs widest).
double _groupYaw(List<PlaneQuad> g) {
  PlaneQuad? bestPoly;
  for (final q in g) {
    if (q.polygon.length < 3) continue;
    if (bestPoly == null || q.extentX > bestPoly.extentX) bestPoly = q;
  }
  if (bestPoly != null) return bestPoly.yaw;
  final base = g.first.yaw;
  final deltas = [
    for (final q in g) wrapYaw(q.yaw - base),
  ]..sort();
  final n = deltas.length;
  final mid = n.isOdd
      ? deltas[n ~/ 2]
      : (deltas[n ~/ 2 - 1] + deltas[n ~/ 2]) / 2;
  return wrapYaw(base + mid);
}

(double, double) _groupYRange(List<PlaneQuad> g) {
  var lo = double.infinity;
  var hi = double.negativeInfinity;
  for (final q in g) {
    for (final c in planeQuadCorners(q)) {
      if (c.y < lo) lo = c.y;
      if (c.y > hi) hi = c.y;
    }
  }
  return (lo, hi);
}

// Wraps a yaw delta into (−π, π]; public because the lock and the screen
// both measure rotation against it.
double wrapYaw(double delta) {
  var w = delta % (2 * math.pi);
  if (w > math.pi) w -= 2 * math.pi;
  if (w < -math.pi) w += 2 * math.pi;
  return w;
}

// XZ gap between two wall footprints: 0 when either outline touches or
// crosses the other, otherwise the closest corner-to-outline distance.
double _wallFootprintGap(PlaneQuad a, PlaneQuad b) {
  final ca = _flattenXZ(planeQuadCorners(a));
  final cb = _flattenXZ(planeQuadCorners(b));
  if (ca.length < 3 || cb.length < 3) return double.infinity;
  if (_xzCornersInside(ca, cb) || _xzCornersInside(cb, ca)) return 0;
  if (_xzOutlinesCross(ca, cb)) return 0;
  var best = double.infinity;
  for (final p in ca) {
    final n = _nearestOnOutlineXZ(p, cb);
    final d = math.sqrt((p.x - n.x) * (p.x - n.x) + (p.z - n.z) * (p.z - n.z));
    if (d < best) best = d;
  }
  for (final p in cb) {
    final n = _nearestOnOutlineXZ(p, ca);
    final d = math.sqrt((p.x - n.x) * (p.x - n.x) + (p.z - n.z) * (p.z - n.z));
    if (d < best) best = d;
  }
  return best;
}

List<Vector3> _flattenXZ(List<Vector3> pts) =>
    [for (final p in pts) Vector3(p.x, 0, p.z)];

bool _xzCornersInside(List<Vector3> corners, List<Vector3> poly) {
  final n = _polygonNormal(poly);
  if (n == null) return false;
  for (final c in corners) {
    if (_pointInPolygon(c, poly, n)) return true;
  }
  return false;
}

bool _xzOutlinesCross(List<Vector3> a, List<Vector3> b) {
  for (var i = 0; i < a.length; i++) {
    final a1 = a[i];
    final a2 = a[(i + 1) % a.length];
    for (var j = 0; j < b.length; j++) {
      final b1 = b[j];
      final b2 = b[(j + 1) % b.length];
      if (_segmentsProperCross(a1, a2, b1, b2)) return true;
    }
  }
  return false;
}

// Proper (strict) crossing only — abutting outlines already measure gap 0
// through the corner-to-outline distance.
bool _segmentsProperCross(Vector3 p1, Vector3 p2, Vector3 q1, Vector3 q2) {
  final d1 = _crossXZ(q1, q2, p1);
  final d2 = _crossXZ(q1, q2, p2);
  final d3 = _crossXZ(p1, p2, q1);
  final d4 = _crossXZ(p1, p2, q2);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

double _crossXZ(Vector3 o, Vector3 a, Vector3 b) =>
    (a.x - o.x) * (b.z - o.z) - (a.z - o.z) * (b.x - o.x);

// One clean rect through every member's corners, expressed in the
// canonical yaw frame: extentX spans the wall, extentZ the height, and
// the outline (polygon) is dropped on purpose.
PlaneQuad _mergeWallGroup(List<PlaneQuad> g) {
  final yaw = _groupYaw(g);
  final cosY = math.cos(yaw);
  final sinY = math.sin(yaw);
  // along = (cos yaw, 0, −sin yaw); normal = (sin yaw, 0, cos yaw).
  final ux = cosY;
  final uz = -sinY;
  final nx = sinY;
  final nz = cosY;
  var minAlong = double.infinity;
  var maxAlong = double.negativeInfinity;
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  var normalSum = 0.0;
  var normalCount = 0;
  for (final q in g) {
    for (final c in planeQuadCorners(q)) {
      final along = c.x * ux + c.z * uz;
      if (along < minAlong) minAlong = along;
      if (along > maxAlong) maxAlong = along;
      if (c.y < minY) minY = c.y;
      if (c.y > maxY) maxY = c.y;
      normalSum += c.x * nx + c.z * nz;
      normalCount++;
    }
  }
  final width = maxAlong - minAlong;
  final height = maxY - minY;
  final midAlong = (minAlong + maxAlong) / 2;
  final normalMid = normalCount == 0 ? 0.0 : normalSum / normalCount;
  return PlaneQuad(
    center: Vector3(
      midAlong * ux + normalMid * nx,
      minY + height / 2,
      midAlong * uz + normalMid * nz,
    ),
    yaw: yaw,
    extentX: width,
    extentZ: height,
    vertical: true,
    kind: PlaneQuadKind.wall,
  );
}

// Bounds one zone's polygons before the path booleans: anything off the
// viewport (or a sub-16px dust speck) costs time and draws nothing, and
// past [cap] only the largest screen-area regions remain — the visual bulk
// of the zone. Caps only bite when more than [cap] regions share one
// screen, so a normal room paints exactly as before.
List<List<Offset>> boundZonePolys(
  List<List<Offset>> polys,
  Size viewport,
  int cap,
) {
  const margin = 8.0;
  const dustArea = 256.0;
  final kept = <(List<Offset>, double)>[];
  for (final p in polys) {
    var x0 = double.infinity;
    var y0 = double.infinity;
    var x1 = double.negativeInfinity;
    var y1 = double.negativeInfinity;
    for (final o in p) {
      if (o.dx < x0) x0 = o.dx;
      if (o.dx > x1) x1 = o.dx;
      if (o.dy < y0) y0 = o.dy;
      if (o.dy > y1) y1 = o.dy;
    }
    if (x1 < -margin ||
        x0 > viewport.width + margin ||
        y1 < -margin ||
        y0 > viewport.height + margin) {
      continue;
    }
    final area = (x1 - x0) * (y1 - y0);
    if (area < dustArea) continue;
    kept.add((p, area));
  }
  if (kept.length > cap) {
    kept.sort((a, b) => b.$2.compareTo(a.$2));
    kept.length = cap;
  }
  return [for (final k in kept) k.$1];
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
  // One union pass per zone, never one per fragment: every outline goes
  // into a single nonZero path with a common winding (overlaps then fill as
  // a union instead of cancelling) and Skia resolves it in one sweep. The
  // old fragment-by-fragment union re-processed the growing result N times
  // on every camera move — the "laggy once planes pile up" cost (bench:
  // 4.7 → 2.2 ms on a 14-floor/10-wall/12-mask scene). Folding the cuts
  // into the same op measured slower (3.7 ms), so cuts stay separate.
  Path? merge(List<List<Offset>> polys) {
    final path = Path()..fillType = PathFillType.nonZero;
    var n = 0;
    for (final p in polys) {
      final s = simplifyScreenPolygon(p);
      if (s.length < 3) continue;
      path.addPolygon(_signedArea(s) >= 0 ? s : s.reversed.toList(), true);
      n++;
    }
    if (n == 0) return null;
    return Path.combine(PathOperation.union, path, Path());
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

double _signedArea(List<Offset> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    a += p[i].dx * p[j].dy - p[j].dx * p[i].dy;
  }
  return a / 2;
}

// Drops vertices that sit within [tolPx] of the line through their
// neighbours (ARCore outlines carry up to 64 near-collinear points), then
// caps the count — boolean cost scales with edges, the look does not.
List<Offset> simplifyScreenPolygon(List<Offset> p,
    {double tolPx = 1.5, int maxVerts = 24}) {
  if (p.length <= 3) return p;
  var pts = List<Offset>.of(p);
  var changed = true;
  while (changed && pts.length > 3) {
    changed = false;
    for (var i = 0; i < pts.length && pts.length > 3; i++) {
      final a = pts[(i + pts.length - 1) % pts.length];
      final b = pts[i];
      final c = pts[(i + 1) % pts.length];
      final ac = c - a;
      final len = ac.distance;
      final d = len < 1e-9
          ? (b - a).distance
          : ((b - a).dx * ac.dy - (b - a).dy * ac.dx).abs() / len;
      if (d < tolPx) {
        pts.removeAt(i);
        changed = true;
        i--;
      }
    }
  }
  if (pts.length > maxVerts) {
    final stride = pts.length / maxVerts;
    pts = [for (var k = 0; k < maxVerts; k++) pts[(k * stride).floor()]];
  }
  return pts;
}
