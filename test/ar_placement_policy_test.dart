import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/placement_policy.dart';
import 'package:vector_math/vector_math_64.dart';

ARHitTestResult horizontalPlane({
  required double x,
  required double y,
  required double z,
  double? extentX,
  double? extentZ,
  double distance = 2.0,
}) {
  return ARHitTestResult(
    ARHitTestResultType.plane,
    distance,
    Matrix4.translation(Vector3(x, y, z)),
    planeType: 1,
    planeExtentX: extentX,
    planeExtentZ: extentZ,
  );
}

ARHitTestResult verticalPlane({
  required double x,
  double y = 1.0,
  required double z,
  double? extentX,
  double? extentZ,
  double distance = 2.0,
  Matrix4? rotation,
}) {
  final t = Matrix4.copy(rotation ?? Matrix4.rotationZ(math.pi / 2))
    ..setTranslation(Vector3(x, y, z));
  return ARHitTestResult(
    ARHitTestResultType.plane,
    distance,
    t,
    planeType: 2,
    planeExtentX: extentX,
    planeExtentZ: extentZ,
  );
}

ARHitTestResult featurePoint({required double y}) {
  return ARHitTestResult(
    ARHitTestResultType.point,
    1.5,
    Matrix4.translation(Vector3(0, y, 0)),
  );
}

ARPlaneInfo planeInfo({
  required int type,
  required double cy,
  double cx = 0,
  double cz = 2,
  double ex = 4,
  double ez = 4,
}) {
  return ARPlaneInfo(
    planeType: type,
    centerX: cx,
    centerY: cy,
    centerZ: cz,
    extentX: ex,
    extentZ: ez,
  );
}

