import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/finish_footprint.dart';
import 'package:vector_math/vector_math_64.dart';

FinishFootprint floorTile({double x = 0, double y = 0, double z = 0, double yaw = 0, double size = 3.0}) {
  return FinishFootprint.floor(
    center: Vector3(x, y, z),
    yaw: yaw,
    sizeM: size,
  );
}

FinishFootprint wallPanel({double x = 0, double y = 1.35, double z = 0, double yaw = 0, double w = 2.4, double h = 2.7}) {
  return FinishFootprint.wall(
    center: Vector3(x, y, z),
    yaw: yaw,
    widthM: w,
    heightM: h,
  );
}

void main() {
  group('FinishFootprint floor tiles', () {
    test('a tile placed on top of another always overlaps', () {
      expect(floorTile().overlaps(floorTile()), isTrue);
    });

    test('edge-to-edge neighbors never overlap', () {
      // 3 m tiles with centers exactly 3 m apart share an edge only.
      expect(floorTile(x: 1.5).overlaps(floorTile(x: -1.5)), isFalse);
    });

    test('a few cm of placement jitter is tolerated (no visible stack)', () {
      expect(floorTile(x: 1.49).overlaps(floorTile(x: -1.5)), isFalse);
    });

    test('a real overlap zone is refused', () {
      expect(floorTile(x: 1.0).overlaps(floorTile(x: -1.0)), isTrue);
    });

    test('diagonal neighbors touching at the corner never overlap', () {
      expect(
        floorTile(x: 1.5, z: 1.5).overlaps(floorTile(x: -1.5, z: -1.5)),
        isFalse,
      );
    });

    test('a rotated tile poking into a neighbor is caught', () {
      expect(
        floorTile(x: 2.0, yaw: math.pi / 4)
            .overlaps(floorTile(x: -0.6, yaw: 0)),
        isTrue,
      );
    });

    test('far apart tiles never overlap', () {
      expect(floorTile(x: 5).overlaps(floorTile(x: -5)), isFalse);
    });

    test('tiles at different heights never overlap', () {
      expect(floorTile(y: 0).overlaps(floorTile(y: 1.0)), isFalse);
    });
  });

  group('FinishFootprint wall panels', () {
    test('a panel placed on top of another always overlaps', () {
      expect(wallPanel().overlaps(wallPanel()), isTrue);
    });

    test('side-by-side panels on the same wall never overlap', () {
      expect(wallPanel(x: 1.2).overlaps(wallPanel(x: -1.2)), isFalse);
    });

    test('panels on the same wall with a real overlap zone are refused', () {
      expect(wallPanel(x: 0.8).overlaps(wallPanel(x: -0.8)), isTrue);
    });

    test('panels facing opposite directions never stack', () {
      expect(wallPanel(yaw: 0).overlaps(wallPanel(yaw: math.pi)), isFalse);
    });

    test('panels on perpendicular walls never stack', () {
      expect(wallPanel(yaw: 0).overlaps(wallPanel(yaw: math.pi / 2)), isFalse);
    });

    test('panels on parallel walls at different depths never stack', () {
      expect(wallPanel(z: 0).overlaps(wallPanel(z: 0.5)), isFalse);
      expect(wallPanel(z: 0).overlaps(wallPanel(z: 0.1)), isTrue);
    });

    test('vertically offset panels only stack when heights overlap', () {
      expect(wallPanel(y: 0.6).overlaps(wallPanel(y: 3.5)), isFalse);
      expect(wallPanel(y: 0.6).overlaps(wallPanel(y: 1.8)), isTrue);
    });
  });

  group('FinishFootprint cross-kind', () {
    test('a floor tile and a wall panel never count as stacked', () {
      expect(floorTile().overlaps(wallPanel()), isFalse);
      expect(wallPanel().overlaps(floorTile()), isFalse);
    });

    test('fromTransform reads center and yaw like the anchors write them', () {
      final m = Matrix4.identity()
        ..setTranslation(Vector3(1, 0, 2))
        ..rotateY(math.pi / 2);
      final fp = FinishFootprint.fromTransform(
        FinishKind.floor,
        m,
        widthM: 3,
        heightM: 3,
      );
      expect(fp.center.x, closeTo(1, 1e-9));
      expect(fp.center.z, closeTo(2, 1e-9));
      expect(fp.yaw, closeTo(math.pi / 2, 1e-9));
    });

    test('withYaw only changes the yaw', () {
      final fp = floorTile(x: 1, z: 2).withYaw(1.2);
      expect(fp.yaw, closeTo(1.2, 1e-9));
      expect(fp.center.x, closeTo(1, 1e-9));
    });
  });
}
