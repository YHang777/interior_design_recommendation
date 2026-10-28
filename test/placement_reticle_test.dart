import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/furniture_model_library.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/placement_reticle.dart';
import 'package:vector_math/vector_math_64.dart';

ARHitTestResult horizontalPlane({
  required double x,
  required double y,
  required double z,
  required double extentX,
  required double extentZ,
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
  required double z,
  required double extentX,
  required double extentZ,
  double distance = 2.0,
}) {
  final t = Matrix4.copy(Matrix4.rotationZ(math.pi / 2))
    ..setTranslation(Vector3(x, 1.0, z));
  return ARHitTestResult(
    ARHitTestResultType.plane,
    distance,
    t,
    planeType: 2,
    planeExtentX: extentX,
    planeExtentZ: extentZ,
  );
}

ARHitTestResult featurePoint() => ARHitTestResult(
      ARHitTestResultType.point,
      1.5,
      Matrix4.translation(Vector3(0, 0, 1.5)),
    );

void main() {
  group('ReticleAdvisor.evaluate', () {
    test('floor intent without a live floor → noFloorYet', () {
      final s = ReticleAdvisor.evaluate(
        hits: [horizontalPlane(x: 0, y: 0, z: 2, extentX: 3, extentZ: 3)],
        intent: PlacementType.floor,
        liveFloorY: null,
      );
      expect(s.status, ReticleStatus.noFloorYet);
    });

    test('valid floor under center → locked with distance', () {
      final s = ReticleAdvisor.evaluate(
        hits: [
          horizontalPlane(
              x: 0, y: 0, z: 2, extentX: 3, extentZ: 3, distance: 2.1),
        ],
        intent: PlacementType.floor,
        liveFloorY: 0,
      );
      expect(s.status, ReticleStatus.locked);
      expect(s.distanceM, 2.1);
    });

    test('small floor patch → keep scanning', () {
      final s = ReticleAdvisor.evaluate(
        hits: [
          horizontalPlane(x: 0, y: 0, z: 1, extentX: 0.4, extentZ: 0.4),
        ],
        intent: PlacementType.floor,
        liveFloorY: 0,
      );
      expect(s.status, ReticleStatus.searching);
    });

    test('big floor plane out of reach → tooFar', () {
      final s = ReticleAdvisor.evaluate(
        hits: [
          horizontalPlane(
              x: 0, y: 0, z: 6, extentX: 4, extentZ: 4, distance: 6.0),
        ],
        intent: PlacementType.floor,
        liveFloorY: 0,
      );
      expect(s.status, ReticleStatus.tooFar);
      expect(s.distanceM, 6.0);
    });

    test('floor plane nearly touching the camera → tooClose', () {
      final s = ReticleAdvisor.evaluate(
        hits: [
          horizontalPlane(
              x: 0, y: 0, z: 0.1, extentX: 2, extentZ: 2, distance: 0.1),
        ],
        intent: PlacementType.floor,
        liveFloorY: 0,
      );
      expect(s.status, ReticleStatus.tooClose);
    });

    test('wall intent locks on a qualifying wall', () {
      final s = ReticleAdvisor.evaluate(
        hits: [
          verticalPlane(x: 1, z: 2, extentX: 2.5, extentZ: 2.5),
        ],
        intent: PlacementType.wall,
      );
      expect(s.status, ReticleStatus.locked);
    });

    test('any intent locks on any plausible plane', () {
      final s = ReticleAdvisor.evaluate(
        hits: [
          horizontalPlane(x: 0, y: 0, z: 1, extentX: 1.0, extentZ: 1.0),
        ],
        intent: PlacementType.any,
      );
      expect(s.status, ReticleStatus.locked);
    });

    test('only feature points → searching, never locked', () {
      final s = ReticleAdvisor.evaluate(
        hits: [featurePoint()],
        intent: PlacementType.any,
      );
      expect(s.status, ReticleStatus.searching);
    });

    test('floor intent ignores walls in the distance check', () {
      final s = ReticleAdvisor.evaluate(
        hits: [
          verticalPlane(x: 1, z: 5, extentX: 3, extentZ: 3, distance: 5.5),
        ],
        intent: PlacementType.floor,
        liveFloorY: 0,
      );
      expect(s.status, ReticleStatus.searching);
    });
  });
}
