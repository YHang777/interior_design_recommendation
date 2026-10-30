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
  });
}