void main() {
  group('ArPlacementPolicy.liveFloorYFromPlanes (Bug 2: live floor)', () {
    test('table-top-only plane list → NO live floor', () {
      final planes = [
        planeInfo(type: 1, cy: 0.55, ex: 0.9, ez: 0.55),
      ];
      expect(ArPlacementPolicy.liveFloorYFromPlanes(planes), isNull);
    });

    test('fridge-top-only plane list → NO live floor', () {
      final planes = [
        planeInfo(type: 1, cy: 0.9, ex: 0.6, ez: 0.7),
      ];
      expect(ArPlacementPolicy.liveFloorYFromPlanes(planes), isNull);
    });

    test('floor + table → the FLOOR height wins (lowest qualifying plane)', () {
      final planes = [
        planeInfo(type: 1, cy: 0.75, ex: 1.2, ez: 0.8),
        planeInfo(type: 1, cy: 0.0, ex: 4.0, ez: 4.0),
      ];
      expect(ArPlacementPolicy.liveFloorYFromPlanes(planes), 0.0);
    });

    test('ignores vertical planes and non-finite centers', () {
      final planes = [
        planeInfo(type: 2, cy: 1.0, ex: 3.0, ez: 3.0),
        planeInfo(type: 1, cy: double.nan, ex: 4.0, ez: 4.0),
        planeInfo(type: 1, cy: 0.1, ex: 3.0, ez: 3.0),
      ];
      expect(ArPlacementPolicy.liveFloorYFromPlanes(planes), 0.1);
    });
  });

  group('ArPlacementPolicy.chooseFloorHit (Bug 2: live-floor gate)', () {
    test('rejects a fridge-top-only hit list (small plane)', () {
      final hits = [
        horizontalPlane(x: 0, y: 0.9, z: 1.2, extentX: 0.6, extentZ: 0.7),
      ];
      expect(ArPlacementPolicy.chooseFloorHit(hits, liveFloorY: 0.0), isNull);
    });

    test('rejects a small nightstand-sized plane', () {
      final hits = [
        horizontalPlane(x: 0, y: 0.45, z: 1.0, extentX: 0.5, extentZ: 0.5),
      ];
      expect(ArPlacementPolicy.chooseFloorHit(hits, liveFloorY: 0.0), isNull);
    });

    test('rejects hits with UNREPORTED extent (must fail, not pass)', () {
      final hits = [
        horizontalPlane(x: 0, y: 0.9, z: 1.0),
        ARHitTestResult(
          ARHitTestResultType.plane,
          2.0,
          Matrix4.translation(Vector3(0, 0.9, 1.0)),
          planeType: 1,
          planeExtentX: 1.5,
        ),
      ];
      expect(ArPlacementPolicy.chooseFloorHit(hits, liveFloorY: 0.0), isNull);
    });

    test('ignores vertical planes and feature points for floor mode', () {
      final hits = [
        featurePoint(y: 0),
        verticalPlane(x: 0, z: 1.5, extentX: 2.0, extentZ: 2.0),
      ];
      expect(ArPlacementPolicy.chooseFloorHit(hits, liveFloorY: 0.0), isNull);
    });

    test('first-tap-on-table with a KNOWN live floor → REJECTED (0.5 m up)',
        () {
      final table = horizontalPlane(
          x: 0, y: 0.5, z: 1.5, extentX: 1.2, extentZ: 0.8, distance: 1.5);
      final chosen = ArPlacementPolicy.chooseFloorHit([table], liveFloorY: 0.0);
      expect(chosen, isNull,
          reason: 'a table 0.5 m above the live floor is not the floor');
    });

    test('floor + table in one hit list → the FLOOR wins', () {
      final table = horizontalPlane(
          x: 0, y: 0.75, z: 1.5, extentX: 1.2, extentZ: 0.8, distance: 1.5);
      final floor = horizontalPlane(
          x: 0, y: 0.02, z: 2.2, extentX: 4.0, extentZ: 4.0, distance: 2.4);
      final chosen =
          ArPlacementPolicy.chooseFloorHit([table, floor], liveFloorY: 0.0);
      expect(chosen, same(floor),
          reason: 'the table fails the live-floor height gate; the floor wins');
    });

    test('prefers the lowest world-Y among valid candidates', () {
      final raised = horizontalPlane(
          x: 0, y: 0.15, z: 1.5, extentX: 1.6, extentZ: 0.9, distance: 1.5);
      final floor = horizontalPlane(
          x: 0, y: 0.0, z: 2.0, extentX: 3.0, extentZ: 3.0, distance: 2.2);
      final chosen =
          ArPlacementPolicy.chooseFloorHit([raised, floor], liveFloorY: 0.0);
      expect(chosen, same(floor));
    });

    test('tie at the same height → the larger plane wins', () {
      final smaller = horizontalPlane(
          x: -0.5, y: 0, z: 1.5, extentX: 1.0, extentZ: 1.0, distance: 1.5);
      final larger = horizontalPlane(
          x: 0.5, y: 0, z: 1.5, extentX: 2.5, extentZ: 2.5, distance: 1.6);
      final chosen =
          ArPlacementPolicy.chooseFloorHit([smaller, larger], liveFloorY: 0.0);
      expect(chosen, same(larger));
    });

    test('accepts a candidate within tolerance of the live floor', () {
      final floor = horizontalPlane(
          x: 0, y: 0.05, z: 2.0, extentX: 3.0, extentZ: 3.0);
      final chosen =
          ArPlacementPolicy.chooseFloorHit([floor], liveFloorY: 0.0);
      expect(chosen, same(floor));
    });

    test('honors a custom maxAboveLiveFloorM tolerance', () {
      final raised = horizontalPlane(
          x: 0, y: 0.4, z: 2.0, extentX: 3.0, extentZ: 3.0);
      expect(ArPlacementPolicy.chooseFloorHit([raised], liveFloorY: 0.0),
          isNull);
      expect(
        ArPlacementPolicy.chooseFloorHit([raised],
            liveFloorY: 0.0, maxAboveLiveFloorM: 0.5),
        same(raised),
      );
    });

    test('falls back to the plane normal when planeType is not reported', () {
      final legacy = ARHitTestResult(
        ARHitTestResultType.plane,
        2.0,
        Matrix4.translation(Vector3(0, 0, 2.0)),
        planeExtentX: 3.0,
        planeExtentZ: 3.0,
      );
      expect(ArPlacementPolicy.isHorizontalPlane(legacy), isTrue);

      final legacyWall = ARHitTestResult(
        ARHitTestResultType.plane,
        2.0,
        Matrix4.rotationZ(math.pi / 2)..setTranslation(Vector3(0, 1, 2)),
        planeExtentX: 2.0,
        planeExtentZ: 2.0,
      );
      expect(ArPlacementPolicy.isHorizontalPlane(legacyWall), isFalse);
    });
  });

  group('ArPlacementPolicy.chooseWallHit (Bug 2: strengthened)', () {
    test('picks the LARGEST qualifying wall (not the closest)', () {
      final small = verticalPlane(
          x: 0, z: 1.5, extentX: 1.0, extentZ: 1.0, distance: 1.5);
      final large = verticalPlane(
          x: 0, z: 3.0, extentX: 3.0, extentZ: 2.5, distance: 3.0);
      final chosen = ArPlacementPolicy.chooseWallHit([small, large]);
      expect(chosen, same(large));
    });

    test('skips horizontal planes', () {
      final floor = horizontalPlane(
          x: 0, y: 0, z: 2.0, extentX: 3.0, extentZ: 3.0);
      final wall = verticalPlane(x: 1, z: 2.0, extentX: 2.0, extentZ: 2.0);
      final chosen = ArPlacementPolicy.chooseWallHit([floor, wall]);
      expect(chosen, same(wall));
    });

    test('REJECTS unreported extent for walls (telemetry era)', () {
      final wall = verticalPlane(x: 0, z: 2.0);
      expect(ArPlacementPolicy.chooseWallHit([wall]), isNull);
    });

    test('rejects a wall below the 0.8 m both-axes gate', () {
      final sliver =
          verticalPlane(x: 0, z: 2.0, extentX: 1.2, extentZ: 0.6);
      expect(ArPlacementPolicy.chooseWallHit([sliver]), isNull);
    });

    test('rejects a tilted normal (|y| > 0.25)', () {
      final tilted = verticalPlane(
        x: 0,
        z: 2.0,
        extentX: 3.0,
        extentZ: 2.5,
        rotation: Matrix4.rotationX(math.pi / 3),
      );
      expect(ArPlacementPolicy.chooseWallHit([tilted]), isNull);
    });

    test('accepts a level normal (|y| ≤ 0.25)', () {
      final wall = verticalPlane(
          x: 0, z: 2.0, extentX: 2.0, extentZ: 2.0);
      expect(ArPlacementPolicy.chooseWallHit([wall]), same(wall));
    });
  });

  group('ArPlacementPolicy.chooseAnyHit (unchanged behaviour)', () {
    test('picks the closest plane of any orientation', () {
      final floor = horizontalPlane(
          x: 0, y: 0, z: 1.5, extentX: 3.0, extentZ: 3.0, distance: 1.5);
      final wall = verticalPlane(
          x: 0, z: 2.5, extentX: 2.0, extentZ: 2.0, distance: 2.5);
      expect(ArPlacementPolicy.chooseAnyHit([featurePoint(y: 0), floor, wall]),
          same(floor));
    });
  });

  group('ArPlacementPolicy.wallAnchorTransform (Bug 1: orientation)', () {
    Vector3 axis(Matrix4 m, int col) {
      final c = m.getColumn(col);
      return Vector3(c.x, c.y, c.z);
    }

    test('wall normal (−1, 0, 0): model +Z points out, +Y stays up', () {
      final hit = verticalPlane(
        x: 1.0,
        y: 1.5,
        z: 2.0,
        extentX: 2.4,
        extentZ: 2.7,
        rotation: Matrix4.rotationZ(math.pi / 2),
      );
      final m = ArPlacementPolicy.wallAnchorTransform(hit);

      final modelZ = axis(m, 2);
      expect(modelZ.x, closeTo(-1, 1e-6), reason: 'model +Z → wall normal X');
      expect(modelZ.y, closeTo(0, 1e-6));
      expect(modelZ.z, closeTo(0, 1e-6));

      final modelY = axis(m, 1);
      expect(modelY.x, closeTo(0, 1e-6), reason: 'model +Y stays world-up');
      expect(modelY.y, closeTo(1, 1e-6));
      expect(modelY.z, closeTo(0, 1e-6));

      final t = m.getTranslation();
      expect(t.x, closeTo(1.0 - 0.025, 1e-6));
      expect(t.y, closeTo(1.5, 1e-6));
      expect(t.z, closeTo(2.0, 1e-6));
    });

    test('wall normal (0, 0, 1): model +Z points out, +Y stays up', () {
      final hit = verticalPlane(
        x: 0.0,
        y: 1.0,
        z: 3.0,
        extentX: 2.4,
        extentZ: 2.7,
        rotation: Matrix4.rotationX(math.pi / 2),
      );
      final m = ArPlacementPolicy.wallAnchorTransform(hit);

      final modelZ = axis(m, 2);
      expect(modelZ.x, closeTo(0, 1e-6));
      expect(modelZ.y, closeTo(0, 1e-6));
      expect(modelZ.z, closeTo(1, 1e-6), reason: 'model +Z → wall normal Z');

      final modelY = axis(m, 1);
      expect(modelY.y, closeTo(1, 1e-6), reason: 'model +Y stays world-up');

      final t = m.getTranslation();
      expect(t.z, closeTo(3.0 + 0.025, 1e-6));
      expect(t.x, closeTo(0.0, 1e-6));
      expect(t.y, closeTo(1.0, 1e-6));
    });

    test('wallAnchorYaw maps a normal to the yaw that turns +Z onto it', () {
      final yaw = ArPlacementPolicy.wallAnchorYaw(Vector3(-1, 0, 0));
      expect(yaw, closeTo(-math.pi / 2, 1e-9));

      expect(ArPlacementPolicy.wallAnchorYaw(Vector3(0, 0, 1)), closeTo(0, 1e-9));
    });
  });
}
