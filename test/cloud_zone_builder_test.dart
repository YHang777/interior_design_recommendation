import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:interior_design_recommendation/features/customer/ar/data/cloud_zone_builder.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_overlay_math.dart';

List<double> _flat(List<List<double>> pts) =>
    [for (final p in pts) ...p];

bool _hasHullCorner(PlaneQuad q, double x, double z) => q.polygon.any(
    (v) => (v.x - x).abs() < 1e-9 && (v.z - z).abs() < 1e-9);

PlaneQuad _maskQuad({double x = 0, double z = 1, double size = 0.3}) =>
    PlaneQuad(
      center: Vector3(x, 1.0, z),
      yaw: 0,
      extentX: size,
      extentZ: size,
      vertical: false,
      kind: PlaneQuadKind.floor,
    );

ARPlaneInfo _wall({
  int id = 900001,
  double cx = 0,
  double cy = 1,
  double cz = 2,
  double ex = 1.4,
  double ez = 1.2,
  double yaw = 0,
}) =>
    ARPlaneInfo(
      id: id,
      planeType: 2,
      centerX: cx,
      centerY: cy,
      centerZ: cz,
      extentX: ex,
      extentZ: ez,
      yaw: yaw,
    );

List<List<double>> _grid({
  required List<double> xs,
  required List<double> ys,
  required List<double> zs,
}) {
  final out = <List<double>>[];
  for (final x in xs) {
    for (final y in ys) {
      for (final z in zs) {
        out.add([x, y, z]);
      }
    }
  }
  return out;
}

