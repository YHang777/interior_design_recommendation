import 'dart:math';

import 'package:flutter/material.dart' show Offset, Rect;

import 'room_fit.dart' show pointInPolygon;

// ── shell geometry ──
// RoomDesign.walls is the room's INNER face as a closed corner ring (cm).
// The 3D shell extrudes wall boxes OUTWARD from that ring, so the interior
// footprint furniture may use is exactly the polygon the planner validates.
// Outer faces are miter-joined so corners stay watertight from outside.

const double kShellWallThicknessCm = 10;
const double kShellWallHeightCm = 270; // matches RoomFinishCatalog.wallHeightM
const double kShellBaseboardHeightCm = 8;
const double kShellBaseboardProudCm = 1.5;
const double kShellCutawayHeightCm = 120;

class WallSegment {
  const WallSegment({
    required this.a,
    required this.b,
    required this.outerA,
    required this.outerB,
    required this.outward,
  });

  final Offset a;
  final Offset b;
  final Offset outerA;
  final Offset outerB;
  final Offset outward;

  List<Offset> get planCorners => [a, b, outerB, outerA];
}

class ShellGeometry {
  ShellGeometry._({
    required this.ringCm,
    required this.outerRingCm,
    required this.baseboardInnerRingCm,
    required this.wallSegments,
    required this.floorTriangles,
    required this.floorAreaCm2,
    required this.wallThicknessCm,
    required this.wallHeightCm,
    required this.baseboardHeightCm,
    required this.baseboardProudCm,
  });

  factory ShellGeometry({
    required List<Offset> ringCm,
    double wallThicknessCm = kShellWallThicknessCm,
    double wallHeightCm = kShellWallHeightCm,
    double baseboardHeightCm = kShellBaseboardHeightCm,
    double baseboardProudCm = kShellBaseboardProudCm,
  }) {
    final ring = List<Offset>.of(ringCm);
    if (ring.length < 3) {
      return ShellGeometry._(
        ringCm: ring,
        outerRingCm: List<Offset>.of(ring),
        baseboardInnerRingCm: List<Offset>.of(ring),
        wallSegments: const [],
        floorTriangles: const [],
        floorAreaCm2: 0,
        wallThicknessCm: wallThicknessCm,
        wallHeightCm: wallHeightCm,
        baseboardHeightCm: baseboardHeightCm,
        baseboardProudCm: baseboardProudCm,
      );
    }
    final outer = offsetRing(ring, wallThicknessCm);
    final baseInner = offsetRing(ring, -baseboardProudCm);
    final segments = <WallSegment>[
      for (var i = 0; i < ring.length; i++)
        WallSegment(
          a: ring[i],
          b: ring[(i + 1) % ring.length],
          outerA: outer[i],
          outerB: outer[(i + 1) % ring.length],
          outward: _outwardNormal(
              ring[i], ring[(i + 1) % ring.length], ring),
        ),
    ];
    final tris = triangulateRing(ring);
    return ShellGeometry._(
      ringCm: ring,
      outerRingCm: outer,
      baseboardInnerRingCm: baseInner,
      wallSegments: segments,
      floorTriangles: tris,
      floorAreaCm2: _signedArea(ring).abs(),
      wallThicknessCm: wallThicknessCm,
      wallHeightCm: wallHeightCm,
      baseboardHeightCm: baseboardHeightCm,
      baseboardProudCm: baseboardProudCm,
    );
  }

  final List<Offset> ringCm;
  final List<Offset> outerRingCm;
  final List<Offset> baseboardInnerRingCm;
  final List<WallSegment> wallSegments;
  final List<List<Offset>> floorTriangles;
  final double floorAreaCm2;
  final double wallThicknessCm;
  final double wallHeightCm;
  final double baseboardHeightCm;
  final double baseboardProudCm;

  // [a, b, innerB, innerA] per wall run — the trim sits ON the inner face,
  // proud into the room.
  List<List<Offset>> get baseboardPlanQuads => [
        for (var i = 0; i < ringCm.length; i++)
          [
            ringCm[i],
            ringCm[(i + 1) % ringCm.length],
            baseboardInnerRingCm[(i + 1) % ringCm.length],
            baseboardInnerRingCm[i],
          ],
      ];

