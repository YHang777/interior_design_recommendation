import 'dart:math' as math;
import 'dart:ui';

import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/placement_policy.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_overlay_math.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/room_walls.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/wall_raycast.dart';
import 'package:vector_math/vector_math_64.dart';

PlaneQuad wallAt(double cx, double cz, double yaw,
    {double w = 1.2, double h = 1.8, double cy = 0.9}) {
  final u = Vector3(math.cos(yaw), 0, -math.sin(yaw));
  final c = Vector3(cx, cy, cz);
  return PlaneQuad(
    center: c,
    yaw: yaw,
    extentX: w,
    extentZ: h,
    vertical: true,
    kind: PlaneQuadKind.wall,
    polygon: [
      c - u * (w / 2) - Vector3(0, h / 2, 0),
      c + u * (w / 2) - Vector3(0, h / 2, 0),
      c + u * (w / 2) + Vector3(0, h / 2, 0),
      c - u * (w / 2) + Vector3(0, h / 2, 0),
    ],
  );
}

void main() {
  final t0 = DateTime(2026);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  group('RoomWalls', () {
    test('a wall shows only after it has been seen for a second', () {
      final rw = RoomWalls();
      expect(rw.update([wallAt(0, 2, 0)], baseY: 0, now: at(0)), isEmpty);
      expect(rw.update([wallAt(0, 2, 0)], baseY: 0, now: at(500)), isEmpty);
      expect(rw.update([wallAt(0, 2, 0)], baseY: 0, now: at(1100)), hasLength(1));
    });

    test('overlapping fragments of one wall fold into ONE painted wall', () {
      final rw = RoomWalls();
      List<PlaneQuad> out = const [];
      for (var i = 0; i <= 15; i++) {
        out = rw.update([
          wallAt(-0.8, 2.00, 0),
          wallAt(0.2, 2.08, 0),
          wallAt(1.0, 1.95, math.pi),
        ], baseY: 0, now: at(i * 100));
      }
      expect(out, hasLength(1));
      final w = out.single;
      expect(w.extentX, greaterThan(2.5), reason: 'span is the union');
      expect(w.center.z, closeTo(2.0, 0.1));
    });

    test('a fit that expires never removes the painted wall', () {
      final rw = RoomWalls();
      for (var i = 0; i <= 12; i++) {
        rw.update([wallAt(0, 2, 0)], baseY: 0, now: at(i * 100));
      }
      expect(rw.update(const [], baseY: 0, now: at(5000)), hasLength(1));
    });

    test('once frozen, a drifting refit does not move the wall', () {
      final rw = RoomWalls();
      for (var i = 0; i <= 40; i++) {
        rw.update([wallAt(0, 2, 0)], baseY: 0, now: at(i * 100));
      }
      final before = rw.update(const [], baseY: 0, now: at(4100)).single;
      for (var i = 0; i < 20; i++) {
        rw.update([wallAt(0, 2.2, 0)], baseY: 0, now: at(4200 + i * 100));
      }
      final after = rw.update(const [], baseY: 0, now: at(7000)).single;
      expect(after.center.z, closeTo(before.center.z, 1e-9));
    });

    test('perpendicular walls stay separate', () {
      final rw = RoomWalls();
      List<PlaneQuad> out = const [];
      for (var i = 0; i <= 12; i++) {
        out = rw.update([wallAt(0, 2, 0), wallAt(2, 0, math.pi / 2)],
            baseY: 0, now: at(i * 100));
      }
      expect(out, hasLength(2));
    });

    test('wall bottoms follow the current floor height', () {
      final rw = RoomWalls();
      for (var i = 0; i <= 12; i++) {
        rw.update([wallAt(0, 2, 0)], baseY: 0, now: at(i * 100));
      }
      final w = rw.update(const [], baseY: -0.05, now: at(1300)).single;
      expect(planeQuadCorners(w).map((c) => c.y).reduce(math.min),
          closeTo(-0.05, 1e-9));
    });
  });

  group('wall raycast', () {
    test('screenRay inverts the overlay projection', () {
      final proj = makePerspectiveMatrix(1.0, 0.5, 0.1, 100);
      final view = makeViewMatrix(
          Vector3(0, 1.5, 0), Vector3(0, 1.5, 5), Vector3(0, 1, 0));
      final vp = proj * view;
      const size = Size(400, 800);
      final target = Vector3(0.3, 1.2, 3);
      final clip = Vector4(target.x, target.y, target.z, 1)..applyMatrix4(vp);
      final px = Offset((clip.x / clip.w + 1) / 2 * size.width,
          (1 - clip.y / clip.w) / 2 * size.height);
      final ray = screenRay(vp, px, size)!;
      final toTarget = (target - ray.origin).normalized();
      expect((toTarget - ray.dir).length, lessThan(1e-6));
    });

    test('a ray hits the nearest painted wall, normal toward the camera', () {
      final near = wallAt(0, 2, 0, w: 3);
      final far = wallAt(0, 4, 0, w: 3);
      final h = raycastWalls(
          origin: Vector3(0, 1, 0),
          dir: Vector3(0, 0, 1),
          walls: [far, near])!;
      expect(h.point.z, closeTo(2, 1e-9));
      expect(h.normal.z, lessThan(0), reason: 'faces back into the room');
    });

    test('a ray past the wall edge misses', () {
      final w = wallAt(0, 2, 0, w: 1);
      expect(
          raycastWalls(
              origin: Vector3(0, 1, 0),
              dir: Vector3(0.6, 0, 0.8).normalized(),
              walls: [w]),
          isNull);
    });

    test('the hit pose reads as a vertical wall to the placement policy', () {
      final h = raycastWalls(
          origin: Vector3(0, 1, 0),
          dir: Vector3(0, 0, 1),
          walls: [wallAt(0, 2, 0, w: 3)])!;
      final pose = wallHitPose(h);
      expect(pose.getColumn(1).y.abs(), lessThan(1e-9));
      final t = ArPlacementPolicy.wallAnchorTransform(ARHitTestResult(
          ARHitTestResultType.plane, h.distance, pose,
          planeType: 2, planeExtentX: 3, planeExtentZ: 1.8));
      expect(t.getTranslation().z, lessThan(2),
          reason: 'panel sits on the room side of the wall');
    });
  });
}
