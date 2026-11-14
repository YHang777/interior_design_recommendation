import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:vector_math/vector_math_64.dart';

import 'placement_policy.dart';
import 'plane_overlay_math.dart';

// Feature-point cells dense with obstacle-height samples → mask quads.
// Same treatment as furniture plane masks: clip green paint, block
// placement. Cells are XZ buckets of cellM; a cell needs ≥3 obstacle
// points before it counts (a lone noisy point masks nothing). Cells
// cluster with 8-connectivity (diagonals merge) and each cluster becomes
// ONE convex-hull quad — one chair masks as a smooth outline, not a
// staircase of grid cells. Clusters that mostly hug a detected wall are
// dropped: those points describe the wall, not an object on the floor.
List<PlaneQuad> obstacleMaskQuads({
  required List<double> points,
  required double refY,
  List<ARPlaneInfo> walls = const [],
  double cellM = 0.3,
}) {
  if (cellM <= 0) return const [];
  final cells = <String, _Cell>{};
  final floorEvidence = <String, int>{};
  for (var i = 0; i + 2 < points.length; i += 3) {
    final x = points[i];
    final y = points[i + 1];
    final z = points[i + 2];
    if (!x.isFinite || !y.isFinite || !z.isFinite) continue;
    final dy = y - refY;
    final ix = (x / cellM).floor();
    final iz = (z / cellM).floor();
    final key = '$ix:$iz';
    // Depth noise puts a handful of points 0.25–0.35 m above the floor on
    // open floor; those cells must be recognisable as floor-with-a-tail
    // below, or they punch phantom holes and fragment the placement area.
    if (dy > -0.10 && dy <= 0.15) {
      floorEvidence[key] = (floorEvidence[key] ?? 0) + 1;
    }
    // Obstacle band only: floor-band points and anything at/above2.2 m
    // (door frames, ceilings) never mask the floor.
    if (dy <= 0.25 || dy >= 2.2) continue;
    final cell = cells.putIfAbsent(key, () => _Cell(ix, iz));
    cell.add(y);
  }
  final dense = <_Cell>[
    for (final c in cells.values)
      if (c.count >= 3 && !_dominatedByFloor(c, floorEvidence)) c,
  ];
  if (dense.isEmpty) return const [];
  final clusters = <_MaskCluster>[];
  for (final cluster in _clusterCells(dense)) {
    if (_clusterSitsOnWall(cluster, walls, cellM)) continue;
    if (!_clusterIsCompact(cluster, cellM)) continue;
    clusters.add(cluster);
  }
  // Biggest cluster first; min (ix, iz) breaks ties so the same cloud
  // always masks the same 14 cells-worth of hulls.
  clusters.sort((a, b) {
    if (a.total != b.total) return b.total.compareTo(a.total);
    if (a.minIx != b.minIx) return a.minIx.compareTo(b.minIx);
    return a.minIz.compareTo(b.minIz);
  });
  return [
    for (final c in clusters.take(14)) _clusterToQuad(c, cellM),
  ];
}

// A cell whose floor evidence is both absolute (≥3 points) and dominant
// (more than 3× the elevated count) is open floor with a noise tail, not
// an object — object cells (seat tops) have hundreds of elevated points
// and little or no floor evidence under them.
bool _dominatedByFloor(_Cell c, Map<String, int> floorEvidence) {
  final floorCount = floorEvidence['${c.ix}:${c.iz}'] ?? 0;
  return floorCount >= 3 && floorCount > c.count * 3;
}

