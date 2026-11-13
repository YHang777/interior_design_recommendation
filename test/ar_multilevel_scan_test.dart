import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/cloud_zone_builder.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/placement_policy.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_memory.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_overlay_math.dart';
import 'package:vector_math/vector_math_64.dart';

// Level-2 balcony scene, session origin at the phone: the balcony slab sits
// 1.4 m under the phone, the railing runs along z = 1.6, and the level-1
// courtyard lies one storey (3 m) further down beyond it.
const cameraY = 0.0;
const balconyY = -1.4;
const groundY = -4.4;

ARPlaneInfo horizontal(int id,
        {required double y,
        double cx = 0,
        double cz = 0.8,
        double ex = 3.0,
        double ez = 1.5}) =>
    ARPlaneInfo(
      id: id,
      planeType: 1,
      centerX: cx,
      centerY: y,
      centerZ: cz,
      extentX: ex,
      extentZ: ez,
      yaw: 0,
    );

ARPlaneInfo balcony() => horizontal(1, y: balconyY);

// Courtyard below, mostly beyond the railing but its outline reaches back
// under the balcony footprint (ARCore extends planes under overhangs).
ARPlaneInfo courtyard() =>
    horizontal(2, y: groundY, cz: 3.5, ex: 8.0, ez: 6.0);

ARHitTestResult floorHit(
    {required double x, required double y, required double z,
    double ex = 3, double ez = 3}) {
  final m = Matrix4.identity()..setTranslation(Vector3(x, y, z));
  final d = math.sqrt(x * x + (y - cameraY) * (y - cameraY) + z * z);
  return ARHitTestResult(ARHitTestResultType.plane, d, m,
      planeType: 1, planeExtentX: ex, planeExtentZ: ez);
}

void main() {
  group('balcony over a lower level — floor height', () {
    test('both levels visible with a known camera → floorY is the balcony', () {
      final m = PlaneMemory()..noteCameraY(cameraY);
      m.ingest([balcony(), courtyard()]);
      expect(m.floorY, closeTo(balconyY, 1e-9));
      expect(m.floorYRenderTrusted, isTrue);
      expect(m.classOf(1), PlaneClass.floor);
      expect(m.classOf(2), isNot(PlaneClass.floor));
    });

    test('courtyard seen before the first camera pose snaps back to the '
        'balcony as soon as the pose lands', () {
      final m = PlaneMemory();
      m.ingest([balcony(), courtyard()]);
      expect(m.floorY, closeTo(groundY, 1e-9),
          reason: 'precondition: with no camera height lowest wins');
      m.noteCameraY(cameraY);
      expect(m.floorY, closeTo(balconyY, 1e-6),
          reason: 'a floorY 4.4 m under the phone is provably not the floor '
              'being stood on — one update must land on the balcony');
      expect(m.floorYRenderTrusted, isTrue);
      m.ingest([balcony(), courtyard()]);
      m.ingest([balcony(), courtyard()]);
      expect(m.classOf(1), PlaneClass.floor);
    });

    test('a courtyard hit under the balcony footprint never inherits the '
        "balcony's floor class", () {
      final m = PlaneMemory()..noteCameraY(cameraY);
      m.ingest([balcony(), courtyard()]);
      m.ingest([balcony(), courtyard()]);
      expect(m.classNear(0.5, balconyY, 1.0, planeType: 1), PlaneClass.floor);
      expect(m.classNear(0.5, groundY, 1.0, planeType: 1),
          isNot(PlaneClass.floor));
    });

    test('depth points from the courtyard never pull floorY down', () {
      final m = PlaneMemory()..noteCameraY(cameraY);
      m.ingest([balcony(), courtyard()]);
      final pts = <double>[
        for (var i = 0; i < 400; i++) ...[
          (i % 20) * 0.3 - 3,
          groundY + (i % 7) * 0.005,
          2.0 + (i ~/ 20) * 0.2,
        ],
        for (var i = 0; i < 40; i++) ...[(i % 10) * 0.2 - 1, balconyY, 0.6],
      ];
      for (var i = 0; i < 30; i++) {
        final probe = floorProbeCandidate(points: pts, refY: m.floorY!);
        if (probe != null) m.noteFloorYCandidate(probe);
      }
      expect(m.floorY, closeTo(balconyY, 0.05));
    });

    test('placement refuses a big courtyard hit once floorY is the balcony',
        () {
      final hits = [
        floorHit(x: 0.5, y: groundY, z: 2.0, ex: 8, ez: 6),
        floorHit(x: 0.2, y: balconyY, z: 0.9),
      ];
      final best = ArPlacementPolicy.chooseFloorHit(hits,
          liveFloorY: balconyY, vouchedFloor: (_) => true);
      expect(best, isNotNull);
      expect(ArPlacementPolicy.worldY(best!), closeTo(balconyY, 1e-9));
      final only = ArPlacementPolicy.chooseFloorHit(
          [floorHit(x: 0.5, y: groundY, z: 2.0, ex: 8, ez: 6)],
          liveFloorY: balconyY,
          vouchedFloor: (_) => true);
      expect(only, isNull);
    });
  });

  group('balcony over a lower level — overlay paint', () {
    test('the courtyard is never the overlay reference plane', () {
      final lowest = overlayLowestPlaneY(
        planes: [balcony(), courtyard()],
        liveIds: {1, 2},
        cameraY: cameraY,
      );
      expect(lowest, closeTo(balconyY, 1e-9));
    });

    test('untrusted window: balcony paints green, courtyard drops', () {
      final lowest = overlayLowestPlaneY(
        planes: [balcony(), courtyard()],
        liveIds: {1, 2},
        cameraY: cameraY,
      );
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: balconyY,
            cameraY: cameraY,
            lowestPlaneY: lowest),
        OverlayZoneKind.floor,
      );
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: groundY,
            cameraY: cameraY,
            lowestPlaneY: lowest),
        OverlayZoneKind.drop,
      );
    });

    test('trusted window: courtyard drops below the balcony floor', () {
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: groundY,
            floorY: balconyY,
            floorYTrusted: true,
            cameraY: cameraY,
            lowestPlaneY: balconyY),
        OverlayZoneKind.drop,
      );
    });

    test('with no reference at all a plane a storey down drops, not masks',
        () {
      expect(
        overlayZoneOf(planeType: 1, centerY: groundY, cameraY: cameraY),
        OverlayZoneKind.drop,
        reason: 'a mask a storey down punches placement holes over the '
            'railing for nothing',
      );
    });

    test('a held ghost far below a known floor stays excluded', () {
      final lowest = overlayLowestPlaneY(
        planes: [balcony(), horizontal(9, y: balconyY - 0.9)],
        liveIds: {1},
        floorY: balconyY,
        cameraY: cameraY,
      );
      expect(lowest, closeTo(balconyY, 1e-9));
    });

    test('a real lower floor inside the camera band still anchors', () {
      // Ordinary room: a table at 0.75 under a 1.5 m phone and the floor.
      final lowest = overlayLowestPlaneY(
        planes: [horizontal(1, y: 0.75), horizontal(2, y: 0.0)],
        liveIds: {1, 2},
        floorY: 0.75,
        cameraY: 1.5,
      );
      expect(lowest, closeTo(0.0, 1e-9));
    });
  });
}
