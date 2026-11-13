import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/planner_scene_bridge.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/room_fit.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/walkthrough_controller.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

// A partition across the middle of a 400 × 500 room, x = 0…300 at y = 250.
const _partition = [
  [Offset(0, 250), Offset(300, 250)],
];

FurniturePlacement _piece({double x = 0, double y = 0, double w = 100, double h = 60}) =>
    FurniturePlacement(
        id: 'p', name: 'Sofa', iconName: 'sofa', x: x, y: y, width: w, height: h);

RoomDesign _design({List<List<Offset>> interior = _partition}) => RoomDesign(
      id: 'd',
      name: 'Room',
      roomType: 'living_room',
      widthCm: 400,
      heightCm: 500,
      interiorWalls: interior,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      userId: 'u',
    );

void main() {
  group('furniture vs interior walls', () {
    test('a footprint crossing a partition does not fit', () {
      expect(
          placementFits(_piece(x: 50, y: 220),
              roomW: 400, roomH: 500, walls: const [], interiorWalls: _partition),
          isFalse);
    });

    test('a footprint flush against a wall face fits', () {
      // Wall slab spans y 245…255; a piece ending at y = 245 touches it.
      expect(
          placementFits(_piece(x: 50, y: 185),
              roomW: 400, roomH: 500, walls: const [], interiorWalls: _partition),
          isTrue);
    });

    test('a drop onto a partition settles beside it, not through it', () {
      final r = resolveDrop(_piece(x: 50, y: 220),
          roomW: 400, roomH: 500, walls: const [], interiorWalls: _partition);
      expect(
          placementFits(r,
              roomW: 400, roomH: 500, walls: const [], interiorWalls: _partition),
          isTrue);
      expect(rectHitsInteriorWalls(furnitureRect(r), _partition), isFalse);
    });

    test('a lone corner post blocks its 10 cm square', () {
      const post = [
        [Offset(200, 200)]
      ];
      expect(
          rectHitsInteriorWalls(const Rect.fromLTWH(150, 150, 100, 100), post),
          isTrue);
      expect(
          rectHitsInteriorWalls(const Rect.fromLTWH(0, 0, 100, 100), post),
          isFalse);
    });
  });

  group('walkthrough', () {
    test('the walker cannot pass through a partition', () {
      final ctl = WalkthroughController(design: _design());
      ctl.walker = const Offset(150, 150);
      ctl.heading = 1.5707963267948966; // south, toward the wall at y = 250
      for (var i = 0; i < 10; i++) {
        ctl.walk(1);
      }
      expect(ctl.walker.dy,
          lessThan(250 - WalkthroughController.walkerRadiusCm));
    });

    test('the gap past the partition end is still walkable', () {
      final ctl = WalkthroughController(design: _design());
      ctl.walker = const Offset(370, 150);
      ctl.heading = 1.5707963267948966;
      for (var i = 0; i < 6; i++) {
        ctl.walk(1);
      }
      expect(ctl.walker.dy, greaterThan(250));
    });
  });

  group('persistence', () {
    test('interior walls round-trip through JSON', () {
      final d = _design(interior: const [
        [Offset(10, 20), Offset(30, 40), Offset(50, 60)],
        [Offset(100, 100)],
      ]);
      final back = RoomDesign.fromJson(d.toJson());
      expect(back.interiorWalls, hasLength(2));
      expect(back.interiorWalls[0], d.interiorWalls[0]);
      expect(back.interiorWalls[1], d.interiorWalls[1]);
    });

    test('interior walls load from the packed furniture column', () {
      final row = {
        'id': 'd',
        'name': 'Room',
        'furniture': {
          'items': [],
          'walls': [],
          'interiorWalls': [
            [
              [0, 250],
              [300, 250]
            ]
          ],
        },
      };
      final d = RoomDesign.fromJson(row);
      expect(d.interiorWalls.single,
          const [Offset(0, 250), Offset(300, 250)]);
    });

    test('designs without interior walls keep their JSON shape', () {
      expect(_design(interior: const []).toJson().containsKey('interiorWalls'),
          isFalse);
    });
  });

  group('3D', () {
    test('every chain segment becomes a wall slab; a lone corner a post', () {
      final drafts = interiorWallDrafts(
        chains: const [
          [Offset(0, 250), Offset(300, 250), Offset(300, 400)],
          [Offset(50, 50)],
        ],
        roomWCm: 400,
        roomHCm: 500,
      );
      expect(drafts, hasLength(3));
      expect(drafts[2].aCm, drafts[2].bCm, reason: 'post');
    });

    test('a partition between the camera and the room center is cut low', () {
      final near = interiorWallDrafts(
        chains: const [
          [Offset(0, 450), Offset(400, 450)]
        ],
        roomWCm: 400,
        roomHCm: 500,
        cameraCm: const Offset(200, 900),
      );
      expect(near.single.cut, isTrue);
    });
  });
}