// 8-connected components over the dense cells: diagonal neighbours merge,
// which is what kills the staircase silhouette.
List<_MaskCluster> _clusterCells(List<_Cell> dense) {
  final byPos = <String, _Cell>{
    for (final c in dense) '${c.ix}:${c.iz}': c,
  };
  final seen = <String>{};
  final out = <_MaskCluster>[];
  for (final start in dense) {
    final startKey = '${start.ix}:${start.iz}';
    if (seen.contains(startKey)) continue;
    seen.add(startKey);
    final queue = <_Cell>[start];
    final cells = <_Cell>[];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      cells.add(cur);
      for (var dx = -1; dx <= 1; dx++) {
        for (var dz = -1; dz <= 1; dz++) {
          if (dx == 0 && dz == 0) continue;
          final key = '${cur.ix + dx}:${cur.iz + dz}';
          if (seen.contains(key)) continue;
          final nb = byPos[key];
          if (nb == null) continue;
          seen.add(key);
          queue.add(nb);
        }
      }
    }
    cells.sort((a, b) =>
        a.ix != b.ix ? a.ix.compareTo(b.ix) : a.iz.compareTo(b.iz));
    var total = 0;
    for (final c in cells) {
      total += c.count;
    }
    out.add(_MaskCluster(cells, total, cells.first.ix, cells.first.iz));
  }
  return out;
}

// Objects fill their outline; a chain of wall + furniture points around an
// undetected wall does not. Device round 7: such a chain hulled into a
// 2.8×2.75 m "object" that punched 40–93% of the screen out of both zones,
// so painted planes kept vanishing. Sparse or room-sized hulls are dropped.
bool _clusterIsCompact(_MaskCluster cluster, double cellM) {
  final hull = _clusterToQuad(cluster, cellM);
  final poly = hull.polygon;
  var area = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    area += a.x * b.z - b.x * a.z;
  }
  area = area.abs() / 2;
  if (math.max(hull.extentX, hull.extentZ) > maxObstacleSpanM) return false;
  final filled = cluster.cells.length * cellM * cellM;
  if (area > 0.8 && filled < area * minObstacleFill) return false;
  return true;
}

const double maxObstacleSpanM = 2.2;
const double minObstacleFill = 0.45;

// ≥60% of the cluster's points (weighted) sitting on a wall plane means
// the cluster IS wall surface — punching it into the floor/mask would
// carve holes into the painted wall itself.
bool _clusterSitsOnWall(
  _MaskCluster cluster,
  List<ARPlaneInfo> walls,
  double cellM,
) {
  if (walls.isEmpty) return false;
  var total = 0;
  var hug = 0;
  for (final c in cluster.cells) {
    total += c.count;
    if (_cellHugsWall(c, walls, cellM)) hug += c.count;
  }
  return hug * 5 >= total * 3;
}

bool _cellHugsWall(_Cell cell, List<ARPlaneInfo> walls, double cellM) {
  final cx = (cell.ix + 0.5) * cellM;
  final cz = (cell.iz + 0.5) * cellM;
  for (final w in walls) {
    if (w.planeType != 2) continue;
    // No area gate here: this exempts cells from masking (wall feet keep
    // their floor) — it is not wall classification, and the shared gate
    // already guards the five sites that paint/score/classify walls.
    final sinY = math.sin(w.yaw);
    final cosY = math.cos(w.yaw);
    // Vertical plane: normal (sin yaw, 0, cos yaw), width along
    // (cos yaw, 0, −sin yaw); extentZ is the height.
    final dx = cx - w.centerX;
    final dz = cz - w.centerZ;
    if ((dx * sinY + dz * cosY).abs() > 0.15) continue;
    if ((dx * cosY - dz * sinY).abs() > w.extentX / 2 + 0.25) continue;
    final bottom = w.centerY - w.extentZ / 2;
    final top = w.centerY + w.extentZ / 2;
    if (cell.meanY < bottom - 0.06 || cell.meanY > top + 0.06) continue;
    return true;
  }
  return false;
}

