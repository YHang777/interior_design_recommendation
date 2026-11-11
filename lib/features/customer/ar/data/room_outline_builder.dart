import 'dart:math' as math;
import 'dart:ui';

import 'plane_overlay_math.dart';

// AR wall quads → a closed room outline in planner coords (cm, y grows
// south). Chains detected runs into a ring, seals openings up to a doorway
// wide, and normalises the bbox to the origin; a gap wider than that (an
// unscanned wall) fails instead of exporting a wrong shape.

class RoomOutline {
  const RoomOutline({
    required this.walls,
    required this.widthCm,
    required this.heightCm,
  });

  final List<Offset> walls;

  final double widthCm;

  final double heightCm;
}

RoomOutline? buildRoomOutline(
  List<PlaneQuad> wallQuads, {
  double minSegmentM = 0.3,
  double mergeAngleRad = 0.25,
  double mergeOffsetM = 0.35,
  double mergeGapM = 0.6,
  double chainTolM = 1.0,
  double sealGapM = 2.2,
}) {
  final segs = <_Seg>[];
  for (final q in wallQuads) {
    if (!q.vertical) continue;
    final s = _segmentOf(q);
    if (s != null && s.length >= minSegmentM) segs.add(s);
  }
  if (segs.length < 3) return null;
  final merged = _mergeCollinear(
    segs,
    angleRad: mergeAngleRad,
    offsetM: mergeOffsetM,
    gapM: mergeGapM,
  );
  final ring = _chainRing(merged, chainTolM: chainTolM, sealGapM: sealGapM);
  if (ring == null || ring.length < 3) return null;
  return _toOutline(ring);
}

class _Seg {
  _Seg(this.a, this.b);

  final Offset a;

  final Offset b;

  double get length => (b - a).distance;

  Offset get dir {
    final d = b - a;
    final n = d.distance;
    return n < 1e-9 ? Offset.zero : Offset(d.dx / n, d.dy / n);
  }
}

// Footprint of one wall quad on the XZ plane: both the fitted rectangle and
// an ARCore outline lie in the plane through the center spanned by the yaw
// direction, so the extremes along that direction are the run's ends.
_Seg? _segmentOf(PlaneQuad q) {
  final pts = planeQuadCorners(q);
  if (pts.length < 2) return null;
  final c = q.center;
  final ux = math.cos(q.yaw);
  final uz = -math.sin(q.yaw);
  var tMin = double.infinity;
  var tMax = double.negativeInfinity;
  for (final p in pts) {
    final t = (p.x - c.x) * ux + (p.z - c.z) * uz;
    if (t < tMin) tMin = t;
    if (t > tMax) tMax = t;
  }
  if (!tMin.isFinite || tMax - tMin < 1e-6) return null;
  return _Seg(
    Offset(c.x + ux * tMin, c.z + uz * tMin),
    Offset(c.x + ux * tMax, c.z + uz * tMax),
  );
}

// ARCore reports one physical wall as several patchwork fragments — the ring
// walk below connects endpoints, so near-collinear neighbours would become
// bogus corners. Fold them into single runs first.
List<_Seg> _mergeCollinear(
  List<_Seg> input, {
  required double angleRad,
  required double offsetM,
  required double gapM,
}) {
  final list = List<_Seg>.of(input);
  final cosMin = math.cos(angleRad);
  var merged = true;
  while (merged) {
    merged = false;
    search:
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final a = list[i];
        final b = list[j];
        final da = a.dir;
        final db = b.dir;
        if (da == Offset.zero || db == Offset.zero) continue;
        if ((da.dx * db.dx + da.dy * db.dy).abs() < cosMin) continue;
        double along(Offset p) =>
            (p.dx - a.a.dx) * da.dx + (p.dy - a.a.dy) * da.dy;
        double perp(Offset p) =>
            ((p.dx - a.a.dx) * da.dy - (p.dy - a.a.dy) * da.dx).abs();
        if (perp(b.a) > offsetM || perp(b.b) > offsetM) continue;
        final b0 = along(b.a);
        final b1 = along(b.b);
        final loB = math.min(b0, b1);
        final hiB = math.max(b0, b1);
        final gap = loB > a.length
            ? loB - a.length
            : (hiB < 0.0 ? -hiB : 0.0);
        if (gap > gapM) continue;
        list[i] = _Seg(
          a.a + da * math.min(0.0, loB),
          a.a + da * math.max(a.length, hiB),
        );
        list.removeAt(j);
        merged = true;
        break search;
      }
    }
  }
  return list;
}