  Rect get boundsCm {
    final pts = [...ringCm, ...outerRingCm];
    var minX = pts.first.dx, minY = pts.first.dy;
    var maxX = minX, maxY = minY;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

// ── dollhouse cutaway ──
// Walls between the camera and the room drop to kShellCutawayHeightCm so the
// orbit view sees over them; walls on the far side keep full height. The same
// mask feeds generation and the bridge cache key (a discrete bitstring — the
// camera may move freely inside one mask).

List<Offset> shellRing({
  required List<Offset> wallsCm,
  required double roomWCm,
  required double roomHCm,
}) =>
    wallsCm.length >= 3
        ? List<Offset>.of(wallsCm)
        : [
            Offset.zero,
            Offset(roomWCm, 0),
            Offset(roomWCm, roomHCm),
            Offset(0, roomHCm),
          ];

/// Cut[ShellGeometry.wallSegments] index i when the camera sits on that
/// wall's outer side (the wall would block the view).
List<bool> cutawayMask(ShellGeometry shell, Offset cameraCm) => [
      for (final seg in shell.wallSegments)
        seg.outward.dx * (cameraCm.dx - (seg.a.dx + seg.b.dx) / 2) +
                seg.outward.dy * (cameraCm.dy - (seg.a.dy + seg.b.dy) / 2) >
            0,
    ];

String cutawaySignature(ShellGeometry shell, Offset cameraCm) =>
    cutawayMask(shell, cameraCm).map((cut) => cut ? '1' : '0').join();

// ── ring offsetting ──

// Positive delta = outward (away from the room interior), negative = into
// the room. Vertices miter-join (intersection of adjacent offset lines) so
// wall corners and trim corners meet without notches.
List<Offset> offsetRing(List<Offset> ringCm, double deltaCm) {
  final n = ringCm.length;
  if (n < 3) return List<Offset>.of(ringCm);
  final normals = <Offset>[
    for (var i = 0; i < n; i++)
      _outwardNormal(ringCm[i], ringCm[(i + 1) % n], ringCm),
  ];
  final out = <Offset>[];
  for (var i = 0; i < n; i++) {
    final prev = (i - 1 + n) % n;
    final a = ringCm[i] + normals[prev] * deltaCm;
    final b = ringCm[i] + normals[i] * deltaCm;
    final dPrev = _unit(ringCm[i] - ringCm[prev]);
    final dCur = _unit(ringCm[(i + 1) % n] - ringCm[i]);
    out.add(_lineIntersect(a, dPrev, b, dCur) ?? b);
  }
  return out;
}

Offset _outwardNormal(Offset a, Offset b, List<Offset> ring) {
  final d = b - a;
  final len = d.distance;
  if (len == 0) return Offset.zero;
  var n = Offset(d.dy / len, -d.dx / len);
  final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  // Probe just off the midpoint: landing inside means n points inward.
  final probe = mid + n * max(2.0, len * 0.02);
  if (pointInPolygon(probe, ring)) n = -n;
  return n;
}

Offset? _lineIntersect(Offset p1, Offset d1, Offset p2, Offset d2) {
  final denom = d1.dx * d2.dy - d1.dy * d2.dx;
  if (denom.abs() < 1e-9) return null;
  final t = ((p2.dx - p1.dx) * d2.dy - (p2.dy - p1.dy) * d2.dx) / denom;
  return p1 + d1 * t;
}

Offset _unit(Offset v) {
  final len = v.distance;
  return len == 0 ? Offset.zero : v / len;
}

// ── floor triangulation ──

// Ear clipping for simple rings (convex or concave, e.g. L-shapes) — the
// shell floor is one polygon fan per triangle, ready for GLB emission.
List<List<Offset>> triangulateRing(List<Offset> ringCm) {
  if (ringCm.length < 3) return const [];
  var pts = List<Offset>.of(ringCm);
  if (_signedArea(pts) < 0) pts = pts.reversed.toList();
  final idx = [for (var i = 0; i < pts.length; i++) i];
  final tris = <List<Offset>>[];
  var guard = pts.length * pts.length + 8;
  while (idx.length > 3 && guard-- > 0) {
    var clipped = false;
    for (var i = 0; i < idx.length; i++) {
      final i0 = idx[(i - 1 + idx.length) % idx.length];
      final i1 = idx[i];
      final i2 = idx[(i + 1) % idx.length];
      final a = pts[i0];
      final b = pts[i1];
      final c = pts[i2];
      final cross = (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
      if (cross <= 0) continue;
      if (_anyRingPointInTriangle(pts, idx, i0, i1, i2)) continue;
      tris.add([a, b, c]);
      idx.removeAt(i);
      clipped = true;
      break;
    }
    if (!clipped) break;
  }
  if (idx.length == 3) {
    tris.add([pts[idx[0]], pts[idx[1]], pts[idx[2]]]);
  }
  return tris;
}

bool _anyRingPointInTriangle(
    List<Offset> pts, List<int> idx, int i0, int i1, int i2) {
  final a = pts[i0];
  final b = pts[i1];
  final c = pts[i2];
  for (final j in idx) {
    if (j == i0 || j == i1 || j == i2) continue;
    if (_pointInTriangle(pts[j], a, b, c)) return true;
  }
  return false;
}

bool _pointInTriangle(Offset p, Offset a, Offset b, Offset c) {
  double cross(Offset u, Offset v, Offset w) =>
      (v.dx - u.dx) * (w.dy - u.dy) - (v.dy - u.dy) * (w.dx - u.dx);
  final d1 = cross(a, b, p);
  final d2 = cross(b, c, p);
  final d3 = cross(c, a, p);
  final hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
  final hasPos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(hasNeg && hasPos);
}

double _signedArea(List<Offset> ring) {
  var sum = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum / 2;
}
