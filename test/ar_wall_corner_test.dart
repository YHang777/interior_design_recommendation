import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_overlay_math.dart';
import 'package:vector_math/vector_math_64.dart';

PlaneQuad wall({
  required double x,
  required double z,
  double yaw = 0,
  double width = 2,
  List<Vector3> polygon = const [],
}) =>
    PlaneQuad(
      center: Vector3(x, 1, z),
      yaw: yaw,
      extentX: width,
      extentZ: 2,
      vertical: true,
      kind: PlaneQuadKind.wall,
      polygon: polygon,
    );

// Wall A lies on z = 2 running along +x; wall B on x = 2 running along −z.
// Their corner is (2, 2).
double endAlongX(PlaneQuad a) => a.center.x + a.extentX / 2;

double endAlongZ(PlaneQuad b) => b.center.z + b.extentX / 2;

void main() {
  group('joinWallCorners overshoot', () {
    test('a run poking 0.25 m past the corner is trimmed onto it', () {
      final a = wall(x: 0, z: 2, width: 4.5);
      final b = wall(x: 2, z: 0, yaw: math.pi / 2, width: 3.6);
      final out = joinWallCorners([a, b]);
      expect(endAlongX(out[0]), closeTo(2.0, 1e-9),
          reason: 'paint past the corner bleeds over the adjacent wall');
      expect(out[0].center.x - out[0].extentX / 2, closeTo(-2.25, 1e-9),
          reason: 'the far end is untouched');
      expect(endAlongZ(out[1]), closeTo(2.0, 1e-9));
    });

    test('both runs overshooting meet exactly at the corner', () {
      final a = wall(x: 0, z: 2, width: 4.4);
      final b = wall(x: 2, z: 0, yaw: math.pi / 2, width: 4.3);
      final out = joinWallCorners([a, b]);
      expect(endAlongX(out[0]), closeTo(2.0, 1e-9));
      expect(endAlongZ(out[1]), closeTo(2.0, 1e-9));
    });

    test('a through-wall at a T-junction is never cut', () {
      final a = wall(x: 0, z: 2, width: 8);
      final b = wall(x: 2, z: 0, yaw: math.pi / 2, width: 3.6);
      final out = joinWallCorners([a, b]);
      expect(out[0].extentX, closeTo(8, 1e-9));
      expect(endAlongZ(out[1]), closeTo(2.0, 1e-9),
          reason: 'the stem still extends onto the through-wall face');
    });

    test('a polygon outline is clamped at the corner, far side kept', () {
      final poly = [
        Vector3(-2.25, 0, 2),
        Vector3(2.25, 0, 2),
        Vector3(2.25, 2, 2),
        Vector3(-2.25, 2, 2),
      ];
      final a = wall(x: 0, z: 2, width: 4.5, polygon: poly);
      final b = wall(x: 2, z: 0, yaw: math.pi / 2, width: 4.0);
      final out = joinWallCorners([a, b]);
      final xs = [for (final v in out[0].polygon) v.x];
      expect(xs.reduce(math.max), closeTo(2.0, 1e-9));
      expect(xs.reduce(math.min), closeTo(-2.25, 1e-9));
    });

    test('a slightly skewed pair still closes on the true intersection', () {
      // B tilted 0.05 rad off square: the join must land on where the two
      // lines really cross, not on an assumed 90° corner.
      final a = wall(x: 0, z: 2, width: 4.5);
      final b = wall(x: 2, z: 0, yaw: math.pi / 2 + 0.05, width: 3.6);
      final out = joinWallCorners([a, b]);
      final ub = Vector3(math.cos(out[1].yaw), 0, -math.sin(out[1].yaw));
      final bEndPlus = out[1].center + ub * (out[1].extentX / 2);
      final bEndMinus = out[1].center - ub * (out[1].extentX / 2);
      final bEnd = bEndPlus.z > bEndMinus.z ? bEndPlus : bEndMinus;
      expect(bEnd.z, closeTo(2.0, 1e-9));
      expect(endAlongX(out[0]), closeTo(bEnd.x, 1e-9),
          reason: 'both runs end on the same point');
    });
  });
}
