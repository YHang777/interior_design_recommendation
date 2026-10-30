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
