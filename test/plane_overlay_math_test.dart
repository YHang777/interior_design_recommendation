import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_overlay_math.dart';
import 'package:vector_math/vector_math_64.dart';

Matcher isOffset(double x, double y) =>
    predicate<Offset>((o) => (o.dx - x).abs() < 1e-6 && (o.dy - y).abs() < 1e-6);

bool sameCorner(Vector3 a, Vector3 b) => (a - b).length < 1e-6;

Matrix4 perspective() {
  final m = Matrix4.zero();
  setPerspectiveMatrix(m, math.pi / 3, 1.0, 0.1, 100.0);
  return m;
}

void main() {
  group('planeQuadCorners', () {
    test('horizontal quad at yaw 0 spans extentX on X and extentZ on Z', () {
      final corners = planeQuadCorners(PlaneQuad(
        center: Vector3.zero(),
        yaw: 0,
        extentX: 2,
        extentZ: 4,
        vertical: false,
        kind: PlaneQuadKind.floor,
      ));
      expect(corners, hasLength(4));
      for (final expected in [
        Vector3(1, 0, 2),
        Vector3(1, 0, -2),
        Vector3(-1, 0, -2),
        Vector3(-1, 0, 2),
      ]) {
        expect(corners.any((c) => sameCorner(c, expected)), isTrue,
            reason: 'missing corner $expected in $corners');
      }
    });

    test('yaw π/2 rotates the horizontal span onto Z', () {
      final corners = planeQuadCorners(PlaneQuad(
        center: Vector3.zero(),
        yaw: math.pi / 2,
        extentX: 2,
        extentZ: 4,
        vertical: false,
        kind: PlaneQuadKind.floor,
      ));
      for (final expected in [
        Vector3(2, 0, -1),
        Vector3(2, 0, 1),
        Vector3(-2, 0, 1),
        Vector3(-2, 0, -1),
      ]) {
        expect(corners.any((c) => sameCorner(c, expected)), isTrue,
            reason: 'missing corner $expected in $corners');
      }
    });

    test('vertical quad spans width horizontally and height along up', () {
      final corners = planeQuadCorners(PlaneQuad(
        center: Vector3(1, 1, -2),
        yaw: 0,
        extentX: 2,
        extentZ: 2.7,
        vertical: true,
        kind: PlaneQuadKind.wall,
      ));
      for (final expected in [
        Vector3(2, 2.35, -2),
        Vector3(2, -0.35, -2),
        Vector3(0, -0.35, -2),
        Vector3(0, 2.35, -2),
      ]) {
        expect(corners.any((c) => sameCorner(c, expected)), isTrue,
            reason: 'missing corner $expected in $corners');
      }
    });

    test('vertical yaw π/2 turns the width onto -Z', () {
      final corners = planeQuadCorners(PlaneQuad(
        center: Vector3.zero(),
        yaw: math.pi / 2,
        extentX: 2,
        extentZ: 1,
        vertical: true,
        kind: PlaneQuadKind.wall,
      ));
      for (final expected in [
        Vector3(0, 0.5, -1),
        Vector3(0, -0.5, -1),
        Vector3(0, -0.5, 1),
        Vector3(0, 0.5, 1),
      ]) {
        expect(corners.any((c) => sameCorner(c, expected)), isTrue,
            reason: 'missing corner $expected in $corners');
      }
    });
  });

  group('projectWorldPolygon', () {
    const viewport = Size(200, 100);

    test('identity view-projection maps NDC corners onto the viewport', () {
      final pts = projectWorldPolygon(
        viewProjection: Matrix4.identity(),
        points: [
          Vector3(1, 1, 0),
          Vector3(1, -1, 0),
          Vector3(-1, -1, 0),
          Vector3(-1, 1, 0),
        ],
        viewport: viewport,
      );
      expect(pts, isNotNull);
      expect(pts, [
        isOffset(200, 0),
        isOffset(200, 100),
        isOffset(0, 100),
        isOffset(0, 0),
      ]);
    });

    test('points fully behind the camera project to nothing', () {
      final pts = projectWorldPolygon(
        viewProjection: perspective(),
        points: [
          Vector3(1, 1, 5),
          Vector3(1, -1, 5),
          Vector3(-1, -1, 5),
          Vector3(-1, 1, 5),
        ],
        viewport: viewport,
      );
      expect(pts, isNull);
    });

    test('a polygon straddling the near plane is clipped, not dropped', () {
      final pts = projectWorldPolygon(
        viewProjection: perspective(),
        points: [
          Vector3(1, 1, -2),
          Vector3(1, -1, -2),
          Vector3(-1, -1, 2),
          Vector3(-1, 1, 2),
        ],
        viewport: viewport,
      );
      expect(pts, isNotNull);
      expect(pts!.length, greaterThanOrEqualTo(3));
      for (final p in pts) {
        expect(p.dx.isFinite && p.dy.isFinite, isTrue);
      }
    });

    test('fewer than three points is never a polygon', () {
      final pts = projectWorldPolygon(
        viewProjection: Matrix4.identity(),
        points: [Vector3(0, 0, 0), Vector3(1, 0, 0)],
        viewport: viewport,
      );
      expect(pts, isNull);
    });
  });

  group('planeQuadCorners true polygon', () {
    test('a supplied polygon wins over the center/extents rectangle', () {
      final polygon = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 0, 1),
        Vector3(0.5, 0, 1.5),
        Vector3(0, 0, 1),
      ];
      final corners = planeQuadCorners(PlaneQuad(
        center: Vector3(10, 0, 10),
        yaw: 0,
        extentX: 2,
        extentZ: 2,
        vertical: false,
        kind: PlaneQuadKind.floor,
        polygon: polygon,
      ));
      expect(corners, hasLength(5));
      for (final p in polygon) {
        expect(corners.any((c) => sameCorner(c, p)), isTrue);
      }
    });

    test('fewer than three polygon points falls back to the rectangle', () {
      final corners = planeQuadCorners(PlaneQuad(
        center: Vector3.zero(),
        yaw: 0,
        extentX: 2,
        extentZ: 2,
        vertical: false,
        kind: PlaneQuadKind.floor,
        polygon: [Vector3(0, 0, 0), Vector3(1, 0, 0)],
      ));
      expect(corners, hasLength(4));
    });

    test('a tilted floor polygon snaps level to the center height', () {
      // ARCore's fitted normal leans a few degrees — invisible up close,
      // the far edge climbs off the real floor at distance.
      final corners = planeQuadCorners(PlaneQuad(
        center: Vector3(0, -1.5, -3),
        yaw: 0,
        extentX: 4,
        extentZ: 4,
        vertical: false,
        kind: PlaneQuadKind.floor,
        polygon: [
          Vector3(-2, -1.4, -5),
          Vector3(2, -1.4, -5),
          Vector3(2, -1.6, -1),
          Vector3(-2, -1.6, -1),
        ],
      ));
      expect(corners, hasLength(4));
      for (final c in corners) {
        expect(c.y, closeTo(-1.5, 1e-9),
            reason: 'every vertex sits at the plane height');
      }
      expect(corners.any((v) => v.x == 2 && v.z == -5), isTrue,
          reason: 'the outline itself is preserved');
    });

    test('a leaning wall polygon snaps onto its vertical plane', () {
      // yaw 0 → normal (0, 0, 1); the lean lives entirely in z.
      final corners = planeQuadCorners(PlaneQuad(
        center: Vector3(0, 1, 2),
        yaw: 0,
        extentX: 3,
        extentZ: 2,
        vertical: true,
        kind: PlaneQuadKind.wall,
        polygon: [
          Vector3(-1.5, 0, 2.3),
          Vector3(1.5, 0, 2.3),
          Vector3(1.5, 2, 1.7),
          Vector3(-1.5, 2, 1.7),
        ],
      ));
      expect(corners, hasLength(4));
      for (final v in corners) {
        expect(v.z, closeTo(2.0, 1e-9), reason: 'on the wall plane');
      }
      expect(corners.any((v) => v.y == 0), isTrue,
          reason: 'height is untouched by the projection');
      expect(corners.any((v) => v.x == 1.5), isTrue,
          reason: 'width is untouched by the projection');
    });
  });

  group('overlayZoneOf', () {
    test('every vertical plane is wall zone', () {
      expect(
        overlayZoneOf(planeType: 2, centerY: 1.2, floorY: 0, cameraY: 1.5),
        OverlayZoneKind.wall,
      );
    });

    test('a floor-level horizontal plane is floor zone at any size', () {
      // The old class-based rule dropped sub-1.0 m fragments — the overlay
      // stayed blank while the coach's coverage bar moved.
      expect(
        overlayZoneOf(planeType: 1, centerY: -0.02, floorY: 0, cameraY: 1.5),
        OverlayZoneKind.floor,
      );
    });

    test('clearly above the known floor is a furniture mask', () {
      expect(
        overlayZoneOf(planeType: 1, centerY: 0.75, floorY: 0, cameraY: 1.5),
        OverlayZoneKind.mask,
      );
    });

    test('without floorY the below-camera band decides', () {
      expect(
        overlayZoneOf(planeType: 1, centerY: -0.5, floorY: null, cameraY: 1.5),
        OverlayZoneKind.floor,
        reason: '2.0 m below the phone is a plausible floor',
      );
      expect(
        overlayZoneOf(planeType: 1, centerY: 0.75, floorY: null, cameraY: 1.5),
        OverlayZoneKind.mask,
        reason: 'a table top sits too close to the phone',
      );
    });

    test('a surface at camera height without floorY masks, not floors', () {
      expect(
        overlayZoneOf(planeType: 1, centerY: 1.2, floorY: null, cameraY: 1.5),
        OverlayZoneKind.mask,
      );
    });

    test('no height reference at all drops the plane', () {
      expect(
        overlayZoneOf(planeType: 1, centerY: -0.5, floorY: null, cameraY: null),
        OverlayZoneKind.drop,
      );
    });

    test('downward-facing and unknown plane types drop', () {
      expect(
        overlayZoneOf(planeType: 0, centerY: 2.5, floorY: 0, cameraY: 1.5),
        OverlayZoneKind.drop,
      );
      expect(
        overlayZoneOf(planeType: 3, centerY: 0, floorY: 0, cameraY: 1.5),
        OverlayZoneKind.drop,
      );
    });
  });

  group('emaPolygon', () {
    test('the first sighting adopts the raw ring', () {
      final next = [Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)];
      final out = emaPolygon(null, next);
      expect(out, same(next));
    });

    test('later sightings blend toward the new vertices', () {
      final prev = [Vector3.zero(), Vector3.zero(), Vector3.zero()];
      final next = [Vector3(10, 0, 0), Vector3(0, 4, 0), Vector3(0, 0, 2)];
      final out = emaPolygon(prev, next, alpha: 0.35);
      expect(out[0].x, closeTo(3.5, 1e-9));
      expect(out[1].y, closeTo(1.4, 1e-9));
      expect(out[2].z, closeTo(0.7, 1e-9));
    });

    test('a re-fitted outline of a different length resets', () {
      final prev = [Vector3.zero(), Vector3.zero(), Vector3.zero()];
      final next = [
        Vector3(1, 0, 0),
        Vector3(2, 0, 0),
        Vector3(3, 0, 0),
        Vector3(4, 0, 0),
        Vector3(5, 0, 0),
      ];
      expect(emaPolygon(prev, next), same(next));
    });

    test('degenerate rings pass through', () {
      final next = [Vector3.zero(), Vector3.zero()];
      expect(emaPolygon([Vector3(1, 1, 1)], next), same(next));
    });
  });

  group('polygonFromFlat', () {
    test('converts xyz triplets into world points', () {
      final pts = polygonFromFlat([
        1.0, 2.0, 3.0, //
        4.0, 5.0, 6.0,
        7.0, 8.0, 9.0,
      ]);
      expect(pts, hasLength(3));
      expect(sameCorner(pts[0], Vector3(1, 2, 3)), isTrue);
      expect(sameCorner(pts[1], Vector3(4, 5, 6)), isTrue);
      expect(sameCorner(pts[2], Vector3(7, 8, 9)), isTrue);
    });

    test('short or ragged input collapses to empty', () {
      expect(polygonFromFlat(const []), isEmpty);
      expect(polygonFromFlat([1.0, 2.0, 3.0]), isEmpty,
          reason: 'a single point is not a polygon');
      expect(polygonFromFlat([1.0, 2.0, 3.0, 4.0]), isEmpty,
          reason: 'ragged triplet list is rejected');
    });
  });

  group('segmentBlockedByQuad', () {
    PlaneQuad table() => PlaneQuad(
          center: Vector3(0, 0.75, 2),
          yaw: 0,
          extentX: 1,
          extentZ: 1,
          vertical: false,
          kind: PlaneQuadKind.floor,
        );

    test('floor behind a table top is blocked', () {
      // Camera 1.5 m up looks at a floor patch past the 0.75 m table — the
      // sight line pierces the table top before reaching the floor.
      expect(
        segmentBlockedByQuad(
          origin: Vector3(0, 1.5, 0),
          target: Vector3(0, 0, 4),
          quad: table(),
        ),
        isTrue,
      );
    });

    test('floor beside the table is not blocked', () {
      expect(
        segmentBlockedByQuad(
          origin: Vector3(0, 1.5, 0),
          target: Vector3(3, 0, 1),
          quad: table(),
        ),
        isFalse,
      );
    });

    test('floor in front of the table is not blocked', () {
      expect(
        segmentBlockedByQuad(
          origin: Vector3(0, 1.5, 0),
          target: Vector3(0, 0, 1),
          quad: table(),
        ),
        isFalse,
      );
    });

    test('a tap landing on the furniture itself is not "behind" it', () {
      // Pierce point ≈ target — the margin keeps that the furniture-hit
      // gates' business (chooseFloorHit refuses elevated surfaces there).
      expect(
        segmentBlockedByQuad(
          origin: Vector3(0, 1.5, 0),
          target: Vector3(0, 0.75, 2),
          quad: table(),
        ),
        isFalse,
      );
    });

    test('a ray parallel to the plane never blocks', () {
      expect(
        segmentBlockedByQuad(
          origin: Vector3(0, 1.5, 0),
          target: Vector3(5, 1.5, 0),
          quad: table(),
        ),
        isFalse,
      );
    });

    test('a wall quad blocks a tap aimed through it', () {
      final wall = PlaneQuad(
        center: Vector3(0, 1, 2),
        yaw: 0,
        extentX: 3,
        extentZ: 2,
        vertical: true,
        kind: PlaneQuadKind.wall,
      );
      expect(
        segmentBlockedByQuad(
          origin: Vector3(0, 1.5, 0),
          target: Vector3(0, 1, 4),
          quad: wall,
        ),
        isTrue,
      );
      expect(
        segmentBlockedByQuad(
          origin: Vector3(0, 1.5, 0),
          target: Vector3(4, 1, 4),
          quad: wall,
        ),
        isFalse,
      );
    });

    test('a true polygon masks only where its outline actually covers', () {
      // L-shaped outline: the sight line passes through the missing corner.
      // Center shares the pose with the polygon (y = table height), as the
      // telemetry always does — idealization snaps to center height.
      final lShape = PlaneQuad(
        center: Vector3(0, 0.75, 0),
        yaw: 0,
        extentX: 2,
        extentZ: 2,
        vertical: false,
        kind: PlaneQuadKind.floor,
        polygon: [
          Vector3(-1, 0.75, -1),
          Vector3(1, 0.75, -1),
          Vector3(1, 0.75, 0),
          Vector3(0, 0.75, 0),
          Vector3(0, 0.75, 1),
          Vector3(-1, 0.75, 1),
        ],
      );
      // Through the solid arm (pierce lands at (-0.5, 0.75, -0.5))…
      expect(
        segmentBlockedByQuad(
          origin: Vector3(-0.5, 1.5, -3),
          target: Vector3(-0.5, 0, 2),
          quad: lShape,
        ),
        isTrue,
      );
      // …through the cut-out corner (pierce lands at (0.5, 0.75, 0.5)):
      // not blocked.
      expect(
        segmentBlockedByQuad(
          origin: Vector3(0.5, 1.5, -3),
          target: Vector3(0.5, 0, 4),
          quad: lShape,
        ),
        isFalse,
      );
    });
  });

  group('buildOverlayZones', () {
    final floorPoly = [
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, 100),
      Offset(0, 100),
    ];
    final wallPoly = [
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, 40),
      Offset(0, 40),
    ];

    test('the floor never paints over a wall region', () {
      final z = buildOverlayZones(
        floors: [floorPoly],
        walls: [wallPoly],
        masks: const [],
      );
      expect(z.floor, isNotNull);
      expect(z.wall, isNotNull);
      expect(z.floor!.contains(const Offset(50, 20)), isFalse,
          reason: 'the wall band belongs to the wall zone');
      expect(z.floor!.contains(const Offset(50, 70)), isTrue,
          reason: 'open floor stays floor');
      expect(z.wall!.contains(const Offset(50, 20)), isTrue);
    });

    test('furniture holes punch out of both zones', () {
      final hole = [
        Offset(40, 60),
        Offset(60, 60),
        Offset(60, 80),
        Offset(40, 80),
      ];
      final z = buildOverlayZones(
        floors: [floorPoly],
        walls: [wallPoly],
        masks: [hole],
      );
      expect(z.floor!.contains(const Offset(50, 70)), isFalse,
          reason: 'floor under the table is masked');
      expect(z.floor!.contains(const Offset(20, 70)), isTrue);
      // Hole in the wall band too.
      final wallHole = [
        Offset(40, 10),
        Offset(60, 10),
        Offset(60, 30),
        Offset(40, 30),
      ];
      final z2 = buildOverlayZones(
        floors: [floorPoly],
        walls: [wallPoly],
        masks: [wallHole],
      );
      expect(z2.wall!.contains(const Offset(50, 20)), isFalse);
      expect(z2.wall!.contains(const Offset(20, 20)), isTrue);
    });

    test('fragments union into one zone path', () {
      final a = [
        Offset(0, 0),
        Offset(60, 0),
        Offset(60, 60),
        Offset(0, 60),
      ];
      final b = [
        Offset(40, 40),
        Offset(100, 40),
        Offset(100, 100),
        Offset(40, 100),
      ];
      final z = buildOverlayZones(floors: [a, b], walls: const [], masks: const []);
      expect(z.floor, isNotNull);
      expect(z.floor!.contains(const Offset(10, 10)), isTrue);
      expect(z.floor!.contains(const Offset(90, 90)), isTrue,
          reason: 'both fragments live in the single merged path');
    });

    test('empty inputs give null zones', () {
      final z = buildOverlayZones(
        floors: const [],
        walls: const [],
        masks: const [],
      );
      expect(z.floor, isNull);
      expect(z.wall, isNull);
    });

    test('a zone with no counterpart still draws', () {
      final z = buildOverlayZones(
        floors: [floorPoly],
        walls: const [],
        masks: const [],
      );
      expect(z.floor, isNotNull);
      expect(z.wall, isNull);
    });
  });

  group('projectPlaneQuad', () {
    test('a floor quad under a forward camera lands below screen center', () {
      final pts = projectPlaneQuad(
        viewProjection: perspective(),
        quad: PlaneQuad(
          center: Vector3(0, -1.5, -3),
          yaw: 0,
          extentX: 4,
          extentZ: 4,
          vertical: false,
          kind: PlaneQuadKind.floor,
        ),
        viewport: const Size(200, 200),
      );
      expect(pts, isNotNull);
      for (final p in pts!) {
        expect(p.dy, greaterThan(100), reason: 'floor sits under the camera');
      }
    });

    test('a wall quad ahead of the camera projects in front', () {
      final pts = projectPlaneQuad(
        viewProjection: perspective(),
        quad: PlaneQuad(
          center: Vector3(0, 0, -4),
          yaw: 0,
          extentX: 2,
          extentZ: 2.7,
          vertical: true,
          kind: PlaneQuadKind.wall,
        ),
        viewport: const Size(200, 200),
      );
      expect(pts, isNotNull);
      expect(pts, hasLength(4));
      for (final p in pts!) {
        expect(p.dx.isFinite && p.dy.isFinite, isTrue);
      }
    });

    test('a quad behind the camera is not drawn', () {
      final pts = projectPlaneQuad(
        viewProjection: perspective(),
        quad: PlaneQuad(
          center: Vector3(0, 0, 3),
          yaw: 0,
          extentX: 2,
          extentZ: 2,
          vertical: true,
          kind: PlaneQuadKind.wall,
        ),
        viewport: const Size(200, 200),
      );
      expect(pts, isNull);
    });
  });
}
