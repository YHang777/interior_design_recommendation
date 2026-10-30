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
      m.ingest([plane(id: 1, type: 1, cy: 1.0, ex: 3, ez: 3)]);
      final smoothed = m.smoothedPlanes().single;
      expect(smoothed.centerY, closeTo(0.35, 1e-9));
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
}
