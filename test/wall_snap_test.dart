import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_overlay_math.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/wall_snap.dart';
import 'package:vector_math/vector_math_64.dart';

const _deg = math.pi / 180;

PlaneQuad _wall(double yawDeg, {double w = 2.0, double h = 2.0}) {
  final yaw = yawDeg * _deg;
  final u = Vector3(math.cos(yaw), 0, -math.sin(yaw));
  final c = Vector3(1, 1, 2);
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
  test('wrapQuarter folds any angle into ±45°', () {
    expect(RoomAxis.wrapQuarter(100 * _deg), closeTo(10 * _deg, 1e-9));
    expect(RoomAxis.wrapQuarter(-100 * _deg), closeTo(-10 * _deg, 1e-9));
    expect(RoomAxis.wrapQuarter(178 * _deg), closeTo(-2 * _deg, 1e-9));
  });

  test('no axis until a wall of 1.5 m² is seen; nothing snaps before', () {
    final ax = RoomAxis();
    ax.observe([_wall(5, w: 1.0, h: 1.0)]);
    expect(ax.axis, isNull);
    final w = _wall(5, w: 1.0, h: 1.0);
    expect(ax.snap([w]).single.yaw, w.yaw);
  });

  test('scattered fits of one wall and its neighbour snap square', () {
    final ax = RoomAxis();
    ax.observe([_wall(172)]);
    final out = ax.snap([_wall(168), _wall(178), _wall(82)]);
    final a = RoomAxis.wrapQuarter(out[0].yaw - out[1].yaw);
    final b = RoomAxis.wrapQuarter(out[0].yaw - out[2].yaw);
    expect(a.abs(), lessThan(1e-9));
    expect(b.abs(), lessThan(1e-9), reason: 'perpendicular wall is exactly 90°');
  });

  test('a genuinely angled wall (30° off) is left as measured', () {
    final ax = RoomAxis();
    ax.observe([_wall(0)]);
    final w = _wall(30);
    expect(ax.snap([w]).single.yaw, w.yaw);
  });

  test('the axis freezes after its refinement budget', () {
    final ax = RoomAxis(refineSteps: 3);
    ax.observe([_wall(0)]);
    for (var i = 0; i < 10; i++) {
      ax.observe([_wall(10)]);
    }
    final frozen = ax.axis!;
    ax.observe([_wall(10)]);
    expect(ax.axis, frozen);
    expect(frozen, greaterThan(0));
    expect(frozen, lessThan(10 * _deg));
  });

  test('rotation keeps heights and turns the outline with the yaw', () {
    final w = _wall(0);
    final r = rotateWallYaw(w, 10 * _deg);
    for (var i = 0; i < w.polygon.length; i++) {
      expect(r.polygon[i].y, w.polygon[i].y);
    }
    final dir = r.polygon[1] - r.polygon[0];
    final expected = Vector3(math.cos(10 * _deg), 0, -math.sin(10 * _deg));
    expect((dir.normalized() - expected).length, lessThan(1e-9));
  });
}
