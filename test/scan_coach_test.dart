import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/scan_coach.dart';

ARPlaneInfo _floor({double x = 0, double z = 0}) => ARPlaneInfo(
      planeType: 1,
      centerX: 0,
      centerY: -0.5,
      centerZ: 0,
      extentX: x,
      extentZ: z,
    );

ARPlaneInfo _wall({double x = 2, double z = 1}) => ARPlaneInfo(
      planeType: 2,
      centerX: 0,
      centerY: 0,
      centerZ: 0,
      extentX: x,
      extentZ: z,
    );

void main() {
  group('ScanCoach.evaluate', () {
    test('no planes → find the floor, no progress', () {
      final s = ScanCoach.evaluate(planes: const [], elapsed: Duration.zero);
      expect(s.step, ScanCoachStep.findFloor);
      expect(s.ready, isFalse);
      expect(s.progress, 0);
      expect(s.tip, 'Tilt down until the floor fills the view');
    });

    test('long wait with nothing detected suggests lighting', () {
      final s = ScanCoach.evaluate(
        planes: const [],
        elapsed: const Duration(seconds: 5),
      );
      expect(s.step, ScanCoachStep.findFloor);
      expect(s.tip, 'Check the lighting and hold still');
    });

    test('vertical planes alone never leave the first step', () {
      final s =
          ScanCoach.evaluate(planes: [_wall()], elapsed: Duration.zero);
      expect(s.step, ScanCoachStep.findFloor);
      expect(s.ready, isFalse);
    });

    test('small floor patch advances to sweeping', () {
      final s = ScanCoach.evaluate(
        planes: [_floor(x: 0.35, z: 0.4)],
        elapsed: Duration.zero,
      );
      expect(s.step, ScanCoachStep.sweepFloor);
      expect(s.progress, closeTo(0.35, 0.01));
    });

    test('wider floor asks to map more', () {
      final s = ScanCoach.evaluate(
        planes: [_floor(x: 0.9, z: 0.5)],
        elapsed: Duration.zero,
      );
      expect(s.step, ScanCoachStep.expandCoverage);
      expect(s.ready, isFalse);
    });

    test('both axes at the placement gate → ready', () {
      final s = ScanCoach.evaluate(
        planes: [_floor(x: 1.1, z: 1.0)],
        elapsed: Duration.zero,
        floorY: -0.5,
      );
      expect(s.step, ScanCoachStep.ready);
      expect(s.ready, isTrue);
      expect(s.progress, 1.0);
      expect(s.tip, 'Ready — tap the floor to place');
    });

    test('largest plane wins', () {
      final s = ScanCoach.evaluate(
        planes: [
          _floor(x: 0.2, z: 0.2),
          _floor(x: 1.2, z: 1.1),
        ],
        elapsed: Duration.zero,
        floorY: -0.5,
      );
      expect(s.ready, isTrue);
    });

    test('excessive motion is shown as slow down', () {
      final s = ScanCoach.evaluate(
        planes: const [],
        elapsed: Duration.zero,
        trackingIssue: 'EXCESSIVE_MOTION',
      );
      expect(s.hasIssue, isTrue);
      expect(s.tip, contains('Slow down'));
    });

    test('tracking issue overrides the step tip', () {
      final s = ScanCoach.evaluate(
        planes: [_floor(x: 1.1, z: 1.0)],
        elapsed: Duration.zero,
        floorY: -0.5,
        trackingIssue: 'INSUFFICIENT_LIGHT',
      );
      expect(s.ready, isTrue);
      expect(s.hasIssue, isTrue);
      expect(s.tip, contains('Too dark'));
    });

    test('a table top does not fake floor coverage', () {
      final s = ScanCoach.evaluate(
        planes: [
          ARPlaneInfo(
            planeType: 1,
            centerX: 0,
            centerY: 0.75,
            centerZ: 0,
            extentX: 1.4,
            extentZ: 1.1,
          ),
        ],
        elapsed: Duration.zero,
        floorY: 0,
      );
      expect(s.ready, isFalse);
      expect(s.tip, 'That looks like furniture — scan the open floor');
    });

    test('floor-level coverage still counts beside furniture', () {
      final s = ScanCoach.evaluate(
        planes: [
          ARPlaneInfo(
            planeType: 1,
            centerX: 0,
            centerY: -0.5,
            centerZ: 0,
            extentX: 1.2,
            extentZ: 1.1,
          ),
          ARPlaneInfo(
            planeType: 1,
            centerX: 0,
            centerY: 0.75,
            centerZ: 0,
            extentX: 1.4,
            extentZ: 1.1,
          ),
        ],
        elapsed: Duration.zero,
        floorY: -0.5,
      );
      expect(s.ready, isTrue);
    });

    test('merged floor coverage from the memory can lift a sweep to ready',
        () {
      final s = ScanCoach.evaluate(
        planes: [_floor(x: 0.6, z: 0.7)],
        elapsed: Duration.zero,
        floorY: -0.5,
        floorCoverageM: 1.4,
      );
      expect(s.ready, isTrue);
      expect(s.progress, 1.0);
    });

    test('zero merged coverage never fakes readiness', () {
      final s = ScanCoach.evaluate(
        planes: [
          ARPlaneInfo(
            planeType: 1,
            centerX: 0,
            centerY: 0.75,
            centerZ: 0,
            extentX: 1.4,
            extentZ: 1.1,
          ),
        ],
        elapsed: Duration.zero,
        floorY: 0,
        floorCoverageM: 0.0,
      );
      expect(s.ready, isFalse);
    });

    test('NONE or unknown tracking reasons are ignored', () {
      expect(ScanCoach.issueTip('NONE'), isNull);
      expect(ScanCoach.issueTip(null), isNull);
      expect(ScanCoach.issueTip('SOMETHING_ELSE'), isNull);
    });

    test('partial coverage is not ready before the relaxation window', () {
      final s = ScanCoach.evaluate(
        planes: [_floor(x: 0.8, z: 0.75)],
        elapsed: const Duration(seconds: 17),
      );
      expect(s.ready, isFalse);
      expect(s.step, ScanCoachStep.expandCoverage);
    });

    test('after the relaxation window a partial floor is ready', () {
      final s = ScanCoach.evaluate(
        planes: [_floor(x: 0.8, z: 0.75)],
        elapsed: const Duration(seconds: 20),
        floorY: -0.5,
      );
      expect(s.ready, isTrue);
      expect(s.step, ScanCoachStep.ready);
      expect(s.progress, 1.0);
    });

    test('relaxation still ignores furniture as coverage', () {
      final s = ScanCoach.evaluate(
        planes: [
          ARPlaneInfo(
            planeType: 1,
            centerX: 0,
            centerY: 0.75,
            centerZ: 0,
            extentX: 1.4,
            extentZ: 1.1,
          ),
        ],
        elapsed: const Duration(seconds: 20),
        floorY: 0,
      );
      expect(s.ready, isFalse);
    });

    test('never ready without an established floor height', () {
      // Coverage alone must not promise placement — placement refuses
      // while liveFloorY is null, so neither may the coach.
      final s = ScanCoach.evaluate(
        planes: [_floor(x: 1.2, z: 1.1)],
        elapsed: const Duration(seconds: 20),
      );
      expect(s.ready, isFalse);
      expect(s.tip, isNot('Ready — tap the floor to place'));
    });

    test('while floorY is unknown, a desk is not floor coverage', () {
      final s = ScanCoach.evaluate(
        planes: [
          ARPlaneInfo(
            planeType: 1,
            centerX: 0,
            centerY: 0.75,
            centerZ: 0,
            extentX: 1.4,
            extentZ: 1.1,
          ),
        ],
        elapsed: Duration.zero,
        cameraY: 1.5,
      );
      expect(s.ready, isFalse);
      expect(s.step, ScanCoachStep.findFloor);
      expect(s.tip, 'Tilt down until the floor fills the view');
    });

    test('while floorY is unknown, a camera-plausible floor still counts', () {
      final s = ScanCoach.evaluate(
        planes: [_floor(x: 0.35, z: 0.4)],
        elapsed: Duration.zero,
        cameraY: 1.5,
      );
      expect(s.step, ScanCoachStep.sweepFloor);
    });
  });

  group('camera pitch guidance', () {
    test('a shallow camera gets the hold-angle tip', () {
      final s = ScanCoach.evaluate(
        planes: const [],
        elapsed: Duration.zero,
        cameraPitchDeg: -8,
      );
      expect(s.tip, 'Point the camera down about 30° toward the floor');
      expect(s.hasIssue, isFalse);
    });

    test('enough tilt keeps the step tip', () {
      final s = ScanCoach.evaluate(
        planes: const [],
        elapsed: Duration.zero,
        cameraPitchDeg: -45,
      );
      expect(s.tip, 'Tilt down until the floor fills the view');
    });

    test('right at the threshold the angle tip stays quiet', () {
      final s = ScanCoach.evaluate(
        planes: const [],
        elapsed: Duration.zero,
        cameraPitchDeg: ScanCoach.shallowPitchDeg,
      );
      expect(s.tip, 'Tilt down until the floor fills the view');
    });

    test('a tracking issue beats the pitch tip', () {
      final s = ScanCoach.evaluate(
        planes: const [],
        elapsed: Duration.zero,
        cameraPitchDeg: -5,
        trackingIssue: 'EXCESSIVE_MOTION',
      );
      expect(s.tip, contains('Slow down'));
    });

    test('ready never shows the pitch tip', () {
      final s = ScanCoach.evaluate(
        planes: [_floor(x: 1.1, z: 1.0)],
        elapsed: Duration.zero,
        floorY: -0.5,
        cameraPitchDeg: -5,
      );
      expect(s.ready, isTrue);
      expect(s.tip, 'Ready — tap the floor to place');
    });

    test('a missing pitch reading falls back to the step tip', () {
      final s = ScanCoach.evaluate(
        planes: const [],
        elapsed: Duration.zero,
        cameraPitchDeg: null,
      );
      expect(s.tip, 'Tilt down until the floor fills the view');
      expect(ScanCoach.pitchTip(null), isNull);
      expect(ScanCoach.pitchTip(double.nan), isNull);
      expect(ScanCoach.pitchTip(-30), isNull);
      expect(ScanCoach.pitchTip(-10), isNotNull);
    });
  });

  group('ScanCoach wall intent', () {
    test('no planes → findWall with the corner tip', () {
      final s = ScanCoach.evaluate(
        planes: const [],
        elapsed: Duration.zero,
        wall: true,
      );
      expect(s.step, ScanCoachStep.findWall);
      expect(s.ready, isFalse);
      expect(s.wall, isTrue);
      expect(s.tip, contains('corner'));
    });

    test('floor planes never advance the wall ladder', () {
      final s = ScanCoach.evaluate(
        planes: [_floor(x: 1.2, z: 1.1)],
        elapsed: Duration.zero,
        wall: true,
      );
      expect(s.step, ScanCoachStep.findWall);
      expect(s.ready, isFalse);
      expect(s.progress, 0);
    });

    test('a partial wall asks to sweep it', () {
      final s = ScanCoach.evaluate(
        planes: [_wall(x: 1.0, z: 0.5)],
        elapsed: Duration.zero,
        wall: true,
      );
      expect(s.step, ScanCoachStep.sweepWall);
      expect(s.ready, isFalse);
      expect(s.progress, greaterThan(0));
      expect(s.progress, lessThan(1));
      expect(s.tip, contains('Move left and right'));
    });

    test('a wall at both placement gates → ready without any floorY', () {
      final s = ScanCoach.evaluate(
        planes: [_wall(x: 2, z: 1.5)],
        elapsed: Duration.zero,
        wall: true,
      );
      expect(s.step, ScanCoachStep.ready);
      expect(s.ready, isTrue);
      expect(s.progress, 1.0);
      expect(s.tip, 'Ready — tap the wall to place');
    });

    test('wall mode never shows the floor pitch tip', () {
      final s = ScanCoach.evaluate(
        planes: const [],
        elapsed: Duration.zero,
        cameraPitchDeg: -5,
        wall: true,
      );
      expect(s.tip, isNot('Point the camera down about 30° toward the floor'));
      expect(s.tip, contains('wall'));
    });

    test('a tracking issue overrides the wall tip', () {
      final s = ScanCoach.evaluate(
        planes: const [],
        elapsed: Duration.zero,
        trackingIssue: 'EXCESSIVE_MOTION',
        wall: true,
      );
      expect(s.hasIssue, isTrue);
      expect(s.tip, contains('Slow down'));
    });

    test('sweepWall tips rotate after the first entry has had its turn', () {
      final early = ScanCoach.evaluate(
        planes: [_wall(x: 1.0, z: 0.5)],
        elapsed: Duration.zero,
        wall: true,
      );
      expect(early.tip, contains('Move left and right'));

      final later = ScanCoach.evaluate(
        planes: [_wall(x: 1.0, z: 0.5)],
        elapsed: const Duration(seconds: 6),
        wall: true,
      );
      expect(later.tip, contains('Step back'));
    });
  });

  group('ScanCoach white-surface tip rotation', () {
    test('the classic lighting tip keeps the early slot', () {
      final s = ScanCoach.evaluate(
        planes: const [],
        elapsed: const Duration(seconds: 5),
      );
      expect(s.tip, 'Check the lighting and hold still');
    });

    test('findFloor tips rotate once the classic tip has had its turn', () {
      final s = ScanCoach.evaluate(
        planes: const [],
        elapsed: const Duration(seconds: 6),
      );
      expect(s.tip, 'Move slowly side to side — white floors need parallax');

      final s2 = ScanCoach.evaluate(
        planes: const [],
        elapsed: const Duration(seconds: 12),
      );
      expect(s2.tip, 'Aim near a rug, edge, or seam for something to lock onto');
    });

    test('sweepFloor tips rotate too', () {
      final s = ScanCoach.evaluate(
        planes: [_floor(x: 0.35, z: 0.4)],
        elapsed: const Duration(seconds: 6),
      );
      expect(s.step, ScanCoachStep.sweepFloor);
      expect(s.tip, contains('Kneel'));
    });
  });
}
