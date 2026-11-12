import 'package:flutter/material.dart' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/scanner/data/room_fit.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

void main() {
  FurniturePlacement piece({
    double x = 0,
    double y = 0,
    double w = 180,
    double h = 90,
    double rotation = 0,
  }) =>
      FurniturePlacement(
        id: 'sofa-1',
        name: 'Sofa',
        iconName: 'sofa',
        x: x,
        y: y,
        width: w,
        height: h,
        rotation: rotation,
      );

  const innerWalls = [
    Offset(100, 100),
    Offset(300, 100),
    Offset(300, 400),
    Offset(100, 400),
  ];

  group('furnitureRect / distToRect', () {
    test('rotation swaps the footprint', () {
      expect(furnitureRect(piece()), const Rect.fromLTWH(0, 0, 180, 90));
      expect(furnitureRect(piece(rotation: 90)), const Rect.fromLTWH(0, 0, 90, 180));
      expect(furnitureRect(piece(rotation: 180)), const Rect.fromLTWH(0, 0, 180, 90));
    });

    test('distance is zero inside and on the edge', () {
      const r = Rect.fromLTWH(10, 10, 10, 10);
      expect(distToRect(const Offset(15, 15), r), 0);
      expect(distToRect(const Offset(10, 15), r), 0);
      expect(distToRect(const Offset(5, 5), r), closeTo(7.0710678, 1e-5));
      expect(distToRect(const Offset(25, 15), r), closeTo(5, 1e-9));
    });
  });

  group('placementFits', () {
    test('a piece fully inside the wall ring fits', () {
      expect(
        placementFits(piece(x: 120, y: 150),
            roomW: 400, roomH: 500, walls: innerWalls),
        isTrue,
      );
    });

    test('a piece straddling the wall ring does not fit', () {
      // Left edge outside the ring (x=50 < 100) — classic wall-straddle.
      expect(
        placementFits(piece(x: 50, y: 200),
            roomW: 400, roomH: 500, walls: innerWalls),
        isFalse,
      );
    });

    test('a piece outside the room rectangle does not fit', () {
      expect(
        placementFits(piece(x: 350, y: 400), roomW: 400, roomH: 500, walls: const []),
        isFalse,
      );
    });
  });

  group('clampAllPlacements (render clamp)', () {
    test('valid placements are kept exactly where they are', () {
      final f = piece(x: 120, y: 150);
      final out = clampAllPlacements([f], roomW: 400, roomH: 500, walls: innerWalls);
      expect(out.single.x, f.x);
      expect(out.single.y, f.y);
    });

    test('wall-straddling legacy placements settle inside near the drop', () {
      final f = piece(x: 50, y: 200);
      final out = clampAllPlacements([f], roomW: 400, roomH: 500, walls: innerWalls);
      final settled = out.single;
      expect(
        placementFits(settled, roomW: 400, roomH: 500, walls: innerWalls),
        isTrue,
        reason: 'render clamp must never leave a piece inside a wall',
      );
      expect((settled.x - f.x).abs(), lessThan(80),
          reason: 'settles near the drop point, not the room center');
      expect((settled.y - f.y).abs(), lessThan(80));
    });
  });
}
