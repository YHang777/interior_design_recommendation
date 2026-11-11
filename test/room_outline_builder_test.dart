import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_overlay_math.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/room_outline_builder.dart';
import 'package:vector_math/vector_math_64.dart';

// A vertical wall quad running along [yaw]'s direction: center is the middle
// of the run at 1.2 m up, extentX the run length, extentZ the wall height.
PlaneQuad wall({
  required double x,
  required double z,
  required double len,
  required double yaw,
  bool vertical = true,
  PlaneQuadKind kind = PlaneQuadKind.wall,
  List<Vector3> polygon = const [],
}) =>
    PlaneQuad(
      center: Vector3(x, 1.2, z),
      yaw: yaw,
      extentX: len,
      extentZ: 2.4,
      vertical: vertical,
      kind: kind,
      polygon: polygon,
    );

bool hasCorner(RoomOutline o, double xCm, double yCm, {double tol = 1}) => o
    .walls
    .any((w) => (w.dx - xCm).abs() <= tol && (w.dy - yCm).abs() <= tol);

double shoelaceCm2(List<Offset> ring) {
  var sum = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum.abs() / 2;
}

void main() {
  group('buildRoomOutline', () {
    test('rectangle 4×3 m exports four corners in cm', () {
      final out = buildRoomOutline([
        wall(x: 2, z: 0, len: 4, yaw: 0),
        wall(x: 2, z: 3, len: 4, yaw: 0),
        wall(x: 0, z: 1.5, len: 3, yaw: -math.pi / 2),
        wall(x: 4, z: 1.5, len: 3, yaw: -math.pi / 2),
      ]);
      expect(out, isNotNull);
      expect(out!.walls, hasLength(4));
      expect(out.widthCm, closeTo(400, 1));
      expect(out.heightCm, closeTo(300, 1));
      for (final c in [
        (0.0, 0.0),
        (400.0, 0.0),
        (400.0, 300.0),
        (0.0, 300.0),
      ]) {
        expect(hasCorner(out, c.$1, c.$2), isTrue,
            reason: 'missing corner $c in ${out.walls}');
      }
    });

    test('L-shape keeps its concavity — six walls, area 12 m²', () {
      final out = buildRoomOutline([
        wall(x: 2, z: 0, len: 4, yaw: 0), // south 0,0 → 4,0
        wall(x: 4, z: 1, len: 2, yaw: -math.pi / 2), // east 4,0 → 4,2
        wall(x: 3, z: 2, len: 2, yaw: 0), // inner horizontal 4,2 → 2,2
        wall(x: 2, z: 3, len: 2, yaw: -math.pi / 2), // inner vertical 2,2 → 2,4
        wall(x: 1, z: 4, len: 2, yaw: 0), // north 2,4 → 0,4
        wall(x: 0, z: 2, len: 4, yaw: -math.pi / 2), // west 0,4 → 0,0
      ]);
      expect(out, isNotNull);
      expect(out!.walls, hasLength(6));
      expect(out.widthCm, closeTo(400, 1));
      expect(out.heightCm, closeTo(400, 1));
      expect(shoelaceCm2(out.walls), closeTo(120000, 1),
          reason: 'must be the 12 m² L, not the 16 m² bounding box');
      expect(hasCorner(out, 200, 200), isTrue,
          reason: 'the reentrant corner is a real vertex of the L');
      expect(hasCorner(out, 400, 400), isFalse,
          reason: 'the bounding-box corner the L does not cover');
    });

    test('collinear fragments of one wall merge before chaining', () {
      final out = buildRoomOutline([
        wall(x: 0.9, z: 0, len: 1.8, yaw: 0), // south 0,0 → 1.8,0
        wall(x: 3.1, z: 0, len: 1.8, yaw: 0), // south 2.2,0 → 4,0
        wall(x: 2, z: 3, len: 4, yaw: 0),
        wall(x: 0, z: 1.5, len: 3, yaw: -math.pi / 2),
        wall(x: 4, z: 1.5, len: 3, yaw: -math.pi / 2),
      ]);
      expect(out, isNotNull);
      expect(out!.walls, hasLength(4),
          reason: 'the 0.4 m seam must not become a corner');
      expect(out.widthCm, closeTo(400, 1));
      expect(hasCorner(out, 0, 0), isTrue);
      expect(hasCorner(out, 400, 0), isTrue);
    });

    test('a doorway-sized gap seals across the opening', () {
      final out = buildRoomOutline([
        wall(x: 0.625, z: 0, len: 1.25, yaw: 0), // south 0,0 → 1.25,0
        wall(x: 3.375, z: 0, len: 1.25, yaw: 0), // south 2.75,0 → 4,0
        wall(x: 2, z: 3, len: 4, yaw: 0),
        wall(x: 0, z: 1.5, len: 3, yaw: -math.pi / 2),
        wall(x: 4, z: 1.5, len: 3, yaw: -math.pi / 2),
      ]);
      expect(out, isNotNull);
      expect(out!.walls, hasLength(5),
          reason: 'sealing the door adds a vertex at the midpoint');
      expect(out.widthCm, closeTo(400, 1));
      expect(out.heightCm, closeTo(300, 1));
      expect(hasCorner(out, 200, 0, tol: 1), isTrue,
          reason: 'door midpoint seals onto the south line');
      expect(shoelaceCm2(out.walls), closeTo(120000, 1),
          reason: 'the seal closes the room, not a notch');
    });

    test('an unscanned wall fails instead of exporting a wrong shape', () {
      final out = buildRoomOutline([
        wall(x: 2, z: 3, len: 4, yaw: 0), // north
        wall(x: 0, z: 1.5, len: 3, yaw: -math.pi / 2), // west
        wall(x: 4, z: 1.5, len: 3, yaw: -math.pi / 2), // east — south missing
      ]);
      expect(out, isNull, reason: '4 m gap is a lost wall, not a doorway');
    });

    test('fewer than three segments never exports', () {
      expect(
        buildRoomOutline([
          wall(x: 2, z: 0, len: 4, yaw: 0),
          wall(x: 2, z: 3, len: 4, yaw: 0),
        ]),
        isNull,
      );
    });

    test('floor quads are ignored', () {
      expect(
        buildRoomOutline([
          wall(x: 2, z: 0, len: 4, yaw: 0),
          wall(x: 2, z: 3, len: 4, yaw: 0),
          wall(x: 2, z: 1.5, len: 3, yaw: math.pi / 2, vertical: false,
              kind: PlaneQuadKind.floor),
        ]),
        isNull,
      );
    });

    test('a wall carrying ARCore\'s true polygon exports the same ring', () {
      final out = buildRoomOutline([
        wall(
          x: 2,
          z: 0,
          len: 4,
          yaw: 0,
          polygon: [
            Vector3(0, 0.1, 0),
            Vector3(4, 0.1, 0),
            Vector3(4, 2.4, 0),
            Vector3(0, 2.4, 0),
          ],
        ),
        wall(x: 2, z: 3, len: 4, yaw: 0),
        wall(x: 0, z: 1.5, len: 3, yaw: -math.pi / 2),
        wall(x: 4, z: 1.5, len: 3, yaw: -math.pi / 2),
      ]);
      expect(out, isNotNull);
      expect(out!.walls, hasLength(4));
      expect(out.widthCm, closeTo(400, 1));
      expect(out.heightCm, closeTo(300, 1));
      expect(hasCorner(out, 0, 0), isTrue);
      expect(hasCorner(out, 400, 0), isTrue);
    });
  });
}