// Where two wall lines should meet: their intersection when the lines are
// far enough from parallel for it to be stable and near enough to both ends
// to be the real corner, else the midpoint of the two candidate ends (the
// collinear case — a doorway gap closes straight across).
Offset _junction(Offset p, Offset dp, Offset q, Offset dq, double tol) {
  final cross = dp.dx * dq.dy - dp.dy * dq.dx;
  if (cross.abs() > 0.34) {
    final t = ((q.dx - p.dx) * dq.dy - (q.dy - p.dy) * dq.dx) / cross;
    final ip = Offset(p.dx + dp.dx * t, p.dy + dp.dy * t);
    if ((ip - p).distance <= tol && (ip - q).distance <= tol) return ip;
  }
  return Offset((p.dx + q.dx) / 2, (p.dy + q.dy) / 2);
}

// Greedily walk segments into a ring from the longest run outward, always
// taking the nearest endpoint within the tolerance; stop as soon as the two
// open ends meet (strays and hallway walls past that never join) and seal
// the remaining gap when it reads as an opening rather than a lost wall.
List<Offset>? _chainRing(List<_Seg> segs,
    {required double chainTolM, required double sealGapM}) {
  if (segs.length < 3) return null;
  var startIdx = 0;
  for (var i = 1; i < segs.length; i++) {
    if (segs[i].length > segs[startIdx].length) startIdx = i;
  }
  final used = List<bool>.filled(segs.length, false);
  used[startIdx] = true;
  final chain = <_Seg>[segs[startIdx]];

  while (true) {
    if (chain.length >= 3 &&
        (chain.last.b - chain.first.a).distance <= chainTolM) {
      break;
    }
    var bestI = -1;
    var bestFront = true;
    var bestAtA = true;
    var bestD = double.infinity;
    for (var i = 0; i < segs.length; i++) {
      if (used[i]) continue;
      final s = segs[i];
      void consider({required bool front, required bool atA, required double d}) {
        if (d <= chainTolM && d < bestD) {
          bestI = i;
          bestFront = front;
          bestAtA = atA;
          bestD = d;
        }
      }

      consider(front: true, atA: true, d: (s.a - chain.last.b).distance);
      consider(front: true, atA: false, d: (s.b - chain.last.b).distance);
      consider(front: false, atA: true, d: (s.a - chain.first.a).distance);
      consider(front: false, atA: false, d: (s.b - chain.first.a).distance);
    }
    if (bestI < 0) break;

    final s = segs[bestI];
    used[bestI] = true;
    final end = bestFront ? chain.last.b : chain.first.a;
    final endDir = bestFront ? chain.last.dir : chain.first.dir;
    final near = bestAtA ? s.a : s.b;
    final far = bestAtA ? s.b : s.a;
    final j = _junction(end, endDir, near, s.dir, chainTolM);
    if (bestFront) {
      chain[chain.length - 1] = _Seg(chain.last.a, j);
      chain.add(_Seg(j, far));
    } else {
      chain[0] = _Seg(j, chain.first.b);
      chain.insert(0, _Seg(far, j));
    }
  }

  if (chain.length < 3) return null;
  final front = chain.last.b;
  final back = chain.first.a;
  if ((front - back).distance > sealGapM) return null;
  final j = _junction(
      front, chain.last.dir, back, chain.first.dir, math.max(chainTolM, sealGapM));
  chain[chain.length - 1] = _Seg(chain.last.a, j);
  chain[0] = _Seg(j, chain.first.b);
  return [
    chain.first.a,
    for (var i = 0; i < chain.length - 1; i++) chain[i].b,
  ];
}

// Normalise the world ring to the origin and to centimetres the planner
// already speaks; degenerate footprints and slivers below a square metre
// are not rooms.
RoomOutline? _toOutline(List<Offset> ring) {
  var minX = ring.first.dx;
  var maxX = ring.first.dx;
  var minZ = ring.first.dy;
  var maxZ = ring.first.dy;
  for (final p in ring) {
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minZ) minZ = p.dy;
    if (p.dy > maxZ) maxZ = p.dy;
  }
  final widthM = maxX - minX;
  final heightM = maxZ - minZ;
  if (widthM < 0.8 || heightM < 0.8) return null;
  final walls = <Offset>[];
  for (final p in ring) {
    final c = Offset((p.dx - minX) * 100, (p.dy - minZ) * 100);
    if (walls.isNotEmpty && (c - walls.last).distance < 6) continue;
    walls.add(c);
  }
  if (walls.length >= 2 && (walls.first - walls.last).distance < 6) {
    walls.removeLast();
  }
  if (walls.length < 3) return null;
  var sum = 0.0;
  for (var i = 0; i < walls.length; i++) {
    final a = walls[i];
    final b = walls[(i + 1) % walls.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  if (sum.abs() / 2 < 10000) return null;
  return RoomOutline(
    walls: walls,
    widthCm: widthM * 100,
    heightCm: heightM * 100,
  );
}