void main() {
  group('obstacleMaskQuads', () {
    test('an L of wall points around an undetected corner never masks', () {
      // Device round 7: this shape hulled into a 2.8×2.75 m mask that
      // erased most of the painted floor and walls.
      final pts = <List<double>>[];
      for (var x = 0.05; x < 2.8; x += 0.1) {
        for (final y in [0.6, 1.0, 1.4]) {
          pts
            ..add([x, y, 0.05])
            ..add([x + 0.02, y, 0.1]);
        }
      }
      for (var z = 0.15; z < 2.8; z += 0.1) {
        for (final y in [0.6, 1.0, 1.4]) {
          pts
            ..add([0.05, y, z])
            ..add([0.1, y, z + 0.02]);
        }
      }
      expect(obstacleMaskQuads(points: _flat(pts), refY: 0), isEmpty);
    });

    test('a compact chair-sized object still masks', () {
      final pts = _grid(
        xs: [for (var x = 1.0; x < 1.5; x += 0.05) x],
        ys: [0.45, 0.8],
        zs: [for (var z = 1.0; z < 1.5; z += 0.05) z],
      );
      final quads = obstacleMaskQuads(points: _flat(pts), refY: 0);
      expect(quads, hasLength(1));
      expect(quads.single.extentX, lessThan(1.0));
    });

    test('three obstacle points in one cell → one quad at mean height', () {
      final quads = obstacleMaskQuads(
        points: _flat(const [
          [0.1, 1.0, 0.1],
          [0.2, 1.3, 0.2],
          [0.15, 1.1, 0.25],
        ]),
        refY: 0,
      );
      expect(quads, hasLength(1));
      final q = quads.single;
      expect(q.center.x, closeTo(0.15, 1e-12));
      expect(q.center.y, closeTo(1.1333333333333333, 1e-9));
      expect(q.center.z, closeTo(0.15, 1e-12));
      expect(q.extentX, 0.3);
      expect(q.extentZ, 0.3);
      expect(q.yaw, 0);
      expect(q.vertical, isFalse);
      expect(q.kind, PlaneQuadKind.floor);
      // The hull of one cell's four corners is the cell square itself.
      expect(q.polygon, hasLength(4));
      for (final expected in [
        (0.0, 0.0),
        (0.3, 0.0),
        (0.3, 0.3),
        (0.0, 0.3),
      ]) {
        expect(_hasHullCorner(q, expected.$1, expected.$2), isTrue,
            reason: 'missing hull corner $expected in ${q.polygon}');
      }
      // CCW winding in (x, z).
      var area2 = 0.0;
      for (var i = 0; i < q.polygon.length; i++) {
        final a = q.polygon[i];
        final b = q.polygon[(i + 1) % q.polygon.length];
        area2 += a.x * b.z - b.x * a.z;
      }
      expect(area2, greaterThan(0));
      for (final v in q.polygon) {
        expect(v.y, closeTo(q.center.y, 1e-12), reason: 'flat mask quad');
      }
    });

    test('two points in a cell mask nothing', () {
      final quads = obstacleMaskQuads(
        points: _flat(const [
          [0.1, 1.0, 0.1],
          [0.2, 1.3, 0.2],
        ]),
        refY: 0,
      );
      expect(quads, isEmpty);
    });

    test('floor-band, gap and too-high points are ignored', () {
      final quads = obstacleMaskQuads(
        points: _flat(const [
          [0.1, 0.1, 0.1],
          [0.2, 0.1, 0.2],
          [0.15, -0.05, 0.15],
          [0.1, 0.2, 0.1],
          [0.2, 0.2, 0.2],
          [0.15, 0.25, 0.15],
          [0.1, 2.5, 0.1],
          [0.2, 2.5, 0.2],
          [0.15, 2.5, 0.15],
        ]),
        refY: 0,
      );
      expect(quads, isEmpty);
    });

    test('a point just inside the obstacle band still masks', () {
      final quads = obstacleMaskQuads(
        points: _flat(const [
          [0.1, 0.26, 0.1],
          [0.2, 0.3, 0.2],
          [0.15, 0.4, 0.15],
        ]),
        refY: 0,
      );
      expect(quads, hasLength(1));
      expect(quads.single.center.y, closeTo(0.32, 1e-9));
    });

    test('cell edges bucket correctly, negatives included', () {
      // x=0.3 lands in cell ix=1 (floor(1.0)), x=0.29 in ix=0.
      final right = obstacleMaskQuads(
        points: _flat(const [
          [0.3, 1.0, 0.1],
          [0.3, 1.1, 0.1],
          [0.35, 1.2, 0.1],
        ]),
        refY: 0,
      );
      expect(right, hasLength(1));
      expect(right.single.center.x, closeTo(0.45, 1e-12));

      final left = obstacleMaskQuads(
        points: _flat(const [
          [0.29, 1.0, 0.1],
          [0.28, 1.1, 0.1],
          [0.25, 1.2, 0.1],
        ]),
        refY: 0,
      );
      expect(left, hasLength(1));
      expect(left.single.center.x, closeTo(0.15, 1e-12));

      final negative = obstacleMaskQuads(
        points: _flat(const [
          [-0.1, 1.0, 0.1],
          [-0.05, 1.1, 0.1],
          [-0.02, 1.2, 0.1],
        ]),
        refY: 0,
      );
      expect(negative, hasLength(1));
      expect(negative.single.center.x, closeTo(-0.15, 1e-12));
    });

    test('empty and malformed input never throw', () {
      expect(obstacleMaskQuads(points: const [], refY: 0), isEmpty);
      expect(
        obstacleMaskQuads(points: const [0.1, 1.0, 0.1, 0.2], refY: 0),
        isEmpty,
      );
      expect(
        obstacleMaskQuads(points: const [0.1, 1.0], refY: 0),
        isEmpty,
      );
    });

    test('diagonally adjacent cells merge into one hull', () {
      final quads = obstacleMaskQuads(
        points: _flat(const [
          // Cell (0, 0) and cell (1, 1) touch only at a corner — the
          // staircase case 8-connectivity must weld shut.
          [0.1, 1.0, 0.1],
          [0.2, 1.1, 0.2],
          [0.15, 1.2, 0.25],
          [0.4, 1.0, 0.4],
          [0.5, 1.1, 0.5],
          [0.45, 1.2, 0.45],
        ]),
        refY: 0,
      );
      expect(quads, hasLength(1),
          reason: 'diagonal cells are one 8-connected cluster');
      final q = quads.single;
      expect(q.extentX, closeTo(0.6, 1e-12));
      expect(q.extentZ, closeTo(0.6, 1e-12));
      expect(q.center.x, closeTo(0.3, 1e-12));
      expect(q.center.z, closeTo(0.3, 1e-12));
      expect(q.center.y, closeTo(1.1, 1e-9));
      // Hull over the corner POINTS: the shared corner chamfers out.
      expect(q.polygon, hasLength(6));
      for (final expected in [
        (0.0, 0.0),
        (0.3, 0.0),
        (0.6, 0.3),
        (0.6, 0.6),
        (0.3, 0.6),
        (0.0, 0.3),
      ]) {
        expect(_hasHullCorner(q, expected.$1, expected.$2), isTrue,
            reason: 'missing hull corner $expected in ${q.polygon}');
      }
    });

    test('a cluster hugging a wall drops; a freestanding one survives', () {
      final wall = ARPlaneInfo(
        id: 1,
        planeType: 2,
        centerX: 0,
        centerY: 1,
        centerZ: 1.8,
        extentX: 4,
        extentZ: 2,
        yaw: 0,
      );
      // On-wall cells at iz=6 (center z 1.95 — exactly 0.15 m off the
      // plane, inside the hug band), three cells wide along the wall.
      final onWall = _flat([
        for (final ix in [0, 1, 2])
          for (var i = 0; i < 3; i++) [(ix + 0.5) * 0.3, 1.0, 1.85],
      ]);
      // Freestanding cell at iz=4 (center z 1.35): 0.45 m off the wall
      // plane and two cells away, so it never clusters with the wall.
      final freestanding = _flat([
        for (var i = 0; i < 3; i++) [0.15, 1.0, 1.4],
      ]);
      final all = [...onWall, ...freestanding];
      expect(obstacleMaskQuads(points: all, refY: 0), hasLength(2));
      final kept = obstacleMaskQuads(points: all, refY: 0, walls: [wall]);
      expect(kept, hasLength(1));
      final q = kept.single;
      expect(q.center.x, closeTo(0.15, 1e-12));
      expect(q.center.z, closeTo(1.35, 1e-12),
          reason: 'the freestanding cluster masks alone');
    });

    test('the wall-hug exemption is masking, not classification', () {
      // One cell centred at (0.75, 1.95): iz=6/dz=0.15 sits exactly on the
      // hug band, so only extentX (the reach) decides.
      final pts = _flat([
        for (var i = 0; i < 3; i++) [0.75, 1.0, 1.95],
      ]);
      // reach = 1.0/2 + 0.25 = 0.75 covers cx 0.75 → exempted.
      final exempted = obstacleMaskQuads(
          points: pts, refY: 0, walls: [_wall(cz: 1.8, ex: 1.0, ez: 1.0)]);
      expect(exempted, isEmpty);

      // A sub-m² fragment still exempts: reach passes (ex=1.0 → 0.75) but
      // area 1.0×0.99 = 0.99 m² is under the shared gate. Its feet must
      // keep the floor painted — wall classification stays gated at the
      // five sites that paint/score/classify (overlay, RANSAC admit,
      // emit, coach, placement), not at the mask exemption.
      final kept = obstacleMaskQuads(
          points: pts, refY: 0, walls: [_wall(cz: 1.8, ex: 1.0, ez: 0.99)]);
      expect(kept, isEmpty);
    });

    test('more than 14 clusters keeps the biggest, deterministically', () {
      // 15 isolated cells (every other column → never 8-connected),
      // counts 3..17 so the smallest cluster must be capped off.
      final pts = <double>[];
      for (var k = 0; k < 15; k++) {
        final ix = 2 * k;
        for (var i = 0; i < 3 + k; i++) {
          pts.addAll([(ix + 0.5) * 0.3, 1.0, 0.15]);
        }
      }
      final quads = obstacleMaskQuads(points: pts, refY: 0);
      expect(quads, hasLength(14));
      final xs = [for (final q in quads) q.center.x];
      final expected = [
        for (var k = 14; k >= 1; k--) (2 * k + 0.5) * 0.3,
      ];
      for (var i = 0; i < xs.length; i++) {
        expect(xs[i], closeTo(expected[i], 1e-9), reason: 'slot $i');
      }
      final again = obstacleMaskQuads(points: pts, refY: 0);
      expect([for (final q in again) q.center.x], xs,
          reason: 'identical input → identical output');
    });

    test('equal-size clusters break ties by min (ix, iz)', () {
      final pts = <double>[];
      for (var k = 0; k < 15; k++) {
        final ix = 2 * k;
        for (var i = 0; i < 3; i++) {
          pts.addAll([(ix + 0.5) * 0.3, 1.0, 0.15]);
        }
      }
      final quads = obstacleMaskQuads(points: pts, refY: 0);
      expect(quads, hasLength(14));
      expect(quads.first.center.x, closeTo(0.15, 1e-9),
          reason: 'ties keep ascending min ix');
      expect(quads.last.center.x, closeTo((2 * 13 + 0.5) * 0.3, 1e-9));
      expect(
        quads.any((q) => (q.center.x - (2 * 14 + 0.5) * 0.3).abs() < 1e-9),
        isFalse,
        reason: 'the highest-ix cluster is the one capped off',
      );
    });

    test('open-floor noise cell (5 elevated + 200 floor) is rejected', () {
      final pts = <double>[];
      for (var i = 0; i < 5; i++) {
        pts.addAll([0.1, 0.30, 0.1]);
      }
      for (var i = 0; i < 200; i++) {
        pts.addAll([0.1, 0.0, 0.1]);
      }
      expect(obstacleMaskQuads(points: pts, refY: 0), isEmpty,
          reason: 'floor-dominant evidence is a noise tail, not an object');
    });

    test('object cell (50 elevated, 0 floor) is kept', () {
      final pts = <double>[];
      for (var i = 0; i < 50; i++) {
        pts.addAll([0.1, 0.5, 0.1]);
      }
      expect(obstacleMaskQuads(points: pts, refY: 0), hasLength(1));
    });

    test('mixed edge cell (50 elevated, 40 floor) is kept', () {
      // 40 ≤ 3×50, so the floor is not dominant — an object edge with some
      // floor visible underneath still masks.
      final pts = <double>[];
      for (var i = 0; i < 50; i++) {
        pts.addAll([0.1, 0.5, 0.1]);
      }
      for (var i = 0; i < 40; i++) {
        pts.addAll([0.1, 0.05, 0.1]);
      }
      expect(obstacleMaskQuads(points: pts, refY: 0), hasLength(1));
    });

    test('floor-evidence points do not count toward the dense ≥3 gate', () {
      final pts = <double>[];
      for (var i = 0; i < 2; i++) {
        pts.addAll([0.1, 0.5, 0.1]);
      }
      for (var i = 0; i < 100; i++) {
        pts.addAll([0.1, 0.0, 0.1]);
      }
      expect(obstacleMaskQuads(points: pts, refY: 0), isEmpty,
          reason: 'floor points must never make a cell look like an object');
    });
  });

  group('floorProbeCandidate', () {
    test('p20 of the band with eight points', () {
      final ys = [0.0, 0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07];
      final pts = _flat([
        for (var i = 0; i < ys.length; i++) [i * 0.01, ys[i], 0.0],
      ]);
      expect(floorProbeCandidate(points: pts, refY: 0), closeTo(0.01, 1e-12));
    });

    test('upward contamination never drags the reading off the floor', () {
      // Ten floor points plus ten wall-base points inside the band: a
      // median landed between them and agreed with a wrong floorY forever.
      final pts = _flat([
        for (var i = 0; i < 10; i++) [i * 0.01, 0.0, 0.0],
        for (var i = 0; i < 10; i++) [0.5 + i * 0.01, 0.12, 0.0],
      ]);
      expect(floorProbeCandidate(points: pts, refY: 0), closeTo(0.0, 1e-12));
    });

    test('reads the floor under a too-high estimate', () {
      // floorY locked 0.15 high: the band must reach down to the real
      // floor, and in-band wall points above it must not win the percentile.
      final pts = _flat([
        for (var i = 0; i < 10; i++) [i * 0.01, 0.0, 0.0],
        for (var i = 0; i < 10; i++) [0.5 + i * 0.01, 0.20, 0.0],
      ]);
      expect(floorProbeCandidate(points: pts, refY: 0.15), closeTo(0.0, 1e-12));
    });

    test('null below eight in-band points', () {
      final seven = _flat([
        for (var i = 0; i < 7; i++) [i * 0.01, i * 0.01, 0.0],
      ]);
      expect(floorProbeCandidate(points: seven, refY: 0), isNull);
    });

    test('points outside the band do not count', () {
      final pts = _flat([
        for (var i = 0; i < 7; i++) [i * 0.01, i * 0.01, 0.0],
        [0.0, 0.5, 0.0],
        [0.1, 0.6, 0.0],
        [0.2, -0.7, 0.0],
      ]);
      expect(floorProbeCandidate(points: pts, refY: 0), isNull);
    });
  });

  group('fitWallPlanes', () {
    // One RANSAC wall needs ≥30 inliers and ≥0.7×0.5 m spans.
    final wallA = _grid(
      xs: const [0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4],
      ys: const [0.3, 0.55, 0.8, 1.05, 1.3, 1.55],
      zs: const [2.0],
    );
    final wallB = _grid(
      xs: const [2.0],
      ys: const [0.3, 0.55, 0.8, 1.05, 1.3, 1.55],
      zs: const [0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4],
    );

    test('synthetic vertical wall → one plane with yaw/extents', () {
      final planes =
          fitWallPlanes(points: _flat(wallA), refY: 0);
      expect(planes, hasLength(1));
      final p = planes.single;
      expect(p.id, 900001);
      expect(p.planeType, 2);
      // Canonical normal (0,0,1) → yaw 0, width along world X.
      expect(p.yaw, closeTo(0, 1e-12));
      expect(p.extentX, closeTo(1.4, 1e-9));
      expect(p.extentZ, closeTo(1.25, 1e-9));
      expect(p.centerX, closeTo(0.7, 1e-9));
      expect(p.centerY, closeTo(0.925, 1e-9));
      expect(p.centerZ, closeTo(2.0, 1e-9));
      expect(p.subsumed, isFalse);
      expect(p.polygon, isEmpty);
    });

    test('a sub-m² vertical fit is rejected by the area gate alone', () {
      // Dyadic grid: 8 xs (width 0.875) × 5 ys (height 1.0) = 0.875 m².
      // That clears the old 0.7×0.5 = 0.35 m² admission gate, so ONLY the
      // shared 1.0 m² wall-area gate rejects it.
      final small = _grid(
        xs: const [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875],
        ys: const [0.25, 0.5, 0.75, 1.0, 1.25],
        zs: const [2.0],
      );
      expect(fitWallPlanes(points: _flat(small), refY: 0), isEmpty);
    });

    test('a 1.0 m² vertical fit is admitted', () {
      // Same grid with 9 xs → width 1.0, height 1.0 → exactly 1.0 m².
      final exact = _grid(
        xs: const [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0],
        ys: const [0.25, 0.5, 0.75, 1.0, 1.25],
        zs: const [2.0],
      );
      final planes = fitWallPlanes(points: _flat(exact), refY: 0);
      expect(planes, hasLength(1));
      expect(planes.single.extentX, closeTo(1.0, 1e-9));
      expect(planes.single.extentZ, closeTo(1.0, 1e-9));
    });

    test('floor point cluster yields no wall', () {
      final floorPts = _flat(_grid(
        xs: const [0, 0.3, 0.6, 0.9],
        ys: const [0, 0.05, 0.1],
        zs: const [0, 0.3, 0.6, 0.9, 1.2],
      ));
      expect(fitWallPlanes(points: floorPts, refY: 0), isEmpty);
    });

    test('two perpendicular walls → two planes', () {
      final planes = fitWallPlanes(
        points: _flat([...wallA, ...wallB]),
        refY: 0,
      );
      expect(planes, hasLength(2));
      final za = planes.firstWhere((p) => (p.centerZ - 2.0).abs() < 1e-9);
      final xb = planes.firstWhere((p) => (p.centerX - 2.0).abs() < 1e-9);
      expect(za.yaw, closeTo(0, 1e-12));
      expect(za.extentX, closeTo(1.4, 1e-9));
      expect(za.extentZ, closeTo(1.25, 1e-9));
      // Canonical normal (1,0,0) → yaw π/2, width along world Z.
      expect(xb.yaw, closeTo(math.pi / 2, 1e-12));
      expect(xb.extentX, closeTo(1.4, 1e-9));
      expect(xb.extentZ, closeTo(1.25, 1e-9));
      expect(
        {planes[0].id, planes[1].id},
        {900001, 900002},
      );
    });

    test('same input twice → identical output', () {
      final input = _flat([...wallA, ...wallB]);
      final a = fitWallPlanes(points: input, refY: 0);
      final b = fitWallPlanes(points: input, refY: 0);
      expect(
        [for (final p in a) p.toJson()],
        [for (final p in b) p.toJson()],
      );
    });

    test('bottom-heavy inliers put the rect bottom on minY', () {
      // Mean of the ys is 0.47, bbox mid is 0.925 — the old mean-based cy
      // built a rect whose bottom dipped under the true inlier minimum.
      final heavy = _grid(
        xs: const [0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4],
        ys: const [0.3, 0.31, 0.32, 0.33, 0.34, 0.35, 0.36, 0.37, 1.55],
        zs: const [2.0],
      );
      final planes = fitWallPlanes(points: _flat(heavy), refY: 0);
      expect(planes, hasLength(1));
      final p = planes.single;
      expect(p.centerY, closeTo(0.925, 1e-9),
          reason: 'Y-bbox mid, not the bottom-heavy inlier mean');
      expect(p.centerY - p.extentZ / 2, closeTo(0.3, 1e-9),
          reason: 'rect bottom sits exactly on the inlier minY');
    });

    List<List<double>> rotatedA(double rad) => [
          for (final p in wallA)
            [
              0.7 + (p[0] - 0.7) * math.cos(rad) - (p[2] - 2.0) * math.sin(rad),
              p[1],
              2.0 + (p[0] - 0.7) * math.sin(rad) + (p[2] - 2.0) * math.cos(rad),
            ],
        ];

    test('a same-place fit contradicting an existing wall is rejected', () {
      final existing = [_wall(id: 1, cx: 0.7, cy: 0.925, cz: 2.0, yaw: 0)];
      expect(
        fitWallPlanes(
            points: _flat(rotatedA(0.5)), refY: 0, existing: existing),
        isEmpty,
        reason: 'yawDiff 0.5 on the same surface is a grazing-pan phantom',
      );
    });

    test('the rotated control with no reference is accepted', () {
      expect(fitWallPlanes(points: _flat(rotatedA(0.5)), refY: 0),
          hasLength(1));
    });

    test('an existing wall 3 m off-plane does not reject the fit', () {
      final existing = [_wall(id: 1, cx: 0.7, cy: 0.925, cz: 5.0, yaw: 0)];
      expect(
        fitWallPlanes(
            points: _flat(rotatedA(0.5)), refY: 0, existing: existing),
        hasLength(1),
        reason: 'a parallel wall at another depth is not the same surface',
      );
    });

    test('same-surface fit noise (yawDiff 0.10) passes the gate', () {
      final existing = [_wall(id: 1, cx: 0.7, cy: 0.925, cz: 2.0, yaw: 0.10)];
      expect(
        fitWallPlanes(points: _flat(wallA), refY: 0, existing: existing),
        hasLength(1),
        reason: '≤0.15 rad is fit noise, not a contradiction',
      );
    });

    test('corner-region yaw noise (yawDiff 0.18) passes the gate', () {
      final existing = [_wall(id: 1, cx: 0.7, cy: 0.925, cz: 2.0, yaw: 0.18)];
      expect(
        fitWallPlanes(points: _flat(wallA), refY: 0, existing: existing),
        hasLength(1),
        reason: 'ARCore yaw wobbles hardest near corners; ≤0.20 stays noise',
      );
    });

    test('a same-place fit past the noise band is still rejected', () {
      expect(
        wallFitConsistentWith(
          _wall(id: 900001, cx: 0.7, cy: 0.925, cz: 2.0, yaw: 0.30),
          [_wall(id: 1, cx: 0.7, cy: 0.925, cz: 2.0, yaw: 0)],
        ),
        isFalse,
        reason: '0.30 rad on the same surface is beyond fit noise',
      );
    });

    test('orientation is compared unoriented across the hemisphere seam',
        () {
      // Fits are canonicalized into the +z hemisphere; native telemetry
      // yaw is not. A raw wrap of 3.0 vs 3.0−π is ~π — past the 1.3
      // corner cap — so the gate used to read a flipped-hemisphere
      // same-surface pair as a corner and fail open.
      final ref = _wall(id: 1, cx: 0.7, cy: 0.925, cz: 2.0, yaw: 3.0);
      expect(
        wallFitConsistentWith(
          _wall(
              id: 900001,
              cx: 0.7,
              cy: 0.925,
              cz: 2.0,
              yaw: 3.0 - math.pi + 0.02),
          [ref],
        ),
        isTrue,
        reason: 'the same line within noise is yawDiff 0.02, not ~π',
      );
      expect(
        wallFitConsistentWith(
          _wall(
              id: 900001,
              cx: 0.7,
              cy: 0.925,
              cz: 2.0,
              yaw: 3.0 - math.pi + 0.5),
          [ref],
        ),
        isFalse,
        reason: '0.5 rad off the same surface is still the grazing signature',
      );
    });

    test('a flipped-hemisphere reference still rejects the grazing fit', () {
      final existing = [_wall(id: 1, cx: 0.7, cy: 0.925, cz: 2.0, yaw: 3.0)];
      expect(
        fitWallPlanes(
            points: _flat(rotatedA(3.0 - math.pi + 0.5)),
            refY: 0,
            existing: existing),
        isEmpty,
        reason: 'the +z-canonical fit must not read as a corner of yaw 3.0',
      );
    });

    test('short or empty clouds never throw', () {
      expect(fitWallPlanes(points: const [], refY: 0), isEmpty);
      expect(
        fitWallPlanes(points: const [0.1, 1.0, 2.0], refY: 0),
        isEmpty,
      );
      expect(
        fitWallPlanes(points: _flat(wallA), refY: 0, maxPlanes: 0),
        isEmpty,
      );
    });
  });

  group('MaskTrack temporal stabilization', () {
    test('first sighting hidden, second tick emitted', () {
      final q = _maskQuad();
      var tracks = updateMaskTracks(tracks: const [], curr: [q]);
      expect(emitMaskTracks(tracks), isEmpty,
          reason: 'a real object is seen two ticks running');
      tracks = updateMaskTracks(tracks: tracks, curr: [q]);
      expect(emitMaskTracks(tracks), hasLength(1));
    });

    test('vanished cluster emitted once (hold) then dropped', () {
      final q = _maskQuad();
      var tracks = updateMaskTracks(tracks: const [], curr: [q]);
      tracks = updateMaskTracks(tracks: tracks, curr: [q]);
      expect(emitMaskTracks(tracks), hasLength(1));

      tracks = updateMaskTracks(tracks: tracks, curr: const []);
      expect(tracks.single.holds, 1);
      expect(emitMaskTracks(tracks), hasLength(1),
          reason: 'one missed tick keeps the held geometry alive');

      tracks = updateMaskTracks(tracks: tracks, curr: const []);
      expect(tracks, isEmpty, reason: 'holds > maxHold drops the track');
      expect(emitMaskTracks(tracks), isEmpty);
    });

    test('alternating appear/disappear noise NEVER emits', () {
      // Depth-noise cells flicker AND jump — each reappearance lands in a
      // fresh spot beyond matchDist, so no track ever reaches streak 2.
      var tracks = const <MaskTrack>[];
      for (var i = 0; i < 6; i++) {
        tracks =
            updateMaskTracks(tracks: tracks, curr: [_maskQuad(x: i * 1.5)]);
        expect(emitMaskTracks(tracks), isEmpty, reason: 'appearance $i');
        tracks = updateMaskTracks(tracks: tracks, curr: const []);
        expect(emitMaskTracks(tracks), isEmpty, reason: 'gap after $i');
      }
    });

    test('id inherited across jitter within matchDist', () {
      final q0 = _maskQuad(x: 0, z: 1);
      final q1 = _maskQuad(x: 0.2, z: 1);
      var tracks = updateMaskTracks(tracks: const [], curr: [q0]);
      final id0 = tracks.single.id;
      tracks = updateMaskTracks(tracks: tracks, curr: [q1]);
      expect(tracks.single.id, id0);
      expect(tracks.single.streak, 2);
      expect(emitMaskTracks(tracks), hasLength(1));
    });

    test('cap by area at maxEmit', () {
      final quads = [
        for (var i = 0; i < 16; i++)
          _maskQuad(x: i * 2.0, z: 1, size: 0.3 + i * 0.1),
      ];
      var tracks = updateMaskTracks(tracks: const [], curr: quads);
      tracks = updateMaskTracks(tracks: tracks, curr: quads);
      final emitted = emitMaskTracks(tracks);
      expect(emitted, hasLength(14));
      expect(emitted.first.extentX, closeTo(0.3 + 15 * 0.1, 1e-9),
          reason: 'biggest area first');
      expect(emitted.last.extentX, closeTo(0.3 + 2 * 0.1, 1e-9),
          reason: 'the two smallest clusters are capped off');
      expect(
        emitted.any(
            (q) => (q.extentX - 0.3).abs() < 1e-9 || (q.extentX - 0.4).abs() < 1e-9),
        isFalse,
      );
    });

    test('identical input → identical output, inputs never mutated', () {
      final quads = [_maskQuad(x: 0), _maskQuad(x: 3, size: 0.9)];
      var a = updateMaskTracks(tracks: const [], curr: quads);
      a = updateMaskTracks(tracks: a, curr: quads);
      final snapshot = List<MaskTrack>.of(a);
      updateMaskTracks(tracks: a, curr: const []);
      expect(a.length, snapshot.length);
      expect(identical(a[0], snapshot[0]), isTrue,
          reason: 'updateMaskTracks must not mutate its input list');

      var b = updateMaskTracks(tracks: const [], curr: quads);
      b = updateMaskTracks(tracks: b, curr: quads);
      expect([for (final t in a) t.id], [for (final t in b) t.id]);
      expect([for (final t in a) t.streak], [for (final t in b) t.streak]);
      final ea = emitMaskTracks(a);
      final eb = emitMaskTracks(b);
      expect([for (final q in ea) q.center.x],
          [for (final q in eb) q.center.x]);
    });
  });

  group('WallTrack temporal stabilization', () {
    test('two consecutive fits → one track, same id, damped geometry', () {
      final fit0 = _wall(id: 900001, cx: 0);
      final fit1 = _wall(id: 900001, cx: 0.4);
      var tracks = updateWallTracks(tracks: const [], curr: [fit0]);
      expect(tracks, hasLength(1));
      expect(tracks.single.streak, 1);

      tracks = updateWallTracks(tracks: tracks, curr: [fit1]);
      expect(tracks, hasLength(1));
      expect(tracks.single.streak, 2);
      expect(tracks.single.plane.id, 900001);
      final jump = fit1.centerX - fit0.centerX;
      final moved = tracks.single.plane.centerX - fit0.centerX;
      expect(moved, closeTo(0.35 * jump, 1e-9),
          reason: 'geometry blends toward the new fit at α 0.35');
      expect(moved.abs(), lessThanOrEqualTo(0.35 * jump.abs() + 1e-12));
      expect(emitWallTracks(tracks), hasLength(1));
    });

    test('held wall keeps emitting during misses (holds ≤ maxHold) then '
        'drops', () {
      final fit = _wall(id: 900001, cx: 0);
      var tracks = updateWallTracks(
          tracks: const [], curr: [fit], maxHold: 2);
      tracks = updateWallTracks(
          tracks: tracks, curr: [fit], maxHold: 2);
      expect(emitWallTracks(tracks), hasLength(1));

      tracks = updateWallTracks(tracks: tracks, curr: const [], maxHold: 2);
      expect(tracks.single.holds, 1);
      expect(emitWallTracks(tracks), hasLength(1),
          reason: 'held tracks keep their old streak');

      tracks = updateWallTracks(tracks: tracks, curr: const [], maxHold: 2);
      expect(tracks.single.holds, 2);
      expect(emitWallTracks(tracks), hasLength(1));

      tracks = updateWallTracks(tracks: tracks, curr: const [], maxHold: 2);
      expect(tracks, isEmpty, reason: 'holds > maxHold (2) drops the track');
      expect(emitWallTracks(tracks), isEmpty);
    });

    test('default hold tolerates a long turn-away before dropping', () {
      // At the 1 Hz ticker the default maxHold (30) keeps a briefly-unseen
      // wall alive through ~30 s of turning instead of 3 ticks.
      final fit = _wall(id: 900001, cx: 0);
      var tracks = updateWallTracks(tracks: const [], curr: [fit]);
      tracks = updateWallTracks(tracks: tracks, curr: [fit]);
      expect(emitWallTracks(tracks), hasLength(1));

      for (var i = 0; i < 5; i++) {
        tracks = updateWallTracks(tracks: tracks, curr: const []);
        expect(tracks, hasLength(1), reason: 'miss ${i + 1} still held');
        expect(emitWallTracks(tracks), hasLength(1),
            reason: 'streak is preserved while held');
      }
      expect(tracks.single.streak, 2);
    });

    test('a sub-m² track never emits, even at full streak', () {
      final small = updateWallTracks(
          tracks: const [], curr: [_wall(id: 900001, ex: 0.9, ez: 1.0)]);
      final streaked = updateWallTracks(
          tracks: small, curr: [_wall(id: 900001, ex: 0.9, ez: 1.0)]);
      expect(streaked.single.streak, greaterThanOrEqualTo(2));
      expect(emitWallTracks(streaked), isEmpty,
          reason: 'the shared area gate is the mandatory final boundary');

      final ok = updateWallTracks(
          tracks: const [], curr: [_wall(id: 900001)]); // 1.4×1.2
      final ok2 = updateWallTracks(tracks: ok, curr: [_wall(id: 900001)]);
      expect(emitWallTracks(ok2), hasLength(1));
    });

    test('a fit 0.6 m away (unmatched) stays hidden until its second tick',
        () {
      var tracks =
          updateWallTracks(tracks: const [], curr: [_wall(id: 900001, cx: 0)]);
      final far = _wall(id: 900001, cx: 0.6);
      tracks = updateWallTracks(tracks: tracks, curr: [far]);
      expect(tracks, hasLength(2), reason: '0.6 m > matchDistM starts a new '
          'track while the old one holds');
      expect(emitWallTracks(tracks), isEmpty);

      tracks = updateWallTracks(tracks: tracks, curr: [far]);
      final emitted = emitWallTracks(tracks);
      expect(emitted, hasLength(1));
      expect(emitted.single.centerX, closeTo(0.6, 1e-9));
    });

    test('yaw beyond maxYawDelta starts a new track', () {
      final a = _wall(id: 900001, cx: 0, yaw: 0);
      final b = _wall(id: 900002, cx: 0, yaw: 0.5);
      var tracks = updateWallTracks(tracks: const [], curr: [a]);
      tracks = updateWallTracks(tracks: tracks, curr: [b]);
      expect(tracks, hasLength(2), reason: 'yaw jump breaks the match');
      expect(emitWallTracks(tracks), isEmpty,
          reason: 'both tracks are still at streak 1');
    });

    test('id collision on a held wall is reminted', () {
      var tracks =
          updateWallTracks(tracks: const [], curr: [_wall(id: 900001, cx: 0)]);
      tracks = updateWallTracks(tracks: tracks, curr: const []);
      expect(tracks.single.holds, 1);

      // RANSAC ids are positional: a different wall can re-fit under the
      // held wall's id.
      tracks = updateWallTracks(
          tracks: tracks, curr: [_wall(id: 900001, cx: 3)]);
      expect(tracks, hasLength(2));
      final ids = [for (final t in tracks) t.plane.id];
      expect(ids.toSet(), hasLength(2), reason: 'the held id must be kept '
          'by the held track');
      final fresh = tracks.firstWhere((t) => t.plane.centerX == 3);
      expect(fresh.streak, 1);
      expect(fresh.plane.id, isNot(900001));
      expect(fresh.plane.id, greaterThan(900001));
    });

    test('identical input → identical output', () {
      final fits = [_wall(id: 900001, cx: 0), _wall(id: 900002, cx: 5)];
      var a = updateWallTracks(tracks: const [], curr: fits);
      a = updateWallTracks(tracks: a, curr: fits);
      var b = updateWallTracks(tracks: const [], curr: fits);
      b = updateWallTracks(tracks: b, curr: fits);
      expect([for (final t in a) t.plane.toJson()],
          [for (final t in b) t.plane.toJson()]);
      expect([for (final t in a) (t.streak, t.holds)],
          [for (final t in b) (t.streak, t.holds)]);
      expect([for (final p in emitWallTracks(a)) p.toJson()],
          [for (final p in emitWallTracks(b)) p.toJson()]);
    });

    test('a held track paints through its retention window, then drops', () {
      final fit = _wall(id: 900001, cx: 0);
      var tracks = updateWallTracks(tracks: const [], curr: [fit]);
      tracks = updateWallTracks(tracks: tracks, curr: [fit]); // streak 2
      expect(emitWallTracks(tracks), hasLength(1));

      for (var i = 0; i < 30; i++) {
        tracks = updateWallTracks(tracks: tracks, curr: const []);
      }
      expect(tracks.single.holds, 30);
      expect(emitWallTracks(tracks), hasLength(1),
          reason: 'the emit grace rides the whole retention window — a '
              'static wall must not flicker out while depth points are away');

      tracks = updateWallTracks(tracks: tracks, curr: const []);
      expect(tracks, isEmpty, reason: 'holds > maxHold (30) drops the track');
      expect(emitWallTracks(tracks), isEmpty);
    });

    test('a shorter explicit emit grace stops painting while retained', () {
      final fit = _wall(id: 900001, cx: 0);
      var tracks = updateWallTracks(tracks: const [], curr: [fit]);
      tracks = updateWallTracks(tracks: tracks, curr: [fit]); // streak 2
      tracks = updateWallTracks(tracks: tracks, curr: const []);
      expect(tracks.single.holds, 1);
      expect(emitWallTracks(tracks, maxEmitHolds: 1), hasLength(1),
          reason: 'holds == grace still paints');
      tracks = updateWallTracks(tracks: tracks, curr: const []);
      expect(tracks.single.holds, 2);
      expect(emitWallTracks(tracks, maxEmitHolds: 1), isEmpty,
          reason: 'holds > grace stops painting');
      expect(tracks, hasLength(1), reason: 'the track itself stays retained');
    });

    test('a fresh fragment is not crowded out by older tracks', () {
      final older = [
        for (var i = 0; i < 4; i++) _wall(id: 900001 + i, cx: i * 4.0)
      ];
      var tracks = updateWallTracks(tracks: const [], curr: older);
      for (var i = 0; i < 9; i++) {
        tracks = updateWallTracks(tracks: tracks, curr: older);
      }
      expect([for (final t in tracks) t.streak], [10, 10, 10, 10]);
      final withFragment = [...older, _wall(id: 900005, cx: 20)];
      tracks = updateWallTracks(tracks: tracks, curr: withFragment);
      tracks = updateWallTracks(tracks: tracks, curr: withFragment);
      final emitted = emitWallTracks(tracks);
      expect(emitted, hasLength(5),
          reason: 'streak-desc sort must have room for the new fragment — '
              'with maxEmit 3 the held tracks held every slot');
      expect(emitted.any((p) => p.id == 900005), isTrue);
    });

    test('an unconfirmed streak-2 track is suppressed until the camera moves',
        () {
      final fit = _wall(id: 900001, cx: 0);
      final cam0 = Vector3(0, 1.5, 0);
      var tracks =
          updateWallTracks(tracks: const [], curr: [fit], cameraPos: cam0);
      tracks =
          updateWallTracks(tracks: tracks, curr: [fit], cameraPos: cam0);
      expect(tracks.single.streak, 2);
      expect(tracks.single.confirmed, isFalse);
      expect(emitWallTracks(tracks), isEmpty,
          reason: 'a single-view phantom never paints');

      tracks = updateWallTracks(
          tracks: tracks, curr: [fit], cameraPos: Vector3(0.3, 1.5, 0));
      expect(tracks.single.confirmed, isTrue,
          reason: 'camera moved ≥0.25 m since mint → two views');
      expect(emitWallTracks(tracks), hasLength(1));
    });

    test('a stationary track still emits at the streak ≥4 fallback', () {
      final fit = _wall(id: 900001, cx: 0);
      final cam = Vector3(0, 1.5, 0);
      var tracks =
          updateWallTracks(tracks: const [], curr: [fit], cameraPos: cam);
      for (var i = 0; i < 3; i++) {
        tracks = updateWallTracks(tracks: tracks, curr: [fit], cameraPos: cam);
      }
      expect(tracks.single.streak, 4);
      expect(tracks.single.confirmed, isFalse);
      expect(emitWallTracks(tracks), hasLength(1),
          reason: 'stationary detection survives at ~4 cloud ticks');
    });

    test('an unconfirmed held track stops painting', () {
      final fit = _wall(id: 900001, cx: 0);
      final cam = Vector3(0, 1.5, 0);
      var tracks =
          updateWallTracks(tracks: const [], curr: [fit], cameraPos: cam);
      tracks =
          updateWallTracks(tracks: tracks, curr: [fit], cameraPos: cam);
      tracks =
          updateWallTracks(tracks: tracks, curr: const [], cameraPos: cam);
      expect(tracks.single.holds, 1);
      expect(tracks.single.streak, 2);
      expect(emitWallTracks(tracks), isEmpty,
          reason: 'streak frozen below 4 and never confirmed');
    });
  });
}
