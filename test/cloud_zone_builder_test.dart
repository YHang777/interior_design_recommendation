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
    test('median of the band with eight points', () {
      final ys = [0.0, 0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07];
      final pts = _flat([
        for (var i = 0; i < ys.length; i++) [i * 0.01, ys[i], 0.0],
      ]);
      expect(floorProbeCandidate(points: pts, refY: 0), closeTo(0.035, 1e-12));
    });

    test('odd count takes the middle value', () {
      final ys = [0.0, 0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08];
      final pts = _flat([
        for (var i = 0; i < ys.length; i++) [i * 0.01, ys[i], 0.0],
      ]);
      expect(floorProbeCandidate(points: pts, refY: 0), closeTo(0.04, 1e-12));
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
        [0.2, -0.4, 0.0],
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
      var tracks = updateWallTracks(tracks: const [], curr: [fit]);
      tracks = updateWallTracks(tracks: tracks, curr: [fit]);
      expect(emitWallTracks(tracks), hasLength(1));

      tracks = updateWallTracks(tracks: tracks, curr: const []);
      expect(tracks.single.holds, 1);
      expect(emitWallTracks(tracks), hasLength(1),
          reason: 'held tracks keep their old streak');

      tracks = updateWallTracks(tracks: tracks, curr: const []);
      expect(tracks.single.holds, 2);
      expect(emitWallTracks(tracks), hasLength(1));

      tracks = updateWallTracks(tracks: tracks, curr: const []);
      expect(tracks, isEmpty, reason: 'holds > maxHold (2) drops the track');
      expect(emitWallTracks(tracks), isEmpty);
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
  });
}
