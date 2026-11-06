import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_memory.dart';

ARPlaneInfo plane({
  required int id,
  required int type,
  double cx = 0,
  double cy = 0,
  double cz = 2,
  double yaw = 0,
  required double ex,
  required double ez,
  bool fresh = true,
}) {
  return ARPlaneInfo(
    id: id,
    planeType: type,
    centerX: cx,
    centerY: cy,
    centerZ: cz,
    extentX: ex,
    extentZ: ez,
    yaw: yaw,
    fresh: fresh,
  );
}

void main() {
  group('PlaneMemory floor establishment', () {
    test('one large floor plane → floorY established at its height', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 1, type: 1, cy: -0.02, ex: 3, ez: 3)]);
      expect(m.floorEstablished, isTrue);
      expect(m.floorY, closeTo(-0.02, 1e-9));
      expect(m.classOf(1), PlaneClass.floor);
    });

    test('small horizontal planes never establish the floor', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.1, ez: 0.8)]);
      expect(m.floorEstablished, isFalse);
    });

    test('relaxGates lets a small real floor establish and classify', () {
      final m = PlaneMemory();
      final patch = plane(id: 1, type: 1, cy: -0.02, ex: 1.0, ez: 0.9);
      m.ingest([patch]);
      expect(m.floorEstablished, isFalse);
      m.relaxGates();
      m.ingest([patch]);
      expect(m.floorEstablished, isTrue);
      expect(m.floorY, closeTo(-0.02, 1e-9));
      // The unknown→floor flip still needs the usual two agreeing frames.
      m.ingest([patch]);
      expect(m.classOf(1), PlaneClass.floor);
    });

    test('relaxGates is idempotent', () {
      final m = PlaneMemory();
      m.relaxGates();
      m.minFloorEstablishExtentM = 0.5;
      m.relaxGates();
      expect(m.minFloorEstablishExtentM, 0.5,
          reason: 'a second call must not clobber custom state');
    });

    test('once relaxed, the loose camera window cannot lock the floor', () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      m.relaxGates();
      // A bed top 1.0 m × 2.0 m clears the relaxed 0.9 m establish gate but
      // sits only 0.55 m below the phone — outside the strict prior.
      m.ingest([plane(id: 1, type: 1, cy: 0.95, ex: 1.0, ez: 2.0)]);
      expect(m.floorEstablished, isFalse,
          reason: 'a bed must not become floorY and then refuse the real '
              'floor via the height gate');
    });

    test('once relaxed, a strict-band surface still establishes', () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      m.relaxGates();
      m.ingest([plane(id: 1, type: 1, cy: 0.0, ex: 0.95, ez: 1.4)]);
      expect(m.floorEstablished, isTrue);
      expect(m.floorY, closeTo(0.0, 1e-9));
    });

    test('camera prior rejects a surface just below the phone', () {
      final m = PlaneMemory();
      m.noteCameraY(2.0);
      m.ingest([plane(id: 1, type: 1, cy: 1.9, ex: 2, ez: 2)]);
      expect(m.floorEstablished, isFalse);
    });

    test('a big table top seen first may establish provisionally, then the '
        'real floor corrects it (the memory feature)', () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      // Round 1: only the dining table is scanned — it looks like the floor.
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2)]);
      expect(m.floorY, closeTo(0.75, 1e-9));
      expect(m.classOf(1), PlaneClass.floor);

      // Round 2: the actual floor enters view — floorY corrects downward.
      m.ingest([
        plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2),
        plane(id: 2, type: 1, cy: 0.0, ex: 3, ez: 3),
      ]);
      expect(m.floorY, lessThan(0.15));

      // Round 3: the table keeps disagreeing — it flips to furniture.
      m.ingest([
        plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2),
        plane(id: 2, type: 1, cy: 0.0, ex: 3, ez: 3),
      ]);
      expect(m.floorY, closeTo(0.0, 0.05));
      expect(m.classOf(1), PlaneClass.elevatedSurface);
      expect(m.classOf(2), PlaneClass.floor);
    });

    test('floorY survives the floor leaving view (memory)', () {
      final m = PlaneMemory();
      final t0 = DateTime(2026, 10, 29, 10);
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)], now: t0);
      m.ingest(const [], now: t0.add(const Duration(seconds: 5)));
      expect(m.floorY, closeTo(0, 1e-9));
    });

    test('no camera height → lowest large plane still wins', () {
      final m = PlaneMemory();
      m.ingest([
        plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2),
        plane(id: 2, type: 1, cy: 0.0, ex: 3, ez: 3),
      ]);
      expect(m.floorY, closeTo(0, 1e-9));
    });
  });

  group('PlaneMemory classification', () {
    test('chair seat height is elevated once the floor is known', () {
      final m = PlaneMemory();
      m.ingest([
        plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3),
        plane(id: 2, type: 1, cy: 0.45, ex: 0.6, ez: 0.6),
      ]);
      expect(m.classOf(2), PlaneClass.elevatedSurface);
    });

    test('a wardrobe-sized vertical plane is a wall', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 1, type: 2, cy: 1, ex: 2.5, ez: 2.0)]);
      expect(m.classOf(1), PlaneClass.wall);
    });

    test('a chair back / cabinet side is never a wall', () {
      final m = PlaneMemory();
      m.ingest([
        plane(id: 1, type: 2, cy: 0.5, ex: 0.9, ez: 0.5),
        plane(id: 2, type: 2, cy: 1.0, ex: 1.8, ez: 0.6),
      ]);
      expect(m.classOf(1), PlaneClass.smallSurface);
      expect(m.classOf(2), PlaneClass.smallSurface);
    });

    test('reclassification needs repeated evidence (no flicker)', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 1, type: 2, cy: 1, ex: 1.6, ez: 1.5)]);
      expect(m.classOf(1), PlaneClass.wall);
      // ARCore re-refines the plane down to a sliver: one frame of
      // disagreement keeps the old label…
      m.ingest([plane(id: 1, type: 2, cy: 1, ex: 1.0, ez: 0.5)]);
      expect(m.classOf(1), PlaneClass.wall);
      // …two consecutive ones correct it.
      m.ingest([plane(id: 1, type: 2, cy: 1, ex: 1.0, ez: 0.5)]);
      expect(m.classOf(1), PlaneClass.smallSurface);
    });
  });

  group('PlaneMemory smoothing', () {
    test('centers glide toward new frames instead of jumping', () {
      final m = PlaneMemory(centerAlpha: 0.35);
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)]);
      // Sub-threshold jitter smooths; a re-fit jump past 0.15 m snaps
      // instead (see the re-fit reopen group).
      m.ingest([plane(id: 1, type: 1, cy: 0.05, ex: 3, ez: 3)]);
      final smoothed = m.smoothedPlanes().single;
      expect(smoothed.centerY, closeTo(0.05 * 0.35, 1e-9));
    });
  });

  group('PlaneMemory freshness', () {
    test('a fresh ingest marks the memory fresh', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)]);
      expect(m.isFresh, isTrue);
    });
  });

  group('PlaneMemory id-less association (stale plugin)', () {
    test('jittering centers without ids keep ONE record (smoothing survives)',
        () {
      final m = PlaneMemory(centerAlpha: 0.35);
      m.ingest([plane(id: 0, type: 1, cy: 0, ex: 3, ez: 3)]);
      m.ingest([plane(id: 0, type: 1, cx: 0.05, cy: 0.02, ex: 3, ez: 3)]);
      final smoothed = m.smoothedPlanes();
      expect(smoothed, hasLength(1), reason: 'the second frame must absorb '
          'into the first record, not open a new one');
      expect(smoothed.single.centerY, closeTo(0.02 * 0.35, 1e-9));
    });

    test('distant id-less planes stay separate records', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 0, type: 1, cy: 0, ex: 3, ez: 3)]);
      m.ingest([plane(id: 0, type: 1, cx: 3, cy: 0.75, cz: 2, ex: 1, ez: 1)]);
      expect(m.smoothedPlanes(), hasLength(2));
    });

    test('id-less reclassification still accumulates votes', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 0, type: 2, cy: 1, ex: 1.6, ez: 1.5)]);
      final big = m.smoothedPlanes().single;
      expect(m.classNear(big.centerX, big.centerY, big.centerZ, planeType: 2),
          PlaneClass.wall);
      m.ingest([plane(id: 0, type: 2, cy: 1, ex: 1.0, ez: 0.5)]);
      m.ingest([plane(id: 0, type: 2, cy: 1, ex: 1.0, ez: 0.5)]);
      expect(m.classNear(big.centerX, big.centerY, big.centerZ, planeType: 2),
          PlaneClass.smallSurface);
    });
  });

  group('PlaneMemory separated floor / wall streams', () {
    test('ceilings and odd types are ignored by both streams', () {
      final m = PlaneMemory();
      m.ingest([
        plane(id: 1, type: 0, cy: 2.5, ex: 4, ez: 4),
        plane(id: 2, type: 3, cy: 1, ex: 3, ez: 3),
      ]);
      expect(m.smoothedPlanes(), isEmpty);
      expect(m.floorY, isNull);
    });

    test('a wall can never influence the floor height', () {
      final m = PlaneMemory();
      m.ingest([
        plane(id: 1, type: 2, cy: 0.2, ex: 3, ez: 2.5),
        plane(id: 2, type: 1, cy: 0, ex: 3, ez: 3),
      ]);
      expect(m.floorY, closeTo(0, 1e-9));
      expect(m.floorPlanes.map((p) => p.id), [2]);
      expect(m.wallPlanes.map((p) => p.id), [1]);
    });

    test('a floor fragment can never vouch a wall', () {
      final m = PlaneMemory();
      m.ingest([
        plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3),
        plane(id: 2, type: 2, cy: 1, ex: 1.0, ez: 0.6),
      ]);
      // The small vertical sliver stays smallSurface even though a big
      // floor record sits at the same spot.
      expect(m.classNear(0, 1, 2, planeType: 2), PlaneClass.smallSurface);
      expect(m.classNear(0, 0, 2, planeType: 1), PlaneClass.floor);
    });
  });

  group('PlaneMemory yaw smoothing', () {
    test('yaw glides toward new frames instead of snapping', () {
      final m = PlaneMemory(centerAlpha: 0.5);
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3, yaw: 0)]);
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3, yaw: 1.0)]);
      expect(m.smoothedPlanes().single.yaw, closeTo(0.5, 1e-9));
    });

    test('yaw glides across the ±π seam, not through zero', () {
      final m = PlaneMemory(centerAlpha: 0.5);
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3, yaw: 3.0)]);
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3, yaw: -3.0)]);
      expect(m.smoothedPlanes().single.yaw.abs(), greaterThan(math.pi / 2));
    });
  });

  group('PlaneMemory synthetic ids', () {
    test('id-less records get unique negative ids so classOf can address them',
        () {
      final m = PlaneMemory();
      m.ingest([
        plane(id: 0, type: 1, cy: 0, ex: 3, ez: 3),
        plane(id: 0, type: 2, cx: 5, cy: 1, cz: 5, ex: 1.6, ez: 1.5),
      ]);
      final smoothed = m.smoothedPlanes();
      expect(smoothed, hasLength(2));
      final ids = smoothed.map((p) => p.id).toList();
      expect(ids.every((id) => id < 0), isTrue);
      expect(ids.toSet(), hasLength(2));
      for (final p in smoothed) {
        expect(m.classOf(p.id), isNotNull);
      }
    });
  });

  group('PlaneMemory merged floor coverage', () {
    test('adjacent floor fragments accumulate into one region', () {
      final m = PlaneMemory();
      m.ingest([
        plane(id: 1, type: 1, cy: 0, cx: -0.5, cz: 1.4, ex: 1.0, ez: 1.0),
        plane(id: 2, type: 1, cy: 0, cx: 0.6, cz: 1.4, ex: 1.0, ez: 1.0),
        plane(id: 3, type: 1, cy: 0, cx: -0.5, cz: 2.5, ex: 1.0, ez: 1.0),
        plane(id: 4, type: 1, cy: 0, cx: 0.6, cz: 2.5, ex: 1.0, ez: 1.0),
      ]);
      // Four ~1 m patches swept in a 2×2 grid merge into one ~2.1 m region —
      // placement trusts the accumulated floor, not each fragment alone.
      expect(m.floorCoverageExtentM(), greaterThanOrEqualTo(2.0));
      expect(m.knowsFloorAt(-1.0, 1.0), isTrue);
      expect(m.knowsFloorAt(1.1, 3.0), isTrue);
    });

    test('far-apart fragments do not merge', () {
      final m = PlaneMemory();
      m.ingest([
        plane(id: 1, type: 1, cy: 0, ex: 1.2, ez: 1.2),
        plane(id: 2, type: 1, cy: 0, cx: 5, cz: 5, ex: 1.2, ez: 1.2),
      ]);
      expect(m.floorCoverageExtentM(), closeTo(1.2, 1e-9));
      expect(m.knowsFloorAt(5, 5), isTrue);
      expect(m.knowsFloorAt(2.5, 2.5), isFalse);
    });

    test('furniture tops are never part of the floor region', () {
      final m = PlaneMemory();
      m.ingest([
        plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3),
        plane(id: 2, type: 1, cy: 0.75, cx: 2.5, ex: 1.5, ez: 1.2),
      ]);
      expect(m.knowsFloorAt(2.5, 2), isFalse);
    });
  });

  group('PlaneMemory re-fit reopen', () {
    test('a floor height re-fit snaps and reclassifies from scratch', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)]);
      expect(m.classOf(1), PlaneClass.floor);

      // ARCore re-fits the surface 0.5 m up — gliding toward it would keep
      // the wrong height (and the latched floor class) alive for seconds.
      m.ingest([plane(id: 1, type: 1, cy: 0.5, ex: 3, ez: 3)]);
      expect(m.smoothedPlanes().single.centerY, closeTo(0.5, 1e-9),
          reason: 'a re-fit snaps to the fresh observation');
      expect(m.classOf(1), PlaneClass.elevatedSurface,
          reason: 'classification is re-proposed, not inherited');
    });

    test('an outline pull-back snaps the geometry', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)]);
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 1.0, ez: 3)]);
      expect(m.smoothedPlanes().single.extentX, closeTo(1.0, 1e-9),
          reason: 'a 2 m over-extension pulled back is a re-fit, not jitter');
      expect(m.classOf(1), PlaneClass.floor);
    });

    test('plain growth keeps gliding — growth is not a re-fit', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)]);
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 5, ez: 3)]);
      expect(m.smoothedPlanes().single.extentX, closeTo(3.6, 1e-9));
      expect(m.classOf(1), PlaneClass.floor);
    });
  });

  group('PlaneMemory clustered floorY', () {
    test('fragmented floor beats one big furniture top', () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      // Each floor fragment (0.8 m) is below the 1.2 m establish gate on
      // its own, but the coplanar 2×2 cluster merges to 1.8 m — while the
      // only gate-clearing plane (the table) sits alone in the loose band.
      m.ingest([
        plane(id: 1, type: 1, cy: 0, cx: -0.5, cz: 1.5, ex: 0.8, ez: 0.8),
        plane(id: 2, type: 1, cy: 0, cx: 0.5, cz: 1.5, ex: 0.8, ez: 0.8),
        plane(id: 3, type: 1, cy: 0, cx: -0.5, cz: 2.5, ex: 0.8, ez: 0.8),
        plane(id: 4, type: 1, cy: 0, cx: 0.5, cz: 2.5, ex: 0.8, ez: 0.8),
        plane(id: 5, type: 1, cy: 0.75, cx: 0, cz: 4, ex: 1.5, ez: 1.2),
      ]);
      expect(m.floorY, closeTo(0, 1e-9));
    });
  });

  group('PlaneMemory freshness (cached re-emits)', () {
    final t0 = DateTime(2026, 11, 6, 10);

    test('a cached re-emit keeps the record alive past recordMaxAge', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)], now: t0);
      expect(m.floorPlanes, hasLength(1));

      // A plane in the payload is TRACKING by construction — presence is
      // liveness, so a stable plane's cached re-emit keeps its record (and
      // the scan coach) alive no matter how quiet ARCore has gone.
      m.ingest(
          [plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3, fresh: false)],
          now: t0.add(const Duration(seconds: 20)));
      expect(m.floorPlanes, hasLength(1));
      // Aging a record never clears the height estimate.
      expect(m.floorY, closeTo(0, 1e-9));
    });

    test('fresh observations keep the record alive past recordMaxAge', () {
      final m = PlaneMemory();
      var t = t0;
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)], now: t);
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(seconds: 10));
        m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)], now: t);
      }
      expect(m.floorPlanes, hasLength(1));
    });

    test('payload absence prunes the record after recordMaxAge', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)], now: t0);
      m.ingest(const [], now: t0.add(const Duration(seconds: 13)));
      expect(m.floorPlanes, isEmpty);
      // Aging a record never clears the height estimate.
      expect(m.floorY, closeTo(0, 1e-9));
    });

    test('a later payload frame records the plane again even when non-fresh',
        () {
      final m = PlaneMemory();
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3, fresh: false)],
          now: t0);
      expect(m.floorPlanes, hasLength(1),
          reason: 'presence in the payload is liveness — freshness is not '
              'consulted');
      expect(m.floorEstablished, isTrue);

      // After an absence long enough to prune, the next frame — fresh or
      // not — rebuilds the record.
      m.ingest(const [], now: t0.add(const Duration(seconds: 13)));
      expect(m.floorPlanes, isEmpty);
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3, fresh: false)],
          now: t0.add(const Duration(seconds: 14)));
      expect(m.floorPlanes, hasLength(1));
    });

    test('freshMs in the payload maps to the fresh flag', () {
      // ≤1 s old = fresh (and a missing key reads as fresh — legacy
      // native sides keep the pre-flag behavior).
      expect(ARPlaneInfo.fromJson({'freshMs': 0}).fresh, isTrue);
      expect(ARPlaneInfo.fromJson({'freshMs': 999}).fresh, isTrue);
      expect(ARPlaneInfo.fromJson(<String, dynamic>{}).fresh, isTrue);
      expect(ARPlaneInfo.fromJson({'freshMs': 1001}).fresh, isFalse);
    });

    test('tracking maps from the payload with a legacy default', () {
      expect(ARPlaneInfo.fromJson({'tracking': false}).tracking, isFalse);
      expect(ARPlaneInfo.fromJson({'tracking': true}).tracking, isTrue);
      expect(ARPlaneInfo.fromJson(<String, dynamic>{}).tracking, isTrue,
          reason: 'legacy native sides read as tracking');
    });

    test('subsumed maps from the payload and defaults to false', () {
      expect(ARPlaneInfo.fromJson({'subsumed': true}).subsumed, isTrue);
      expect(ARPlaneInfo.fromJson({'subsumed': false}).subsumed, isFalse);
      expect(ARPlaneInfo.fromJson(<String, dynamic>{}).subsumed, isFalse,
          reason: 'legacy native sides never flag subsumption');
    });
  });

  group('PlaneMemory floorY probe candidate', () {
    test('never establishes floorY on its own', () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      m.noteFloorYCandidate(0.0);
      expect(m.floorEstablished, isFalse);
    });

    test('corrects a too-high floorY downward and reclassifies the '
        'wrong plane', () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      // The table top locked in as provisional floor.
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2)]);
      expect(m.floorY, closeTo(0.75, 1e-9));
      expect(m.classOf(1), PlaneClass.floor);

      // The probe finds the real floor below → same α 0.85 downward
      // correction the plane path uses.
      m.noteFloorYCandidate(0.0);
      expect(m.floorY, closeTo(0.75 * 0.15, 1e-9));
      // The next 1 Hz tick converges and the two agreeing reclassifications
      // flip the table off the floor class.
      m.noteFloorYCandidate(0.0);
      expect(m.floorY, lessThan(0.02));
      expect(m.classOf(1), PlaneClass.elevatedSurface,
          reason: 'once floorY drops, the floating plane stops '
              'classifying as floor');
    });

    test('a deadband stops noise and upward candidates from moving floorY',
        () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)]);
      expect(m.floorY, closeTo(0, 1e-9));

      m.noteFloorYCandidate(-0.02);
      expect(m.floorY, closeTo(0, 1e-9),
          reason: 'a low percentile reads slightly low on noise — a few '
              'centimetres must not drift the floor');
      m.noteFloorYCandidate(0.3);
      expect(m.floorY, closeTo(0, 1e-9),
          reason: 'the probe only ever corrects downward');
    });

    test('a candidate outside the camera band is ignored', () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2)]);
      expect(m.floorY, closeTo(0.75, 1e-9));

      // 2.5 m below the phone — outside the [0.5, 2.4] prior the plane
      // path trusts; garbage points must not drag floorY there.
      m.noteFloorYCandidate(-1.0);
      expect(m.floorY, closeTo(0.75, 1e-9));
    });

    test('a live probe correction survives the next plane ingest', () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2)]);
      expect(m.floorY, closeTo(0.75, 1e-9));

      m.noteFloorYCandidate(0.0);
      m.noteFloorYCandidate(0.0);
      expect(m.floorY, lessThan(0.02));
      expect(m.classOf(1), PlaneClass.elevatedSurface);

      // The wrong plane is the establishable one — without the probe hold
      // its ingest pulls floorY back up within a frame or two and the
      // refocus zone flip vanishes.
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2)]);
      expect(m.floorY, lessThan(0.15),
          reason: 'a probe within the hold window outranks the plane path');
      expect(m.classOf(1), PlaneClass.elevatedSurface);
    });

    test('the probe hold lapses so the plane path can repair floorY', () {
      final m = PlaneMemory();
      final t0 = DateTime(2026, 1, 1);
      m.noteCameraY(1.5, now: t0);
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2)], now: t0);
      m.noteFloorYCandidate(0.0, now: t0);
      expect(m.floorY, closeTo(0.75 * 0.15, 1e-9));

      // Hold still live — the plane path must not pull floorY back up.
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2)],
          now: t0.add(const Duration(seconds: 3)));
      expect(m.floorY, lessThan(0.15));

      // Past the 5 s hold the plane path repairs a too-low estimate again.
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2)],
          now: t0.add(const Duration(seconds: 6)));
      expect(m.floorY, greaterThan(0.15));
    });
  });

  group('PlaneMemory floorY render trust', () {
    test('a loose table-height establishment is not render-trusted', () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2)]);
      expect(m.floorY, closeTo(0.75, 1e-9));
      expect(m.floorYRenderTrusted, isFalse,
          reason: 'painting green at table height is the floating plane');
    });

    test('a strict-band floor establishment is render-trusted', () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)]);
      expect(m.floorY, closeTo(0, 1e-9));
      expect(m.floorYRenderTrusted, isTrue);
    });

    test('establishment without a camera height is not render-trusted', () {
      final m = PlaneMemory();
      m.ingest([plane(id: 1, type: 1, cy: 0, ex: 3, ez: 3)]);
      expect(m.floorEstablished, isTrue);
      expect(m.floorYRenderTrusted, isFalse,
          reason: 'no camera means no strict-band proof, even for a big floor');
    });

    test('a live probe correction proves the height for rendering', () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2)]);
      expect(m.floorYRenderTrusted, isFalse);

      m.noteFloorYCandidate(0.0);
      m.noteFloorYCandidate(0.0);
      expect(m.floorY, lessThan(0.02));
      expect(m.floorYRenderTrusted, isTrue,
          reason: 'the point cloud proved the real floor height');
    });

    test('plane-path drift away from the probe height drops trust', () {
      final m = PlaneMemory();
      final t0 = DateTime(2026, 1, 1);
      m.noteCameraY(1.5, now: t0);
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2)], now: t0);
      m.noteFloorYCandidate(0.0, now: t0);
      m.noteFloorYCandidate(0.0, now: t0);
      expect(m.floorYRenderTrusted, isTrue);

      // Past the 5 s hold the table drags floorY back up — once
      // |floorY − probeY| passes 0.25 the overlay must stop painting.
      m.ingest([plane(id: 1, type: 1, cy: 0.75, ex: 1.5, ez: 1.2)],
          now: t0.add(const Duration(seconds: 6)));
      expect(m.floorY, greaterThan(0.25));
      expect(m.floorYRenderTrusted, isFalse);
    });

    test('a probe with no floorY never establishes or proves anything', () {
      final m = PlaneMemory();
      m.noteCameraY(1.5);
      m.noteFloorYCandidate(0.0);
      expect(m.floorEstablished, isFalse);
      expect(m.floorYRenderTrusted, isFalse);
    });
  });
}
