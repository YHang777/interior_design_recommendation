import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/scanner/data/camera_rig.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/plan_scene_math.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

void main() {
  const viewport = Size(800, 600);
  final rig = OrbitRig.frameRoom(roomWCm: 400, roomHCm: 500);
  final pose = rig.pose;

  FurniturePlacement sofa(
          {String id = 'sofa-1',
          double x = 40,
          double y = 40,
          double rotation = 0}) =>
      FurniturePlacement(
        id: id,
        name: 'Sofa',
        iconName: 'sofa',
        x: x,
        y: y,
        width: 180,
        height: 90,
        rotation: rotation,
      );

  double heightOf(FurniturePlacement f) => 85;

  test('floor points round-trip through projection', () {
    for (final p in [
      const Offset(200, 250),
      const Offset(50, 50),
      const Offset(380, 470),
      const Offset(0, 0),
    ]) {
      final screen = projectWorldPoint(
          pose, viewport, p.dx / 100, 0, p.dy / 100);
      expect(screen, isNotNull, reason: 'floor point $p must project');
      final back = floorPointAt(pose, viewport, screen!);
      expect(back, isNotNull, reason: 'projection of $p must land on the floor');
      expect(back!.dx, moreOrLessEquals(p.dx, epsilon: 0.01));
      expect(back.dy, moreOrLessEquals(p.dy, epsilon: 0.01));
    }
  });

  test('rays pointing at the sky miss the floor', () {
    // A level camera: the top of the screen looks above the horizon.
    const level = ScenePose(
      eyeX: 2,
      eyeY: 1.5,
      eyeZ: 0,
      targetX: 2,
      targetY: 1.5,
      targetZ: 1,
      fovDeg: 55,
    );
    expect(
        floorPointAt(level, viewport, const Offset(400, 0)), isNull);
    expect(
        floorPointAt(level, viewport, const Offset(400, 590)), isNotNull);
  });

  test('projectWorldPolyNear clips at the near plane', () {
    const level = ScenePose(
      eyeX: 2,
      eyeY: 1.5,
      eyeZ: 0,
      targetX: 2,
      targetY: 1.5,
      targetZ: 1,
      fovDeg: 55,
    );
    // Fully in front: identical to projecting the corners one by one.
    final front = [
      (x: 1.5, y: 0.0, z: 2.0),
      (x: 2.5, y: 0.0, z: 2.0),
      (x: 2.5, y: 0.0, z: 3.0),
      (x: 1.5, y: 0.0, z: 3.0),
    ];
    final pts = projectWorldPolyNear(level, viewport, front);
    expect(pts, hasLength(4));
    for (var i = 0; i < 4; i++) {
      final corner = projectWorldPoint(
          level, viewport, front[i].x, front[i].y, front[i].z)!;
      expect(pts[i].dx, moreOrLessEquals(corner.dx, epsilon: 1e-6));
      expect(pts[i].dy, moreOrLessEquals(corner.dy, epsilon: 1e-6));
    }

    // Fully behind the eye: nothing to draw.
    expect(
        projectWorldPolyNear(level, viewport, const [
          (x: 1.5, y: 0.0, z: -2.0),
          (x: 2.5, y: 0.0, z: -2.0),
          (x: 2.5, y: 0.0, z: -1.0),
          (x: 1.5, y: 0.0, z: -1.0),
        ]),
        isEmpty);

    // A ghost at your feet straddles the eye plane — its visible part must
    // still draw: two clipped + two surviving corners.
    final straddle = projectWorldPolyNear(level, viewport, const [
      (x: 1.0, y: 0.0, z: -0.5),
      (x: 3.0, y: 0.0, z: -0.5),
      (x: 3.0, y: 0.0, z: 0.5),
      (x: 1.0, y: 0.0, z: 0.5),
    ]);
    expect(straddle, hasLength(4));
    for (final p in straddle) {
      expect(p.dx.isFinite && p.dy.isFinite, isTrue);
    }
  });

  test('points behind the camera do not project', () {
    final back = projectWorldPoint(
        pose,
        viewport,
        pose.eyeX - (pose.targetX - pose.eyeX) * 2,
        pose.eyeY - (pose.targetY - pose.eyeY) * 2,
        pose.eyeZ - (pose.targetZ - pose.eyeZ) * 2);
    expect(back, isNull);
  });

  test('pickPlacementId selects the piece under the finger', () {
    final items = [
      sofa(id: 'a', x: 40, y: 40),
      sofa(id: 'b', x: 220, y: 300),
    ];
    Offset screenOf(FurniturePlacement f) {
      final s = projectWorldPoint(
        pose,
        viewport,
        (f.x + f.width / 2) / 100,
        heightOf(f) / 200,
        (f.y + f.height / 2) / 100,
      );
      return s!;
    }

    expect(
      pickPlacementId(pose, viewport, screenOf(items[0]), items,
          heightMOf: heightOf),
      'a',
    );
    expect(
      pickPlacementId(pose, viewport, screenOf(items[1]), items,
          heightMOf: heightOf),
      'b',
    );
    expect(
      pickPlacementId(pose, viewport, const Offset(10, 590), items,
          heightMOf: heightOf),
      isNull,
    );
  });

  test('rotated pieces pick through their yawed box', () {
    final items = [sofa(x: 150, y: 200, rotation: 90)];
    final s = projectWorldPoint(
      pose,
      viewport,
      (items[0].x + items[0].height / 2) / 100,
      heightOf(items[0]) / 200,
      (items[0].y + items[0].width / 2) / 100,
    );
    expect(
      pickPlacementId(pose, viewport, s!, items, heightMOf: heightOf),
      'sofa-1',
    );
  });

  test('rayBoxHit returns the entry distance', () {
    final ray = rayThroughScreenPoint(pose, viewport, Offset(400, 300));
    final t = rayBoxHit(
      ray,
      centerXCm: 200,
      centerZCm: 250,
      topYM: 0.9,
      halfWidthM: 0.9,
      halfDepthM: 0.45,
      yawRad: 0,
    );
    // The center screen ray points at the room center target on the floor,
    // so it enters the box above that point — before the target itself.
    expect(t, isNotNull);
    expect(t!, lessThan(5.5),
        reason: 'entry is closer than the 5.44 m target distance');
    expect(t, greaterThan(0));

    // A box far to the side of the ray is not hit.
    expect(
      rayBoxHit(
        ray,
        centerXCm: 5,
        centerZCm: 5,
        topYM: 0.9,
        halfWidthM: 0.1,
        halfDepthM: 0.1,
        yawRad: 0,
      ),
      isNull,
    );
  });

  test('the orbit rig never auto-rotates and clamps its moves', () {
    final r = OrbitRig.frameRoom(roomWCm: 400, roomHCm: 500);
    expect(r.azimuthRad, moreOrLessEquals(-math.pi / 4, epsilon: 1e-9));
    final before = r.pose;
    final again = r.pose;
    expect(again.eyeX, before.eyeX);
    expect(again.eyeZ, before.eyeZ);
    expect(again.targetX, before.targetX);

    r.orbit(-100, -100);
    expect(r.polarRad, 0.05);
    r.orbit(100, 100);
    expect(r.polarRad, 1.45);

    final maxD = r.maxDistanceM;
    r.dolly(1000);
    expect(r.distanceM, maxD);
    r.dolly(0.0001);
    expect(r.distanceM, 1.2);
  });

  test('frameRoom centers the target and frames the diagonal', () {
    final r = OrbitRig.frameRoom(roomWCm: 400, roomHCm: 500);
    expect(r.targetXm, moreOrLessEquals(2.0, epsilon: 1e-9));
    expect(r.targetZm, moreOrLessEquals(2.5, epsilon: 1e-9));
    final diag = math.sqrt(400 * 400 + 500 * 500) / 100.0;
    expect(r.distanceM, moreOrLessEquals(math.max(2.2, diag * 0.85),
        epsilon: 1e-9));
    expect(r.polarRad, moreOrLessEquals(0.95, epsilon: 1e-9),
        reason: 'opens at the elevated 3/4 top view');
  });
}
