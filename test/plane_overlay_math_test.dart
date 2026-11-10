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
      // The drawn ring hugs the raw outline (shrunk only by the edge
      // inset) — it never expands to the center/extents rectangle at (10,10).
      for (var i = 0; i < polygon.length; i++) {
        expect(corners[i].distanceTo(polygon[i]), lessThan(0.06),
            reason: 'vertex $i stays on the raw outline');
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
      // Outline preserved apart from the edge inset: each corner sits
      // 0.04 m closer to the XZ centroid than its raw vertex.
      var cx = 0.0;
      var cz = 0.0;
      for (final v in corners) {
        cx += v.x;
        cz += v.z;
      }
      cx /= corners.length;
      cz /= corners.length;
      final raw = [
        Vector3(-2, -1.4, -5),
        Vector3(2, -1.4, -5),
        Vector3(2, -1.6, -1),
        Vector3(-2, -1.6, -1),
      ];
      for (var i = 0; i < corners.length; i++) {
        final rawD =
            math.sqrt(math.pow(raw[i].x - cx, 2) + math.pow(raw[i].z - cz, 2));
        final outD = math.sqrt(
            math.pow(corners[i].x - cx, 2) + math.pow(corners[i].z - cz, 2));
        expect(outD, closeTo(rawD - 0.04, 1e-9),
            reason: 'corner $i is inset toward the centroid, never expanded');
      }
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
    test('a wall-sized vertical plane is wall zone', () {
      expect(
        overlayZoneOf(
          planeType: 2,
          centerY: 1.2,
          floorY: 0,
          cameraY: 1.5,
          extentX: 2.0,
          extentZ: 1.5,
        ),
        OverlayZoneKind.wall,
      );
    });

    test('vertical planes below the shared area gate drop', () {
      // 0.999 m² is just under ArPlacementPolicy.minWallAreaM2 (1.0).
      expect(
        overlayZoneOf(
            planeType: 2, centerY: 1.0, extentX: 0.999, extentZ: 1.0),
        OverlayZoneKind.drop,
      );
      expect(
        overlayZoneOf(
            planeType: 2, centerY: 1.0, extentX: 1.001, extentZ: 1.0),
        OverlayZoneKind.wall,
        reason: 'the gate is >=, so exactly 1.0 m² also passes',
      );
      expect(
        overlayZoneOf(planeType: 2, centerY: 1.0),
        OverlayZoneKind.drop,
        reason: 'no extents → fails closed, never paints wrongly',
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

    test('an untrusted floorY never paints a table green', () {
      // floorY locked on the table at 0.75 with no corroborating lowest
      // plane — the classic floating detection plane must mask.
      expect(
        overlayZoneOf(
            planeType: 1, centerY: 0.75, floorY: 0.75, cameraY: 1.4),
        OverlayZoneKind.mask,
      );
    });

    test('an untrusted floorY with a real lowest plane recovers', () {
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: -0.02,
            floorY: 0.75,
            cameraY: 1.5,
            lowestPlaneY: -0.02),
        OverlayZoneKind.floor,
      );
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: 0.75,
            floorY: 0.75,
            cameraY: 1.5,
            lowestPlaneY: -0.02),
        OverlayZoneKind.mask,
        reason: 'the table stays masked once the ref is the real floor',
      );
    });

    test('an untrusted lowest plane outside the strict band masks', () {
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: 0.75,
            floorY: 0.75,
            cameraY: 1.4,
            lowestPlaneY: 0.75),
        OverlayZoneKind.mask,
        reason: '0.65 m below the phone is too close to be a floor',
      );
    });

    test('an untrusted floor with no camera height drops', () {
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: 0,
            floorY: 0.75,
            cameraY: null,
            lowestPlaneY: 0),
        OverlayZoneKind.drop,
      );
    });

    test('a floor-level untrusted plane paints even with no camera height',
        () {
      // Pose gap longer than the zone window: the memory already knows this
      // floor, so a plane sitting on it must not blank the overlay.
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: 0.0,
            floorY: 0,
            cameraY: null,
            lowestPlaneY: 0),
        OverlayZoneKind.floor,
      );
    });

    test('a trusted floorY keeps painting while the camera crouches', () {
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: 0,
            floorY: 0,
            cameraY: 0.5,
            floorYTrusted: true),
        OverlayZoneKind.floor,
        reason: 'trust was earned at proof time — no live band check',
      );
    });

    test('a trusted floorY yields to a plane 0.45 m below', () {
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: -0.45,
            floorY: 0,
            cameraY: 1.5,
            lowestPlaneY: -0.45,
            floorYTrusted: true),
        OverlayZoneKind.floor,
        reason: 'the reappeared real floor pulls the ref down',
      );
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: 0,
            floorY: 0,
            cameraY: 1.5,
            lowestPlaneY: -0.45,
            floorYTrusted: true),
        OverlayZoneKind.mask,
        reason: 'the stale anchor height masks once the ref moved down',
      );
    });

    test('a trusted floorY ignores noise far below', () {
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: 0,
            floorY: 0,
            cameraY: 1.5,
            lowestPlaneY: -2.0,
            floorYTrusted: true),
        OverlayZoneKind.floor,
        reason: 'a 2 m gap is noise — the anchor wins',
      );
    });

    test('cloud corroboration refuses a stray low plane for zones', () {
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: 0,
            floorY: 0,
            cameraY: 1.5,
            lowestPlaneY: -0.45,
            floorYTrusted: true,
            corroborateFloorY: true),
        OverlayZoneKind.floor,
        reason: 'the confirmed height paints even when a reflection sits '
            '0.45 m below',
      );
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: -0.45,
            floorY: 0,
            cameraY: 1.5,
            lowestPlaneY: -0.45,
            floorYTrusted: true,
            corroborateFloorY: true),
        OverlayZoneKind.drop,
        reason: 'without the pull the stray plane is simply below the band',
      );
    });

    test('a low object top masks instead of painting floor', () {
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: 0.25,
            floorY: 0,
            cameraY: 1.5,
            floorYTrusted: true),
        OverlayZoneKind.mask,
        reason: '0.25 m above the proven floor is an object top, not drift',
      );
    });

    test('planes clearly below a trusted floor never paint', () {
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: -0.25,
            floorY: 0,
            cameraY: 1.5,
            floorYTrusted: true),
        OverlayZoneKind.drop,
        reason: 'flattening a lower level up would float phantom floor',
      );
    });

    test('elevated untrusted planes mask even with no camera height', () {
      expect(
        overlayZoneOf(
            planeType: 1,
            centerY: 0.3,
            floorY: null,
            cameraY: null,
            lowestPlaneY: 0),
        OverlayZoneKind.mask,
        reason: 'object masks are never dropped — that painted furniture green',
      );
    });
  });

  group('trustedOverlayRefY', () {
    test('the anchor stands unless a slightly lower plane contradicts it', () {
      expect(
          trustedOverlayRefY(floorY: -1.09, lowestPlaneY: -1.02), -1.09);
      expect(trustedOverlayRefY(floorY: -1.09, lowestPlaneY: null), -1.09);
    });

    test('a plane up to 0.5 m below pulls the reference down', () {
      expect(trustedOverlayRefY(floorY: 0, lowestPlaneY: -0.45), -0.45);
    });

    test('noise far below never moves the reference', () {
      expect(trustedOverlayRefY(floorY: 0, lowestPlaneY: -2.0), 0);
    });

    test('fresh cloud corroboration refuses the pull-down', () {
      expect(
        trustedOverlayRefY(
          floorY: 0,
          lowestPlaneY: -0.45,
          corroborateFloorY: true,
        ),
        0,
        reason: 'a stray low plane must not move a cloud-confirmed height',
      );
    });
  });

  group('withWallBaseAt', () {
    PlaneQuad rectWall({
      double y = 1.15,
      double height = 2,
      bool vertical = true,
    }) =>
        PlaneQuad(
          center: Vector3(1, y, 2),
          yaw: 0,
          extentX: 2,
          extentZ: height,
          vertical: vertical,
          kind: vertical ? PlaneQuadKind.wall : PlaneQuadKind.floor,
        );

    test('a rect wall short of the floor stretches down to it', () {
      final wall = rectWall(); // bottom at 0.15 m
      final out = withWallBaseAt(wall, refY: 0);
      expect(out, isNot(same(wall)));
      expect(out.center.x, closeTo(1, 1e-12));
      expect(out.center.z, closeTo(2, 1e-12));
      expect(out.yaw, closeTo(0, 1e-12));
      expect(out.extentX, 2);
      expect(out.extentZ, closeTo(2.15, 1e-9));
      expect(out.center.y, closeTo(1.075, 1e-9));
      expect(out.center.y - out.extentZ / 2, closeTo(0, 1e-9),
          reason: 'the base lands ON the floor paint plane, not below it');
      expect(out.vertical, isTrue);
      expect(out.kind, PlaneQuadKind.wall);
      expect(out.polygon, isEmpty);
    });

    test('the drop happens at exactly maxDropM and stops past it', () {
      final wall = rectWall(y: 1.5); // bottom = 0.5 exactly
      final inLimit = withWallBaseAt(wall, refY: 0, maxDropM: 0.5);
      expect(inLimit.center.y - inLimit.extentZ / 2, closeTo(0, 1e-9));
      expect(withWallBaseAt(wall, refY: 0, maxDropM: 0.49), same(wall),
          reason: 'a fragment floating past the limit is genuinely high');
    });

    test('a wall already reaching the floor is untouched', () {
      final atFloor = rectWall(y: 1.0); // bottom = 0
      expect(withWallBaseAt(atFloor, refY: 0), same(atFloor));
    });

    test('a wall dipping below the floor is raised onto it, top kept', () {
      final below = rectWall(y: 0.9); // bottom = −0.1, top = 1.9
      final out = withWallBaseAt(below, refY: 0);
      expect(out, isNot(same(below)),
          reason: 'the old pass-through painted the dip as blue-on-green');
      expect(out.extentZ, closeTo(1.9, 1e-9), reason: 'top stays at 1.9');
      expect(out.center.y, closeTo(0.95, 1e-9));
      expect(out.center.y - out.extentZ / 2, closeTo(0, 1e-9));
      expect(out.center.x, closeTo(1, 1e-12));
      expect(out.yaw, closeTo(0, 1e-12));
    });

    test('a far-below dip raises onto the floor with no drop band', () {
      final deep = rectWall(y: 0.4); // bottom = −0.6, top = 1.4
      final out = withWallBaseAt(deep, refY: 0);
      expect(out, isNot(same(deep)));
      expect(out.center.y - out.extentZ / 2, closeTo(0, 1e-9));
      expect(out.extentZ, closeTo(1.4, 1e-9));
      expect(out.center.y, closeTo(0.7, 1e-9));
    });

    test('a wholly-below rect lifts rigidly, height preserved', () {
      final under = rectWall(y: -1.5); // bottom = −2.5, top = −0.5 ≤ 0
      final out = withWallBaseAt(under, refY: 0);
      expect(out, isNot(same(under)));
      expect(out.extentZ, closeTo(2, 1e-12),
          reason: 'a rigid lift never distorts the height');
      expect(out.center.y, closeTo(1, 1e-12));
      expect(out.center.y - out.extentZ / 2, closeTo(0, 1e-12));
    });

    test('a fragment floating above maxDropM is untouched', () {
      final high = rectWall(y: 1.6); // bottom = 0.6 > 0.45
      expect(withWallBaseAt(high, refY: 0), same(high));
    });

    test('a horizontal quad and a non-finite refY are untouched', () {
      final floorQuad = rectWall(vertical: false);
      expect(withWallBaseAt(floorQuad, refY: 0), same(floorQuad));
      final wall = rectWall();
      expect(withWallBaseAt(wall, refY: double.nan), same(wall));
      expect(withWallBaseAt(wall, refY: double.infinity), same(wall));
    });

    test('a polygon wall drops its wobbly bottom row', () {
      final wall = PlaneQuad(
        center: Vector3(0, 1.1, 2),
        yaw: 0,
        extentX: 3,
        extentZ: 2,
        vertical: true,
        kind: PlaneQuadKind.wall,
        polygon: [
          Vector3(-1.5, 0.15, 2.05),
          Vector3(0, 0.30, 2.0), // 15 cm above the low point — stays
          Vector3(1.5, 0.18, 1.95),
          Vector3(1.5, 2.0, 2.0),
          Vector3(-1.5, 2.0, 2.0),
        ],
      );
      final out = withWallBaseAt(wall, refY: 0);
      expect(out, isNot(same(wall)));
      expect(out.polygon, hasLength(5));
      expect(out.polygon[0].y, closeTo(0, 1e-9));
      expect(out.polygon[1].y, closeTo(0.30, 1e-9),
          reason: 'only the bottom row (≤ low + 0.10) moves');
      expect(out.polygon[2].y, closeTo(0, 1e-9));
      expect(out.polygon[3].y, closeTo(2.0, 1e-9));
      expect(out.polygon[4].y, closeTo(2.0, 1e-9));
      expect(out.polygon[0].x, closeTo(-1.5, 1e-9));
      expect(out.polygon[2].z, closeTo(1.95, 1e-9));
      // center.y shifts by the same delta: 0 − 0.15 = −0.15
      expect(out.center.y, closeTo(1.1 - 0.15, 1e-9));
      expect(out.center.x, closeTo(0, 1e-12));
      expect(out.center.z, closeTo(2, 1e-12));
      expect(out.extentX, 3);
      expect(out.extentZ, 2);
      expect(out.vertical, isTrue);
      expect(out.kind, PlaneQuadKind.wall);
    });

    test('a polygon wall dipping below the floor is raised onto it', () {
      final wall = PlaneQuad(
        center: Vector3.zero(),
        yaw: 0,
        extentX: 2,
        extentZ: 2,
        vertical: true,
        kind: PlaneQuadKind.wall,
        polygon: [
          Vector3(-1, -0.05, 0),
          Vector3(1, -0.05, 0),
          Vector3(1, 2, 0),
          Vector3(-1, 2, 0),
        ],
      );
      final out = withWallBaseAt(wall, refY: 0);
      expect(out, isNot(same(wall)),
          reason: 'the old pass-through painted the dip as blue-on-green');
      expect(out.polygon, hasLength(4));
      expect(out.polygon[0].y, closeTo(0, 1e-9),
          reason: 'sub-floor vertices land ON the floor paint plane');
      expect(out.polygon[1].y, closeTo(0, 1e-9));
      expect(out.polygon[2].y, closeTo(2, 1e-9));
      expect(out.polygon[3].y, closeTo(2, 1e-9));
      expect(out.center.y, closeTo(0.05, 1e-9),
          reason: 'center.y += refY − minY');
      expect(out.extentZ, 2, reason: 'height unchanged');
    });

    test('a wholly-below polygon translates up, ring intact', () {
      final wall = PlaneQuad(
        center: Vector3(0, -1, 2),
        yaw: 0,
        extentX: 2,
        extentZ: 1,
        vertical: true,
        kind: PlaneQuadKind.wall,
        polygon: [
          Vector3(-1, -1.5, 2),
          Vector3(1, -1.5, 2),
          Vector3(1, -0.5, 2),
          Vector3(-1, -0.5, 2),
        ],
      );
      final out = withWallBaseAt(wall, refY: 0);
      expect(out, isNot(same(wall)));
      final ys = [for (final v in out.polygon) v.y];
      expect(ys, contains(closeTo(0, 1e-9)),
          reason: 'minY lands on the floor');
      expect(ys, contains(closeTo(1.0, 1e-9)),
          reason: 'the ring translates rigidly — no collapse to a line');
      expect(out.extentZ, closeTo(1, 1e-12));
      expect(out.center.y, closeTo(0.5, 1e-9), reason: '−1 + 1.5 delta');
      expect(out.polygon[0].x, closeTo(-1, 1e-9));
    });

    test('a polygon wall floating high is untouched', () {
      final wall = PlaneQuad(
        center: Vector3(0, 1.6, 2),
        yaw: 0,
        extentX: 2,
        extentZ: 2,
        vertical: true,
        kind: PlaneQuadKind.wall,
        polygon: [
          Vector3(-1, 0.6, 2),
          Vector3(1, 0.6, 2),
          Vector3(1, 2.6, 2),
          Vector3(-1, 2.6, 2),
        ],
      );
      expect(withWallBaseAt(wall, refY: 0), same(wall));
    });
  });

  group('mergeWallQuads', () {
    PlaneQuad wall({
      required double x,
      required double z,
      double yaw = 0,
      double width = 2,
      double height = 2,
      double y = 1,
    }) =>
        PlaneQuad(
          center: Vector3(x, y, z),
          yaw: yaw,
          extentX: width,
          extentZ: height,
          vertical: true,
          kind: PlaneQuadKind.wall,
        );

    test('abutting same-yaw fragments merge into one rectangle', () {
      final a = wall(x: 0, z: 2); // x ∈ [−1, 1]
      final b = wall(x: 2, z: 2); // x ∈ [1, 3]
      final out = mergeWallQuads([a, b]);
      expect(out, hasLength(1));
      final m = out.single;
      expect(m.polygon, isEmpty,
          reason: 'merged walls drop per-fragment outlines');
      expect(m.vertical, isTrue);
      expect(m.kind, PlaneQuadKind.wall);
      expect(m.yaw, closeTo(0, 1e-12));
      expect(m.extentX, closeTo(4, 1e-9));
      expect(m.extentZ, closeTo(2, 1e-9));
      expect(m.center.x, closeTo(1, 1e-9));
      expect(m.center.y, closeTo(1, 1e-9));
      expect(m.center.z, closeTo(2, 1e-9));
      final corners = planeQuadCorners(m);
      expect(
        corners.every((c) => c.x >= -1 - 1e-9 && c.x <= 3 + 1e-9),
        isTrue,
        reason: 'the merged rect spans both fragments',
      );
      expect(corners.every((c) => c.y >= 0 - 1e-9 && c.y <= 2 + 1e-9), isTrue);
    });

    test('perpendicular walls stay separate', () {
      final a = wall(x: 0, z: 2, yaw: 0);
      final b = wall(x: 2, z: 0, yaw: math.pi / 2);
      final out = mergeWallQuads([a, b]);
      expect(out, hasLength(2));
      expect(out.any((q) => identical(q, a)), isTrue);
      expect(out.any((q) => identical(q, b)), isTrue);
    });

    test('same-wall fragments 2 m apart stay separate', () {
      final a = wall(x: 0, z: 2); // x ∈ [−1, 1]
      final far = wall(x: 4, z: 2); // x ∈ [3, 5] — a 2 m gap
      final out = mergeWallQuads([a, far]);
      expect(out, hasLength(2));
      expect(out.any((q) => identical(q, a)), isTrue);
      expect(out.any((q) => identical(q, far)), isTrue);
    });

    test('input order does not change the result', () {
      final quads = [
        wall(x: 0, z: 2),
        wall(x: 2, z: 2),
        wall(x: 4, z: 2),
        wall(x: 1, z: 0, yaw: math.pi / 2),
      ];
      final a = mergeWallQuads(quads);
      final b = mergeWallQuads([quads[2], quads[0], quads[3], quads[1]]);
      String key(PlaneQuad q) =>
          '${q.yaw}|${q.center.x}|${q.center.y}|${q.center.z}|'
          '${q.extentX}|${q.extentZ}|${q.polygon.length}';
      expect([for (final q in a) key(q)], [for (final q in b) key(q)]);
      expect(a, hasLength(2));
      // The three abutting fragments became one 6 m rectangle.
      expect(a.first.extentX, closeTo(6, 1e-9));
      expect(a.first.center.x, closeTo(2, 1e-9));
      expect(a.first.yaw, closeTo(0, 1e-12));
    });

    test('an extended base survives the merge', () {
      final a = withWallBaseAt(wall(x: 0, z: 2, y: 1.15), refY: 0);
      final b = wall(x: 2, z: 2);
      final out = mergeWallQuads([a, b]);
      expect(out, hasLength(1));
      final m = out.single;
      expect(m.center.y - m.extentZ / 2, closeTo(0, 1e-9),
          reason: 'the stretched base is part of the merged y-range');
      expect(m.extentZ, closeTo(2.15, 1e-9));
      expect(m.center.y, closeTo(1.075, 1e-9));
    });

    test('a polygon-bearing wall owns the merged yaw', () {
      final poly = PlaneQuad(
        center: Vector3(1, 1, 2),
        yaw: 0,
        extentX: 2,
        extentZ: 2,
        vertical: true,
        kind: PlaneQuadKind.wall,
        polygon: [
          Vector3(0, 0, 2),
          Vector3(2, 0, 2),
          Vector3(2, 2, 2),
          Vector3(0, 2, 2),
        ],
      );
      // Wider rect-only synthetic whose near endpoint sits exactly on the
      // polygon's right edge — widest-owns would rotate the group to 0.24.
      final synth = wall(
        x: 2 + 1.5 * math.cos(0.24),
        z: 2 - 1.5 * math.sin(0.24),
        yaw: 0.24,
        width: 3,
      );
      final out = mergeWallQuads([poly, synth]);
      expect(out, hasLength(1));
      expect(out.single.yaw, closeTo(0, 1e-9),
          reason: 'telemetry polygon owns the frame, not the wider fit');
    });

    test('a yaw-drift chain caps at the pairwise spread bound', () {
      // Endpoints attach exactly (footprint gap 0); widths let the
      // widest-led group yaw walk to 0.26 so the old pairwise-vs-group
      // gate chains all four (span 0.39 rad) while the member-pairwise
      // cap stops at three.
      final a = wall(x: 1, z: 2, yaw: 0, width: 1.5);
      final b = wall(x: 2.99, z: 1.838, yaw: 0.13, width: 2.5);
      final c = wall(x: 5.921, z: 1.227, yaw: 0.26, width: 3.5);
      final d = wall(x: 8.537, z: 0.398, yaw: 0.39, width: 2.0);
      final out = mergeWallQuads([a, b, c, d]);
      expect(out, hasLength(2),
          reason: '0.39 − 0 = 0.39 rad breaks the pairwise 0.26 cap');
      final chain = out.firstWhere((q) => q.yaw > 0.1);
      expect(chain.yaw, closeTo(0.26, 1e-9),
          reason: 'all-synthetic group takes the median yaw');
      final lone = out.firstWhere((q) => q.yaw < 0.1);
      expect(identical(lone, a), isTrue);
    });

    test('a lone polygon wall passes through unchanged', () {
      final w = PlaneQuad(
        center: Vector3(0, 1, 2),
        yaw: 0,
        extentX: 2,
        extentZ: 2,
        vertical: true,
        kind: PlaneQuadKind.wall,
        polygon: [
          Vector3(-1, 0, 2),
          Vector3(1, 0, 2),
          Vector3(1, 2, 2),
          Vector3(-1, 2, 2),
        ],
      );
      final out = mergeWallQuads([w]);
      expect(out, hasLength(1));
      expect(out.single, same(w));
      expect(out.single.polygon, hasLength(4));
      expect(mergeWallQuads(const []), isEmpty);
    });
  });

  group('joinWallCorners', () {
    PlaneQuad wall({
      required double x,
      required double z,
      double yaw = 0,
      double width = 2,
      double height = 2,
      double y = 1,
      List<Vector3> polygon = const [],
    }) =>
        PlaneQuad(
          center: Vector3(x, y, z),
          yaw: yaw,
          extentX: width,
          extentZ: height,
          vertical: true,
          kind: PlaneQuadKind.wall,
          polygon: polygon,
        );

    // Both runs 0.2 m short of their shared corner point (2, 2).
    PlaneQuad runA({double y = 1}) => wall(x: 0, z: 2, width: 3.6, y: y);
    PlaneQuad runB({double y = 1}) =>
        wall(x: 2, z: 0, yaw: math.pi / 2, width: 3.6, y: y);

    test('a right-angle seam extends both runs to the intersection', () {
      final out = joinWallCorners([runA(), runB()]);
      expect(out, hasLength(2));
      final a = out.firstWhere((q) => (q.yaw).abs() < 1e-9);
      final b = out.firstWhere((q) => (q.yaw - math.pi / 2).abs() < 1e-9);
      expect(a.extentX, closeTo(3.8, 1e-9));
      expect(a.center.x, closeTo(0.1, 1e-9),
          reason: 'the rect grows one end, so the center slides half');
      expect(b.extentX, closeTo(3.8, 1e-9));
      expect(b.center.z, closeTo(0.1, 1e-9));
      // Both ends now land on the line intersection (2, 2). B runs along
      // −z (yaw π/2), so its near end sits at center.z + half.
      final endA = Vector3(a.center.x + a.extentX / 2, a.center.y, 2);
      final endB = Vector3(2, b.center.y, b.center.z + b.extentX / 2);
      expect((endA - Vector3(2, 1, 2)).length, lessThan(1e-9));
      expect((endB - Vector3(2, 1, 2)).length, lessThan(1e-9));
      expect(a.extentZ, 2, reason: 'vertical stretch belongs to withWallBaseAt');
      expect(a.center.y, 1);
    });

    test('distant perpendicular walls whose lines cross do not stretch', () {
      // Gap to the crossing point is 1 m on each side — over maxGapM.
      final a = wall(x: 0, z: 2, width: 2);
      final b = wall(x: 2, z: 0, yaw: math.pi / 2, width: 2);
      final out = joinWallCorners([a, b]);
      expect(identical(out[0], a), isTrue);
      expect(identical(out[1], b), isTrue);
    });

    test('a 0.6 m seam joins — ARCore runs stop that far short of corners',
        () {
      // Ends at x/z = ±1.4 → 0.6 m short of the (2, 2) intersection.
      final a = wall(x: 0, z: 2, width: 2.8);
      final b = wall(x: 2, z: 0, yaw: math.pi / 2, width: 2.8);
      final out = joinWallCorners([a, b]);
      expect(out[0].extentX, closeTo(3.4, 1e-9));
      expect(out[0].center.x, closeTo(0.3, 1e-9));
      expect(out[1].extentX, closeTo(3.4, 1e-9));
      expect(out[1].center.z, closeTo(0.3, 1e-9));
    });

    test('the gap bound stays caller-tunable', () {
      final a = wall(x: 0, z: 2, width: 2.8);
      final b = wall(x: 2, z: 0, yaw: math.pi / 2, width: 2.8);
      final out = joinWallCorners([a, b], maxGapM: 0.4);
      expect(identical(out[0], a), isTrue,
          reason: '0.6 m gap over a 0.4 m bound must not stretch');
      expect(identical(out[1], b), isTrue);
    });

    test('same-yaw and oblique pairs pass through untouched', () {
      final a = wall(x: 0, z: 2);
      final b = wall(x: 4, z: 2);
      final c = wall(x: 6, z: 0, yaw: 1.0); // 57° — not a corner
      final out = joinWallCorners([a, b, c]);
      expect(identical(out[0], a), isTrue);
      expect(identical(out[1], b), isTrue);
      expect(identical(out[2], c), isTrue);
    });

    test('height ranges that do not overlap refuse the join', () {
      final a = wall(x: 0, z: 2, width: 3.6, height: 2, y: 2); // y ∈ [1, 3]
      final b = wall(
          x: 2, z: 0, yaw: math.pi / 2, width: 3.6, height: 0.5, y: 0.25);
      final out = joinWallCorners([a, b]);
      expect(identical(out[0], a), isTrue);
      expect(identical(out[1], b), isTrue);
    });

    test('a T junction extends only the stem', () {
      final cross = wall(x: 0, z: 2, width: 6); // P = (0, 2) inside its span
      final stem = wall(x: 0, z: 0, yaw: math.pi / 2, width: 3.6);
      final out = joinWallCorners([cross, stem]);
      expect(identical(out[0], cross), isTrue,
          reason: 'the intersection sits mid-span — the cross wall is done');
      expect(out[1].extentX, closeTo(3.8, 1e-9));
      expect(out[1].center.z + out[1].extentX / 2, closeTo(2, 1e-9),
          reason: 'stem reaches the cross wall line');
    });

    test('polygon end vertices ride along, interior vertices stay', () {
      final poly = [
        Vector3(-1.8, 0, 2),
        Vector3(1.8, 0, 2),
        Vector3(1.8, 2, 2),
        Vector3(-1.8, 2, 2),
      ];
      final a = wall(x: 0, z: 2, width: 3.6, polygon: poly);
      final out = joinWallCorners([a, runB()]);
      final joined = out.firstWhere((q) => (q.yaw).abs() < 1e-9);
      expect(joined.polygon, hasLength(4));
      expect(
        joined.polygon.where((v) => (v.x - 2.0).abs() < 1e-9).length,
        2,
        reason: 'both vertices at the extended end moved by the gap',
      );
      expect(
        joined.polygon.any((v) => (v.x + 1.8).abs() < 1e-9 && v.y == 0),
        isTrue,
        reason: 'the far end is untouched',
      );
    });

    test('each end joins at most once per pass', () {
      final a = wall(x: 0, z: 2, width: 3.6);
      final first = wall(x: 2, z: 0, yaw: math.pi / 2, width: 3.6);
      // Another right-angle run claiming A's already-extended +x end.
      final second = wall(x: 2.05, z: 0, yaw: math.pi / 2, width: 3.6);
      final out = joinWallCorners([a, first, second]);
      expect(out[0].extentX, closeTo(3.8, 1e-9),
          reason: 'extended exactly once, toward the first claim');
      expect(identical(out[2], second), isTrue,
          reason: 'the second claim on the same end is refused');
    });

    test('a second pass is a no-op', () {
      final once = joinWallCorners([runA(), runB()]);
      final twice = joinWallCorners(once);
      for (var i = 0; i < once.length; i++) {
        expect(identical(twice[i], once[i]), isTrue,
            reason: 'ends already meet the intersection exactly');
      }
    });
  });

  group('capWallQuads', () {
    PlaneQuad wall(double ex, double ez) => PlaneQuad(
          center: Vector3.zero(),
          yaw: 0,
          extentX: ex,
          extentZ: ez,
          vertical: true,
          kind: PlaneQuadKind.wall,
        );

    test('past the cap only the biggest footprints survive', () {
      final capped = capWallQuads([wall(1, 2), wall(3, 3), wall(2, 2)], 2);
      expect(capped, hasLength(2));
      expect(capped.first.extentX, 3);
      expect(capped.last.extentX, 2);
    });

    test('under the cap the list passes through untouched', () {
      final few = [wall(1, 1), wall(2, 2)];
      expect(identical(capWallQuads(few, 5), few), isTrue);
    });
  });

  group('emaPolygon', () {
    test('the first sighting adopts the raw ring', () {
      final next = [Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)];
      final out = emaPolygon(null, next);
      expect(out, same(next));
    });

    test('later sightings blend toward the new vertices', () {
      // Sub-threshold jitter only — a jump past the reset shift snaps
      // (covered in the re-fit reset group).
      final prev = [Vector3.zero(), Vector3.zero(), Vector3.zero()];
      final next = [
        Vector3(0.05, 0, 0),
        Vector3(0, 0.05, 0),
        Vector3(0, 0, 0.05),
      ];
      final out = emaPolygon(prev, next, alpha: 0.35);
      expect(out[0].x, closeTo(0.0175, 1e-9));
      expect(out[1].y, closeTo(0.0175, 1e-9));
      expect(out[2].z, closeTo(0.0175, 1e-9));
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

  group('emaPolygon re-fit reset', () {
    test('a vertex jump past the reset shift snaps to the fresh ring', () {
      final prev = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 0, 1),
      ];
      final next = [
        Vector3(0.4, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 0, 1),
      ];
      expect(emaPolygon(prev, next, alpha: 0.35), same(next));
    });

    test('jitter under the reset shift still blends', () {
      final prev = [Vector3.zero(), Vector3(1, 0, 0), Vector3(1, 0, 1)];
      final next = [Vector3(0.05, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)];
      final out = emaPolygon(prev, next, alpha: 0.5);
      expect(out, isNot(same(next)));
      expect(out[0].x, closeTo(0.025, 1e-9));
    });
  });

  group('pushIntoFloorZone', () {
    final camera = Vector3(0, 1.5, 3);

    PlaneQuad openFloor() => PlaneQuad(
          center: Vector3.zero(),
          yaw: 0,
          extentX: 6,
          extentZ: 6,
          vertical: false,
          kind: PlaneQuadKind.floor,
        );

    // Detected object: 1 m × 1 m top at 0.75 m height, x ∈ [0.5, 1.5],
    // z ∈ [-0.5, 0.5].
    PlaneQuad objectTop() => PlaneQuad(
          center: Vector3(1, 0.75, 0),
          yaw: 0,
          extentX: 1,
          extentZ: 1,
          vertical: false,
          kind: PlaneQuadKind.floor,
        );

    test('a tap grazing the object slides out to the clearance', () {
      final out = pushIntoFloorZone(
        point: Vector3(0.35, 0, 0),
        masks: [objectTop()],
        floorZones: [openFloor()],
        cameraPos: camera,
        clearanceM: 0.3,
      );
      expect(out.x, closeTo(0.2, 1e-9));
      expect(out.y, 0);
      expect(out.z, closeTo(0, 1e-9));
    });

    test('a tap in open floor is untouched', () {
      final point = Vector3(-1, 0, 0);
      expect(
        pushIntoFloorZone(
          point: point,
          masks: [objectTop()],
          floorZones: [openFloor()],
          cameraPos: camera,
        ),
        same(point),
      );
    });

    test('a tap inside the object slides out past its edge', () {
      final out = pushIntoFloorZone(
        point: Vector3(1, 0, 0),
        masks: [objectTop()],
        floorZones: [openFloor()],
        cameraPos: camera,
        clearanceM: 0.3,
      );
      // Out through the nearest edge (x = 1.5) plus the clearance.
      expect(out.x, closeTo(1.8, 1e-9));
      expect(out.z, closeTo(0, 1e-9));
    });

    test('a push that would leave the floor zone is refused', () {
      final point = Vector3(0, 0, 0);
      final out = pushIntoFloorZone(
        point: point,
        masks: [
          PlaneQuad(
            center: Vector3(0, 0.75, 0),
            yaw: 0,
            extentX: 1,
            extentZ: 1,
            vertical: false,
            kind: PlaneQuadKind.floor,
          ),
        ],
        floorZones: [
          PlaneQuad(
            center: Vector3(2, 0, 0),
            yaw: 0,
            extentX: 2,
            extentZ: 2,
            vertical: false,
            kind: PlaneQuadKind.floor,
          ),
        ],
        cameraPos: camera,
      );
      expect(out, same(point),
          reason: 'never trade a bad landing for one off the detected floor');
    });

    test('a landing 4 cm past the zone edge is still accepted', () {
      // Push from inside the object lands at x = 0.04 while the floor
      // outline ends at x = 0 — cm-scale edge noise must not refuse it.
      final out = pushIntoFloorZone(
        point: Vector3(0.4, 0, 0),
        masks: [
          PlaneQuad(
            center: Vector3(0.84, 0.75, 0),
            yaw: 0,
            extentX: 1,
            extentZ: 1,
            vertical: false,
            kind: PlaneQuadKind.floor,
          ),
        ],
        floorZones: [
          PlaneQuad(
            center: Vector3(-1.5, 0, 0),
            yaw: 0,
            extentX: 3,
            extentZ: 6,
            vertical: false,
            kind: PlaneQuadKind.floor,
          ),
        ],
        cameraPos: camera,
        clearanceM: 0.3,
      );
      expect(out.x, closeTo(0.04, 1e-9));
      expect(out.z, closeTo(0, 1e-9));
    });

    test('no masks or no floor zones leaves the point alone', () {
      final point = Vector3(0.1, 0, 0);
      expect(
        pushIntoFloorZone(
          point: point,
          masks: const [],
          floorZones: [openFloor()],
          cameraPos: camera,
        ),
        same(point),
      );
      expect(
        pushIntoFloorZone(
          point: point,
          masks: [objectTop()],
          floorZones: const [],
          cameraPos: camera,
        ),
        same(point),
      );
    });
  });

  group('footprintFitsInZones', () {
    PlaneQuad floor(double ex, double ez,
            {Vector3? at, double yaw = 0}) =>
        PlaneQuad(
          center: at ?? Vector3.zero(),
          yaw: yaw,
          extentX: ex,
          extentZ: ez,
          vertical: false,
          kind: PlaneQuadKind.floor,
        );

    // Detected object: 1 m × 1 m top at 0.75 m height, x ∈ [0.5, 1.5],
    // z ∈ [-0.5, 0.5].
    PlaneQuad objectTop() => PlaneQuad(
          center: Vector3(1, 0.75, 0),
          yaw: 0,
          extentX: 1,
          extentZ: 1,
          vertical: false,
          kind: PlaneQuadKind.floor,
        );

    test('a sofa well inside a big floor fits', () {
      expect(
        footprintFitsInZones(
          center: Vector3.zero(),
          yaw: 0,
          widthM: 2.2,
          depthM: 0.9,
          floorZones: [floor(6, 6)],
        ),
        isTrue,
      );
    });

    test('a footprint wider than the detected floor is refused', () {
      expect(
        footprintFitsInZones(
          center: Vector3(0.5, 0, 0),
          yaw: 0,
          widthM: 2.2,
          depthM: 0.9,
          floorZones: [floor(2, 2)],
        ),
        isFalse,
        reason: 'right edge reaches 1.6 m — off the 2 m floor zone; '
            'a big sofa must not hide furniture outside the scan',
      );
    });

    test('rotation decides the fit: a long table fits diagonal, not '
        'parallel to the edge', () {
      expect(
        footprintFitsInZones(
          center: Vector3.zero(),
          yaw: 0,
          widthM: 7,
          depthM: 1,
          floorZones: [floor(6, 6)],
        ),
        isFalse,
      );
      expect(
        footprintFitsInZones(
          center: Vector3.zero(),
          yaw: math.pi / 4,
          widthM: 7,
          depthM: 1,
          floorZones: [floor(6, 6)],
        ),
        isTrue,
        reason: 'diagonal footprint spans ~5.7 m on both axes — inside '
            'the 6 m floor',
      );
    });

    test('a footprint overlapping a mask is refused', () {
      expect(
        footprintFitsInZones(
          center: Vector3(1, 0, 0),
          yaw: 0,
          widthM: 1,
          depthM: 1,
          floorZones: [floor(6, 6)],
          masks: [objectTop()],
        ),
        isFalse,
      );
    });

    test('mask clearance keeps the body off the object, not just '
        'non-overlapping', () {
      expect(
        footprintFitsInZones(
          center: Vector3(0.15, 0, 0),
          yaw: 0,
          widthM: 0.4,
          depthM: 0.4,
          floorZones: [floor(6, 6)],
          masks: [objectTop()],
        ),
        isTrue,
        reason: 'edge at 0.35 — 0.15 m from the object outline',
      );
      expect(
        footprintFitsInZones(
          center: Vector3(0.27, 0, 0),
          yaw: 0,
          widthM: 0.4,
          depthM: 0.4,
          floorZones: [floor(6, 6)],
          masks: [objectTop()],
        ),
        isFalse,
        reason: 'edge at 0.47 — only 0.03 m from the object outline',
      );
    });

    test('no detected floor zones fails open', () {
      expect(
        footprintFitsInZones(
          center: Vector3.zero(),
          yaw: 0,
          widthM: 3,
          depthM: 3,
          floorZones: const [],
        ),
        isTrue,
      );
    });

    test('zero-sized footprint fails open', () {
      expect(
        footprintFitsInZones(
          center: Vector3.zero(),
          yaw: 0,
          widthM: 0,
          depthM: 0,
          floorZones: [floor(6, 6)],
        ),
        isTrue,
      );
    });

    test('a 5 cm seam between floor fragments does not block placement', () {
      // ARCore splits one floor into fragments with cm-scale gaps; a
      // sample 2.5 cm past an outline still counts as floor.
      expect(
        footprintFitsInZones(
          center: Vector3(0.025, 0, 0),
          yaw: 0,
          widthM: 1,
          depthM: 1,
          floorZones: [
            floor(3, 6, at: Vector3(-1.5, 0, 0)),
            floor(2.95, 6, at: Vector3(1.525, 0, 0)),
          ],
        ),
        isTrue,
      );
    });

    test('a real hole in the floor still blocks placement', () {
      // Fragments 1 m apart: samples mid-hole sit 0.5 m from any outline,
      // far beyond the seam tolerance.
      expect(
        footprintFitsInZones(
          center: Vector3.zero(),
          yaw: 0,
          widthM: 1,
          depthM: 1,
          floorZones: [
            floor(2.5, 6, at: Vector3(-1.75, 0, 0)),
            floor(2.5, 6, at: Vector3(1.75, 0, 0)),
          ],
        ),
        isFalse,
      );
    });
  });

  group('pushIntoFloorZone with footprint', () {
    final camera = Vector3(0, 1.5, 3);

    PlaneQuad openFloor() => PlaneQuad(
          center: Vector3.zero(),
          yaw: 0,
          extentX: 6,
          extentZ: 6,
          vertical: false,
          kind: PlaneQuadKind.floor,
        );

    PlaneQuad objectTop() => PlaneQuad(
          center: Vector3(1, 0.75, 0),
          yaw: 0,
          extentX: 1,
          extentZ: 1,
          vertical: false,
          kind: PlaneQuadKind.floor,
        );

    test('a wide body slides further than a point would', () {
      // Tap 0.05 m from the object outline. A point-only push stops 0.3 m
      // out (x = 0.2); a 1 m-wide sofa needs its half-width (0.5) plus the
      // clearance along the push direction → x = -0.3.
      final out = pushIntoFloorZone(
        point: Vector3(0.45, 0, 0),
        masks: [objectTop()],
        floorZones: [openFloor()],
        cameraPos: camera,
        clearanceM: 0.3,
        halfWidthM: 0.5,
        halfDepthM: 0.3,
        footprintYaw: 0.0,
      );
      expect(out.x, closeTo(-0.3, 1e-9));
      expect(out.z, closeTo(0, 1e-9));
    });

    test('support extent follows the footprint yaw', () {
      // Same 3 m × 0.6 m body yawed 90°: the long axis now runs along Z,
      // so sliding along X only needs depth/2 + clearance = 0.6 total.
      final out = pushIntoFloorZone(
        point: Vector3(0.45, 0, 0),
        masks: [objectTop()],
        floorZones: [openFloor()],
        cameraPos: camera,
        clearanceM: 0.3,
        halfWidthM: 1.5,
        halfDepthM: 0.3,
        footprintYaw: math.pi / 2,
      );
      expect(out.x, closeTo(-0.1, 1e-9));
    });

    test('a pushed body that still cannot fit the floor is refused', () {
      // The body-aware push would land the 3 m sofa at x = -1.3 — its left
      // edge (-2.8) falls off a 2 m floor → keep the raw tap.
      final point = Vector3(0.45, 0, 0);
      final out = pushIntoFloorZone(
        point: point,
        masks: [objectTop()],
        floorZones: [
          PlaneQuad(
            center: Vector3.zero(),
            yaw: 0,
            extentX: 2,
            extentZ: 4,
            vertical: false,
            kind: PlaneQuadKind.floor,
          ),
        ],
        cameraPos: camera,
        clearanceM: 0.3,
        halfWidthM: 1.5,
        halfDepthM: 0.3,
        footprintYaw: 0.0,
      );
      expect(out, same(point));
    });
  });

  group('syntheticFloorQuad', () {
    PlaneQuad floorQuadAt(double y) => PlaneQuad(
          center: Vector3(1, y, 2),
          yaw: 0,
          extentX: 3,
          extentZ: 3,
          vertical: false,
          kind: PlaneQuadKind.floor,
        );

    test('null without floorY', () {
      expect(
        syntheticFloorQuad(
            floorY: null, cameraPos: Vector3(0, 1.5, 0), existing: const []),
        isNull,
      );
    });

    test('null without a camera position', () {
      expect(
        syntheticFloorQuad(floorY: 0, cameraPos: null, existing: const []),
        isNull,
      );
    });

    test('paints under the camera when no floor quad is near floorY', () {
      final quad = syntheticFloorQuad(
        floorY: 0.1,
        cameraPos: Vector3(2, 1.5, -3),
        existing: [floorQuadAt(0.8)],
      );
      expect(quad, isNotNull);
      expect(quad!.kind, PlaneQuadKind.floor);
      expect(quad.center.x, closeTo(2, 1e-9));
      expect(quad.center.y, closeTo(0.1, 1e-9));
      expect(quad.center.z, closeTo(-3, 1e-9));
      expect(quad.extentX, 2.0, reason: 'the stand-in stays small');
    });

    test('stays null when ARCore already paints a floor at that height', () {
      expect(
        syntheticFloorQuad(
            floorY: 0.1,
            cameraPos: Vector3(0, 1.5, 0),
            existing: [floorQuadAt(0.12)]),
        isNull,
      );
    });

    test('a floating plane far above floorY does not suppress it', () {
      expect(
        syntheticFloorQuad(
            floorY: 0.1,
            cameraPos: Vector3(0, 1.5, 0),
            existing: [floorQuadAt(0.75)]),
        isNotNull,
      );
    });
  });

  group('rectHitsPolygons', () {
    List<Vector3> square(double cx, double cz, double half) => [
          Vector3(cx - half, 0, cz - half),
          Vector3(cx + half, 0, cz - half),
          Vector3(cx + half, 0, cz + half),
          Vector3(cx - half, 0, cz + half),
        ];

    bool hit({
      required Vector3 center,
      double yaw = 0,
      double widthM = 0.5,
      double depthM = 0.5,
      required List<List<Vector3>> polygons,
      double clearanceM = 0.05,
    }) =>
        rectHitsPolygons(
          center: center,
          yaw: yaw,
          widthM: widthM,
          depthM: depthM,
          polygons: polygons,
          clearanceM: clearanceM,
        );

    test('empty polygons never hit', () {
      expect(
        hit(center: Vector3.zero(), polygons: const []),
        isFalse,
      );
    });

    test('a rect inside the polygon hits', () {
      expect(
        hit(center: Vector3.zero(), polygons: [square(0, 0, 0.5)]),
        isTrue,
      );
    });

    test('a rect far from every polygon is clear', () {
      expect(
        hit(center: Vector3(3, 0, 3), polygons: [square(0, 0, 0.5)]),
        isFalse,
      );
    });

    test('a rect within clearance of the outline hits', () {
      // Rect spans x ∈ [0.43, 0.93] — fully outside the hole (edge 0.4)
      // but its near sample is 0.03 from the outline (< 0.05 clearance).
      expect(
        hit(center: Vector3(0.68, 0, 0), polygons: [square(0, 0, 0.4)]),
        isTrue,
      );
      expect(
        hit(center: Vector3(0.72, 0, 0), polygons: [square(0, 0, 0.4)]),
        isFalse,
        reason: 'nearest sample is 0.07 out — past the 0.05 clearance',
      );
    });

    test('a small polygon fully inside the rect hits (vertex containment)',
        () {
      expect(
        hit(
          center: Vector3.zero(),
          widthM: 0.5,
          depthM: 0.5,
          polygons: [square(0.02, 0.02, 0.03)],
        ),
        isTrue,
      );
    });

    test('a yawed rect still detects the polygon', () {
      // Same geometry rotated 45° — samples land on the polygon either way.
      expect(
        hit(center: Vector3.zero(), yaw: math.pi / 4, polygons: [
          square(0, 0, 0.5)
        ]),
        isTrue,
      );
      expect(
        hit(center: Vector3(3, 0, 0), yaw: math.pi / 4, polygons: [
          square(0, 0, 0.5)
        ]),
        isFalse,
      );
    });
  });
}