// Convex hull of every cell-square corner (XZ), flat at the cluster's
// weighted mean Y — one smooth mask outline instead of per-cell quads.
PlaneQuad _clusterToQuad(_MaskCluster cluster, double cellM) {
  final corners = <Vector2>[];
  var sumWeightedY = 0.0;
  var sumCount = 0;
  for (final c in cluster.cells) {
    final x0 = c.ix * cellM;
    final x1 = (c.ix + 1) * cellM;
    final z0 = c.iz * cellM;
    final z1 = (c.iz + 1) * cellM;
    corners
      ..add(Vector2(x0, z0))
      ..add(Vector2(x1, z0))
      ..add(Vector2(x0, z1))
      ..add(Vector2(x1, z1));
    sumWeightedY += c.meanY * c.count;
    sumCount += c.count;
  }
  final hull = _convexHullXZ(corners);
  var minX = hull.first.x;
  var maxX = hull.first.x;
  var minZ = hull.first.y;
  var maxZ = hull.first.y;
  for (final p in hull) {
    if (p.x < minX) minX = p.x;
    if (p.x > maxX) maxX = p.x;
    if (p.y < minZ) minZ = p.y;
    if (p.y > maxZ) maxZ = p.y;
  }
  final meanY = sumWeightedY / sumCount;
  return PlaneQuad(
    center: Vector3((minX + maxX) / 2, meanY, (minZ + maxZ) / 2),
    yaw: 0,
    extentX: maxX - minX,
    extentZ: maxZ - minZ,
    vertical: false,
    kind: PlaneQuadKind.floor,
    polygon: [for (final p in hull) Vector3(p.x, meanY, p.y)],
  );
}

