import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/scanner/data/camera_rig.dart';

void main() {
  group('OrbitRig', () {
    test('frameRoom targets the room center from an elevated 3/4 view', () {
      final rig = OrbitRig.frameRoom(roomWCm: 400, roomHCm: 500);
      expect(rig.targetXm, closeTo(2.0, 1e-9));
      expect(rig.targetZm, closeTo(2.5, 1e-9));
      expect(rig.polarRad, lessThan(pi / 2), reason: 'stays above eye level');
      expect(rig.polarRad, greaterThan(0.3), reason: 'opens from a top-ish view');

      final pose = rig.pose;
      expect(pose.targetX, closeTo(2.0, 1e-9));
      expect(pose.targetY, 0);
      expect(pose.targetZ, closeTo(2.5, 1e-9));
      expect(pose.eyeY, greaterThan(0), reason: 'camera never dips below the floor');
      final dx = pose.eyeX - pose.targetX;
      final dy = pose.eyeY - pose.targetY;
      final dz = pose.eyeZ - pose.targetZ;
      expect(sqrt(dx * dx + dy * dy + dz * dz), closeTo(rig.distanceM, 1e-9));
    });

    test('orbit clamps the polar angle and wraps azimuth', () {
      final rig = OrbitRig.frameRoom(roomWCm: 400, roomHCm: 500);
      rig.orbit(0, 100);
      expect(rig.polarRad, 1.45);
      rig.orbit(0, -100);
      expect(rig.polarRad, 0.05);
      rig.orbit(3 * pi, 0);
      expect(rig.azimuthRad, inInclusiveRange(-pi, pi));
    });

    test('dolly clamps to the room framing', () {
      final rig = OrbitRig.frameRoom(roomWCm: 400, roomHCm: 500);
      rig.dolly(1000);
      expect(rig.distanceM, rig.maxDistanceM);
      rig.dolly(0.0001);
      expect(rig.distanceM, 0.8);
    });
  });

  group('FirstPersonRig', () {
    test('pose maps walker cm to an eye in scene meters', () {
      final rig = FirstPersonRig();
      final pose = rig.pose(walkerXCm: 200, walkerYCm: 250, headingRad: 0);
      expect(pose.eyeX, closeTo(2.0, 1e-9));
      expect(pose.eyeY, closeTo(1.5, 1e-9));
      expect(pose.eyeZ, closeTo(2.5, 1e-9));
      expect(pose.targetY - pose.eyeY, closeTo(sin(-0.08), 1e-9));
      expect(pose.targetX - pose.eyeX, closeTo(cos(-0.08), 1e-9));
      expect(pose.targetZ, closeTo(2.5, 1e-9), reason: 'heading 0 looks east');
    });

    test('heading rotates the look direction over the plan', () {
      final rig = FirstPersonRig(pitchRad: 0);
      final pose = rig.pose(walkerXCm: 0, walkerYCm: 0, headingRad: pi / 2);
      expect(pose.targetX, closeTo(0, 1e-9), reason: 'south is +Z');
      expect(pose.targetZ, closeTo(1.0, 1e-9));
    });

    test('look and zoom clamp to safe ranges', () {
      final rig = FirstPersonRig();
      rig.look(10);
      expect(rig.pitchRad, 0.45);
      rig.look(-10);
      expect(rig.pitchRad, -0.6);
      rig.zoomFov(100);
      expect(rig.fovDeg, 95);
      rig.zoomFov(-100);
      expect(rig.fovDeg, 35);
    });

    test('setZoom maps the walkthrough zoom onto the lens', () {
      final rig = FirstPersonRig();
      rig.setZoom(1);
      expect(rig.fovDeg, 70);
      rig.setZoom(1.25);
      expect(rig.fovDeg, closeTo(56, 1e-9), reason: 'zooming in narrows');
      rig.setZoom(2);
      expect(rig.fovDeg, 35, reason: 'narrow end clamps');
      rig.setZoom(0.5);
      expect(rig.fovDeg, 95, reason: 'wide end clamps');
    });
  });
}