// Andrew's monotone chain over (x, z): deterministic CCW, collinear
// midpoints dropped so a straight run of cells has no fake vertices.
List<Vector2> _convexHullXZ(List<Vector2> pts) {
  final sorted = [...pts]..sort((a, b) {
      final c = a.x.compareTo(b.x);
      if (c != 0) return c;
      return a.y.compareTo(b.y);
    });
  final uniq = <Vector2>[];
  for (final p in sorted) {
    if (uniq.isNotEmpty && uniq.last.x == p.x && uniq.last.y == p.y) {
      continue;
    }
    uniq.add(p);
  }
  if (uniq.length <= 2) return uniq;
  double cross(Vector2 o, Vector2 a, Vector2 b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final lower = <Vector2>[];
  for (final p in uniq) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Vector2>[];
  for (var i = uniq.length - 1; i >= 0; i--) {
    final p = uniq[i];
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

// Low-percentile Y of floor-band points — the robust refocus signal when
// plane telemetry is quiet. The band reaches well below the current
// estimate so a too-high floorY can still find the real floor under it,
// and only a little above it (a table up there is not floor evidence).
// The p20 matches the native probe: a median in this band sat with the
// wall-base points, agreed with the wrong estimate forever, and its
// disagreement with the native reading reset the correction streak on
// every tick — floorY could never come down. Null below 8 samples so one
// stray speck can never steer floorY (PlaneMemory applies its own
// deadband on top).
double? floorProbeCandidate({
  required List<double> points,
  required double refY,
}) {
  final ys = <double>[];
  for (var i = 0; i + 2 < points.length; i += 3) {
    final y = points[i + 1];
    if (!y.isFinite) continue;
    if (y >= refY - 0.6 && y <= refY + 0.15) ys.add(y);
  }
  if (ys.length < 8) return null;
  ys.sort();
  return ys[((ys.length - 1) * 0.2).toInt()];
}

// RANSAC vertical planes from the feature-point cloud — ARCore reports
// zero vertical planes on white walls, but the cloud still sees them.
// Ids live at 900001+: native planeIdFor mints 1..N per session
// (nextPlaneId++), so the synthetic range can never collide with a real
// plane id.
List<ARPlaneInfo> fitWallPlanes({
  required List<double> points,
  required double refY,
  int maxPlanes = 2,
  List<ARPlaneInfo> existing = const [],
}) {
  if (maxPlanes <= 0) return const [];
  final cand = <Vector3>[];
  for (var i = 0; i + 2 < points.length; i += 3) {
    final x = points[i];
    final y = points[i + 1];
    final z = points[i + 2];
    if (!x.isFinite || !y.isFinite || !z.isFinite) continue;
    if (y > refY + 0.2 && y < refY + 2.2) cand.add(Vector3(x, y, z));
  }
  if (cand.length < 30) return const [];
  // Sorted input + seeded pick sequence → identical output for identical
  // clouds, so tests can pin the fits.
  cand.sort((a, b) {
    final c = a.x.compareTo(b.x);
    if (c != 0) return c;
    final c2 = a.y.compareTo(b.y);
    if (c2 != 0) return c2;
    return a.z.compareTo(b.z);
  });

  var seed = 12345;
  int next(int n) {
    seed = (seed * 48271) % 2147483647;
    return seed % n;
  }

  final out = <ARPlaneInfo>[];
  var pool = cand;
  var rejects = 0;
  while (out.length < maxPlanes && pool.length >= 30) {
    final fit = _ransacWall(pool, next);
    if (fit == null) break;
    final plane = ARPlaneInfo(
      id: 900001 + out.length,
      planeType: 2,
      centerX: fit.cx,
      centerY: fit.cy,
      centerZ: fit.cz,
      extentX: fit.width,
      extentZ: fit.height,
      yaw: fit.yaw,
    );
    if (!wallFitConsistentWith(plane, existing)) {
      // Grazing-pan phantom: drop its inliers and retry. The budget allows
      // a few false rejects (noisy corner-yaw references) before giving up
      // — every reject removes that fit's inliers from the pool, so one
      // bad verdict used to erase the corner's wall run for the tick.
      final drop = fit.inliers.toSet();
      pool = [
        for (var i = 0; i < pool.length; i++)
          if (!drop.contains(i)) pool[i],
      ];
      if (++rejects > 4) break;
      continue;
    }
    out.add(plane);
    final drop = fit.inliers.toSet();
    pool = [
      for (var i = 0; i < pool.length; i++)
        if (!drop.contains(i)) pool[i],
    ];
  }
  return out;
}

// A fit claiming an existing wall's surface at a contradictory yaw is the
// grazing-pan signature: depth noise rotates the fitted normal off the
// wall while the inlier mean stays on it, so perpendicular distance to
// the good wall is ~0. Same-place = within 0.30 m of the reference
// plane; yawDiff ≤0.20 is fit noise (ARCore yaw wobbles hardest near
// corners, where real fits kept getting rejected) and >1.3 is a true
// corner — both pass. Orientation is compared UNORIENTED (mod π): fits are
// hemisphere-canonicalized in _ransacWall while references carry native
// yaw in (−π, π], so a raw wrap reads a flipped-hemisphere same-surface
// pair ~π apart — past the corner cap — and the gate fail-opens.
// Pure; existing=[] is inert.
bool wallFitConsistentWith(ARPlaneInfo fit, List<ARPlaneInfo> existing) {
  for (final e in existing) {
    if (e.planeType != 2 || e.subsumed) continue;
    final raw = _wrapPi(fit.yaw - e.yaw).abs();
    final yawDiff = raw <= math.pi / 2 ? raw : math.pi - raw;
    if (yawDiff <= 0.20 || yawDiff > 1.3) continue;
    final nx = math.sin(e.yaw);
    final nz = math.cos(e.yaw);
    final d1 = ((fit.centerX - e.centerX) * nx +
            (fit.centerZ - e.centerZ) * nz)
        .abs();
    final fnx = math.sin(fit.yaw);
    final fnz = math.cos(fit.yaw);
    final d2 = ((e.centerX - fit.centerX) * fnx +
            (e.centerZ - fit.centerZ) * fnz)
        .abs();
    if (math.min(d1, d2) <= 0.30) return false;
  }
  return true;
}

_Fit? _ransacWall(List<Vector3> pool, int Function(int) next) {
  // 60 rounds: halving to 30 shrank fit quality on sparse white-wall
  // pools, and a smaller inlier bbox then failed the 1.0 m² admission —
  // detection recall collapsed exactly where ARCore reports no planes.
  const rounds = 60;
  final n = pool.length;
  _Fit? best;
  for (var r = 0; r < rounds; r++) {
    final i0 = next(n);
    var i1 = next(n - 1);
    if (i1 >= i0) i1++;
    var i2 = next(n - 2);
    if (i2 >= i0) i2++;
    if (i2 >= i1) i2++;
    final p0 = pool[i0];
    final p1 = pool[i1];
    final p2 = pool[i2];
    final nrm = (p1 - p0).cross(p2 - p0);
    if (nrm.length2 < 1e-12) continue;
    nrm.normalize();
    if (nrm.y.abs() >= 0.3) continue;
    final inliers = <int>[];
    for (var i = 0; i < n; i++) {
      if ((pool[i] - p0).dot(nrm).abs() <= 0.05) inliers.add(i);
    }
    if (inliers.length < 30) continue;
    // Width runs along the wall's horizontal axis — the same direction
    // extentX spans for a telemetry vertical plane (cos yaw, 0, −sin yaw).
    final rXZ = math.sqrt(nrm.x * nrm.x + nrm.z * nrm.z);
    if (rXZ < 1e-9) continue;
    final hx = nrm.z / rXZ;
    final hz = -nrm.x / rXZ;
    var minH = double.infinity;
    var maxH = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    var sx = 0.0;
    var sz = 0.0;
    for (final i in inliers) {
      final p = pool[i];
      final h = p.x * hx + p.z * hz;
      if (h < minH) minH = h;
      if (h > maxH) maxH = h;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
      sx += p.x;
      sz += p.z;
    }
    final width = maxH - minH;
    final height = maxY - minY;
    if (width < 0.7 || height < 0.5) continue;
    if (!ArPlacementPolicy.wallAreaQualifies(width, height)) continue;
    if (best != null && inliers.length <= best.inliers.length) continue;
    // Canonical hemisphere (+z, tie → +x): the cross-product sign depends
    // on which triple won, and the same wall must always report one yaw.
    var nx = nrm.x;
    var nz = nrm.z;
    if (nz < 0 || (nz == 0 && nx < 0)) {
      nx = -nx;
      nz = -nz;
    }
    final count = inliers.length;
    best = _Fit(
      yaw: math.atan2(nx, nz),
      inliers: inliers,
      cx: sx / count,
      // Y-bbox mid, not the inlier mean: a bottom-heavy cloud's mean sits
      // below the bbox and would build a rect whose bottom dips under
      // minY (pre-dipped paint).
      cy: (minY + maxY) / 2,
      cz: sz / count,
      width: width,
      height: height,
    );
  }
  return best;
}

class _Fit {
  _Fit({
    required this.yaw,
    required this.inliers,
    required this.cx,
    required this.cy,
    required this.cz,
    required this.width,
    required this.height,
  });

  final double yaw;

  final List<int> inliers;

  final double cx;

  final double cy;

  final double cz;

  final double width;

  final double height;
}

class _Cell {
  _Cell(this.ix, this.iz);

  final int ix;

  final int iz;

  int count = 0;

  double _sumY = 0;

  void add(double y) {
    count++;
    _sumY += y;
  }

  double get meanY => _sumY / count;
}

class _MaskCluster {
  _MaskCluster(this.cells, this.total, this.minIx, this.minIz);

  // Sorted by (ix, iz) — first entry is the lexicographic min.
  final List<_Cell> cells;

  final int total;

  final int minIx;

  final int minIz;
}

// A real object is seen two ticks running; a noise cell flickers once and
// must never punch a hole — the screen owns these track lists as state and
// feeds them through update/emit every tick. Pure functions: inputs are
// never mutated.
class MaskTrack {
  MaskTrack(
      {required this.id,
      required this.quad,
      required this.streak,
      this.holds = 0});

  final int id;

  // Last emitted geometry for this cluster.
  final PlaneQuad quad;

  // Consecutive ticks seen.
  final int streak;

  // Consecutive ticks missed while held.
  final int holds;
}

List<MaskTrack> updateMaskTracks({
  required List<MaskTrack> tracks,
  required List<PlaneQuad> curr,
  double matchDistM = 0.3,
  int maxHold = 1,
}) {
  final matched = List<bool>.filled(tracks.length, false);
  final out = <MaskTrack>[];
  var nextId = 0;
  for (final t in tracks) {
    if (t.id >= nextId) nextId = t.id + 1;
  }
  for (final q in curr) {
    var bestIdx = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < tracks.length; i++) {
      if (matched[i]) continue;
      final t = tracks[i];
      final dx = t.quad.center.x - q.center.x;
      final dz = t.quad.center.z - q.center.z;
      final d = math.sqrt(dx * dx + dz * dz);
      if (d > matchDistM) continue;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    if (bestIdx >= 0) {
      matched[bestIdx] = true;
      final t = tracks[bestIdx];
      out.add(MaskTrack(id: t.id, quad: q, streak: t.streak + 1, holds: 0));
    } else {
      out.add(MaskTrack(id: nextId++, quad: q, streak: 1, holds: 0));
    }
  }
  for (var i = 0; i < tracks.length; i++) {
    if (matched[i]) continue;
    final t = tracks[i];
    final holds = t.holds + 1;
    if (holds > maxHold) continue;
    out.add(MaskTrack(id: t.id, quad: t.quad, streak: t.streak, holds: holds));
  }
  return out;
}

List<PlaneQuad> emitMaskTracks(List<MaskTrack> tracks,
    {int emitStreak = 2, int maxEmit = 14}) {
  final kept = [
    for (final t in tracks)
      if (t.streak >= emitStreak) t,
  ];
  kept.sort((a, b) {
    final areaA = a.quad.extentX * a.quad.extentZ;
    final areaB = b.quad.extentX * b.quad.extentZ;
    if (areaA != areaB) return areaB.compareTo(areaA);
    final cx = a.quad.center.x.compareTo(b.quad.center.x);
    if (cx != 0) return cx;
    return a.quad.center.z.compareTo(b.quad.center.z);
  });
  return [for (final t in kept.take(maxEmit)) t.quad];
}

// RANSAC re-fits teleport every tick; tracks keep one stable wall id for
// memory ingest and smooth slow growth (α 0.35) while damping jitter.
// Same pure-function contract as the mask tracks — the screen keeps the
// list as state.
class WallTrack {
  WallTrack({
    required this.plane,
    required this.streak,
    this.holds = 0,
    this.originCamera,
    this.confirmed = false,
  });

  final ARPlaneInfo plane;

  final int streak;

  final int holds;

  // Camera XZ at first sighting — the two-view gate's anchor. Null (no
  // pose yet) keeps legacy emit behavior for that track.
  final Vector3? originCamera;

  // Set once the camera has moved ≥0.25 m since mint: two views of the
  // same surface, proof the fit was not a single-view phantom.
  final bool confirmed;
}

List<WallTrack> updateWallTracks({
  required List<WallTrack> tracks,
  required List<ARPlaneInfo> curr,
  double matchDistM = 0.5,
  double maxYawDelta = 0.35,
  int maxHold = 30,
  Vector3? cameraPos,
}) {
  final matched = List<bool>.filled(tracks.length, false);
  final matchOf = List<int>.filled(curr.length, -1);
  for (var q = 0; q < curr.length; q++) {
    final p = curr[q];
    var bestIdx = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < tracks.length; i++) {
      if (matched[i]) continue;
      final t = tracks[i];
      final dx = t.plane.centerX - p.centerX;
      final dz = t.plane.centerZ - p.centerZ;
      final d = math.sqrt(dx * dx + dz * dz);
      if (d > matchDistM) continue;
      if (_wrapPi(t.plane.yaw - p.yaw).abs() > maxYawDelta) continue;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    if (bestIdx >= 0) {
      matched[bestIdx] = true;
      matchOf[q] = bestIdx;
    }
  }
  // Ids that survive into the output from existing tracks: matched ones
  // (inherited) plus held ones that won't be dropped this tick.
  final usedIds = <int>{};
  var maxId = -1;
  for (var i = 0; i < tracks.length; i++) {
    final id = tracks[i].plane.id;
    if (id > maxId) maxId = id;
    if (matched[i] || tracks[i].holds + 1 <= maxHold) usedIds.add(id);
  }
  final out = <WallTrack>[];
  for (var q = 0; q < curr.length; q++) {
    final p = curr[q];
    final mi = matchOf[q];
    if (mi >= 0) {
      final prev = tracks[mi];
      final origin = prev.originCamera;
      var confirmed = prev.confirmed;
      if (!confirmed && origin != null && cameraPos != null) {
        final ox = origin.x - cameraPos.x;
        final oz = origin.z - cameraPos.z;
        confirmed = math.sqrt(ox * ox + oz * oz) >= 0.25;
      }
      out.add(WallTrack(
        plane: _blendWall(prev.plane, p),
        streak: prev.streak + 1,
        holds: 0,
        originCamera: origin,
        confirmed: confirmed,
      ));
      continue;
    }
    var id = p.id;
    if (usedIds.contains(id)) {
      id = ++maxId;
    } else if (id > maxId) {
      maxId = id;
    }
    usedIds.add(id);
    out.add(WallTrack(
      plane: id == p.id ? p : _withId(p, id),
      streak: 1,
      holds: 0,
      originCamera: cameraPos,
    ));
  }
  for (var i = 0; i < tracks.length; i++) {
    if (matched[i]) continue;
    final t = tracks[i];
    final holds = t.holds + 1;
    if (holds > maxHold) continue;
    out.add(WallTrack(
      plane: t.plane,
      streak: t.streak,
      holds: holds,
      originCamera: t.originCamera,
      confirmed: t.confirmed,
    ));
  }
  return out;
}

List<ARPlaneInfo> emitWallTracks(
  List<WallTrack> tracks, {
  int emitStreak = 2,
  // A room routinely holds four walls plus corner fragments; with 3 slots
  // the sort (streak desc) let never-decaying held tracks crowd a fresh
  // fragment out of paint indefinitely.
  int maxEmit = 6,
  // Paint rides the whole retention window (maxHold 30): a wall is static,
  // so the geometry stays correct while depth points are away — and a
  // shorter grace read as "fragment vanished, needs a rescan".
  int maxEmitHolds = 30,
}) {
  final kept = [
    for (final t in tracks)
      if (t.streak >= emitStreak &&
          t.holds <= maxEmitHolds &&
          // Two-view gate: a track minted with a pose must confirm (the
          // camera moved ≥0.25 m since mint) or ride the ≥4 streak
          // fallback — a single-view phantom never paints. Tracks minted
          // without a pose keep legacy behavior.
          (t.originCamera == null || t.confirmed || t.streak >= 4) &&
          ArPlacementPolicy.wallAreaQualifies(
              t.plane.extentX, t.plane.extentZ))
        t,
  ];
  kept.sort((a, b) {
    final s = b.streak.compareTo(a.streak);
    if (s != 0) return s;
    return b.plane.extentX.compareTo(a.plane.extentX);
  });
  return [for (final t in kept.take(maxEmit)) t.plane];
}

// Geometry glides toward the fresh fit at α 0.35 so a re-fit's jump is
// damped; the id never changes (memory ingest keys on it).
ARPlaneInfo _blendWall(ARPlaneInfo old, ARPlaneInfo fresh) {
  const a = 0.35;
  return ARPlaneInfo(
    id: old.id,
    planeType: fresh.planeType,
    centerX: old.centerX + (fresh.centerX - old.centerX) * a,
    centerY: old.centerY + (fresh.centerY - old.centerY) * a,
    centerZ: old.centerZ + (fresh.centerZ - old.centerZ) * a,
    extentX: old.extentX + (fresh.extentX - old.extentX) * a,
    extentZ: old.extentZ + (fresh.extentZ - old.extentZ) * a,
    yaw: old.yaw + _wrapPi(fresh.yaw - old.yaw) * a,
    polygon: fresh.polygon,
    fresh: fresh.fresh,
    tracking: fresh.tracking,
    subsumed: fresh.subsumed,
  );
}

ARPlaneInfo _withId(ARPlaneInfo p, int id) => ARPlaneInfo(
      id: id,
      planeType: p.planeType,
      centerX: p.centerX,
      centerY: p.centerY,
      centerZ: p.centerZ,
      extentX: p.extentX,
      extentZ: p.extentZ,
      yaw: p.yaw,
      polygon: p.polygon,
      fresh: p.fresh,
      tracking: p.tracking,
      subsumed: p.subsumed,
    );

double _wrapPi(double angle) {
  var a = angle % (2 * math.pi);
  if (a > math.pi) a -= 2 * math.pi;
  if (a < -math.pi) a += 2 * math.pi;
  return a;
}
