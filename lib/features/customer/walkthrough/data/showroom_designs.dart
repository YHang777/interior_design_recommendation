import 'package:flutter/material.dart' show IconData, Icons, Offset;

import '../../../../models/room_design.dart';

// Curated predesigned rooms the walkthrough's showroom offers for
// inspiration: each is a full RoomDesign so the same controller/painter
// walks it — no special-case rendering for canned rooms.
//
// Plan coordinates are cm: x runs east, y runs south, the north wall is
// y = 0. Models face +Z (south) at rotation 0, so a piece against the north
// wall uses 0, south wall 180, west wall 270 and east wall 90. Rotations of
// 90/270 swap the footprint, so x/y is always the footprint's top-left.

class ShowroomRoom {
  const ShowroomRoom({
    required this.name,
    required this.description,
    required this.icon,
    required this.design,
  });

  final String name;

  final String description;

  final IconData icon;

  final RoomDesign design;
}

// A catalogue piece (its model comes from the catalogue icon mapping).
FurniturePlacement _f(
  String id,
  String name,
  String iconName,
  double x,
  double y,
  double w,
  double h, [
  double rotation = 0,
  String? imageAsset,
  String? modelUrl,
]) =>
    FurniturePlacement(
      id: id,
      name: name,
      iconName: iconName,
      x: x,
      y: y,
      width: w,
      height: h,
      rotation: rotation,
      imageAsset: imageAsset,
      modelUrl: modelUrl,
    );

// A decor piece with its own model, true height and optional height above
// the floor (wall art, pendant lamps, tabletop pieces). Exception to the +Z
// rule: the standing photo frame's picture faces +X, so it needs 90° less
// than a piece facing the same way (0 faces east, 90 south, 180 west).
FurniturePlacement _d(
  String id,
  String name,
  String model,
  double x,
  double y,
  double w,
  double d,
  double h, {
  double rotation = 0,
  double? elevation,
  String iconName = 'decor',
}) =>
    FurniturePlacement(
      id: id,
      name: name,
      iconName: iconName,
      x: x,
      y: y,
      width: w,
      height: d,
      rotation: rotation,
      heightCm: h,
      elevationCm: elevation,
      modelUrl: 'assets/models/ph_$model.glb',
      imageAsset: 'assets/images/furniture_ph_$model.png',
    );

// Wall-hung art (frames, clock, mirror), specified by the wall it hangs on
// using the furniture rotation convention (north wall 0, east 90, south 180,
// west 270) — the art faces into the room.
FurniturePlacement _art(
  String id,
  String name,
  String model,
  double x,
  double y,
  double w,
  double d,
  double h, {
  required double wall,
  required double elevation,
}) =>
    _d(id, name, model, x, y, w, d, h,
        rotation: wall, elevation: elevation);

List<Offset> _box(double w, double h) =>
    [Offset.zero, Offset(w, 0), Offset(w, h), Offset(0, h)];

// ── Reused decor sizes (cm) ──
// Framed art hangs with its centre ~150 cm up; the pendant's cord reaches
// the 270 cm ceiling.
const _pendantElev = 270.0 - 95.0;

final showroomRooms = <ShowroomRoom>[
  ShowroomRoom(
    name: 'Modern Living Room',
    description:
        'A blue velvet sofa, a lounge chair by the window wall and oak floors '
        'under soft duck-egg walls.',
    icon: Icons.weekend,
    design: RoomDesign(
      id: 'showroom-living',
      name: 'Modern Living Room',
      roomType: 'living_room',
      widthCm: 500,
      heightCm: 400,
      walls: _box(500, 400),
      floorFinishType: 'woodPlanks',
      floorFinishColor: 0xFFB08D6B,
      wallFinishType: 'paint',
      wallFinishColor: 0xFFBCD2CE,
      furniture: [
        _f('s1', 'TV Stand', 'tv_stand', 128, 5, 244, 52, 0,
            'assets/images/furniture_ph_modern_wooden_cabinet.png'),
        _f('s2', 'Velvet Sofa', 'velvet_sofa', 140, 295, 219, 102, 180,
            'assets/images/furniture_kh_glam_velvet_sofa.png'),
        _f('s3', 'Rug', 'rug', 140, 150, 220, 150, 0,
            'assets/images/furniture_rug_modern.png'),
        _f('s4', 'Coffee Table', 'coffee_table', 190, 205, 120, 60, 0,
            'assets/images/furniture_ph_modern_coffee_table_01.png'),
        _f('s5', 'Lounge Chair', 'lounge_chair', 370, 150, 101, 119, 90,
            'assets/images/furniture_ph_mid_century_lounge_chair.png'),
        _f('s6', 'Side Table', 'side_table', 375, 330, 55, 45, 0,
            'assets/images/furniture_ph_side_table_01.png'),
        _f('s7', 'Floor Lamp', 'floor_lamp', 105, 360, 25, 25, 0,
            'assets/images/furniture_lamp_floor.png'),
        _f('s8', 'Plant', 'plant', 20, 20, 70, 66, 0,
            'assets/images/furniture_ph_potted_plant_02.png'),
        _d('s9', 'Tall Plant', 'potted_plant_01', 425, 10, 59, 63, 135,
            iconName: 'small_plant'),
        _art('s10', 'Landscape Print', 'hanging_picture_frame_02', 212, 396.7,
            75, 3.3, 50, wall: 180, elevation: 120),
        _art('s11', 'Oval Frame', 'hanging_picture_frame_03', 0, 160, 38.5,
            2.1, 50, wall: 270, elevation: 125),
        _art('s12', 'Wall Clock', 'wall_clock', 234, 0, 32, 3.5, 32,
            wall: 0, elevation: 175),
        _d('s13', 'Vase', 'ceramic_vase_01', 150, 20, 20.4, 20.4, 40,
            elevation: 68),
        _d('s14', 'Vase', 'ceramic_vase_02', 245, 225, 21.8, 21.8, 31,
            elevation: 39),
        _d('s15', 'Vase', 'ceramic_vase_02', 392, 342, 21.8, 21.8, 31,
            elevation: 55),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: '',
    ),
  ),
  ShowroomRoom(
    name: 'Cozy Bedroom',
    description:
        'Honey parquet, whitewashed wood panelling and a bed flanked by '
        'classic nightstands.',
    icon: Icons.bed,
    design: RoomDesign(
      id: 'showroom-bedroom',
      name: 'Cozy Bedroom',
      roomType: 'bedroom',
      widthCm: 500,
      heightCm: 400,
      walls: _box(500, 400),
      floorFinishType: 'parquet',
      floorFinishColor: 0xFFD9B076,
      wallFinishType: 'woodPanels',
      wallFinishColor: 0xFFDDD6C9,
      furniture: [
        FurniturePlacement(
          id: 'b1',
          name: 'Bed',
          iconName: 'bed',
          x: 10,
          y: 115,
          width: 170,
          height: 205,
          rotation: 270,
          heightCm: 110,
          imageAsset: 'assets/images/furniture_bed_modern.png',
        ),
        _d('b2', 'Nightstand', 'classicnightstand_01', 10, 55, 56.8, 42.4,
            70, rotation: 270, iconName: 'nightstand'),
        _d('b3', 'Nightstand', 'classicnightstand_01', 10, 288, 56.8, 42.4,
            70, rotation: 270, iconName: 'nightstand'),
        _f('b4', 'Rug', 'rug', 190, 110, 230, 180, 0,
            'assets/images/furniture_rug_modern.png'),
        _f('b5', 'Cabinet', 'cabinet', 445, 40, 114, 49, 90,
            'assets/images/furniture_ph_drawer_cabinet.png'),
        _f('b6', 'Velvet Chair', 'velvet_chair', 430, 290, 83, 57, 90,
            'assets/images/furniture_kh_sheen_chair.png'),
        _f('b7', 'Floor Lamp', 'floor_lamp', 440, 370, 25, 25, 0,
            'assets/images/furniture_lamp_floor.png'),
        _d('b8', 'Tall Plant', 'potted_plant_01', 360, 10, 59, 63, 135,
            iconName: 'small_plant'),
        _d('b9', 'Basket', 'wicker_basket_02', 230, 320, 37.5, 27.1, 22,
            iconName: 'basket'),
        _art('b10', 'Portrait Print', 'hanging_picture_frame_01', 0, 170.5,
            59.4, 1.6, 84, wall: 270, elevation: 125),
        _d('b11', 'Photo Frame', 'standing_picture_frame_02', 20, 72, 10.2,
            21.7, 26.6, elevation: 70),
        _d('b12', 'Vase', 'ceramic_vase_02', 18, 305, 21.8, 21.8, 31,
            elevation: 70),
        _art('b13', 'Mirror', 'ornate_mirror_01', 200, 397.4, 48.6, 2.6, 74.4, wall: 180, elevation: 95),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: '',
    ),
  ),
  ShowroomRoom(
    name: 'Family Kitchen',
    description:
        'White tile floors, painted brick and a round table under a pendant '
        'light — breakfast to homework.',
    icon: Icons.kitchen,
    design: RoomDesign(
      id: 'showroom-kitchen',
      name: 'Family Kitchen',
      roomType: 'kitchen',
      widthCm: 400,
      heightCm: 350,
      walls: _box(400, 350),
      floorFinishType: 'ceramicTiles',
      floorFinishColor: 0xFFF2F0EA,
      wallFinishType: 'brick',
      wallFinishColor: 0xFFE0D8CD,
      furniture: [
        _f('k1', 'Cabinet', 'cabinet', 20, 5, 114, 49, 0,
            'assets/images/furniture_ph_drawer_cabinet.png'),
        _d('k2', 'Stove', 'electric_stove', 145, 0, 50.3, 64.8, 85.9,
            iconName: 'stove'),
        _f('k3', 'Industrial Shelf', 'industrial_shelf', 210, 5, 110, 50, 0,
            'assets/images/furniture_ph_steel_frame_shelves_01.png'),
        _f('k4', 'Round Dining Table', 'round_dining_table', 25, 190, 140,
            140, 0, 'assets/images/furniture_ph_round_wooden_table_01.png'),
        _f('k5', 'Dining Chair', 'dining_chair', 73.5, 135, 43, 58, 0,
            'assets/images/furniture_ph_dining_chair_02.png'),
        _f('k6', 'Dining Chair', 'dining_chair', 73.5, 290, 43, 58, 180,
            'assets/images/furniture_ph_dining_chair_02.png'),
        _f('k7', 'Dining Chair', 'dining_chair', 2, 238.5, 43, 58, 270,
            'assets/images/furniture_ph_dining_chair_02.png'),
        _f('k8', 'Dining Chair', 'dining_chair', 130, 238.5, 43, 58, 90,
            'assets/images/furniture_ph_dining_chair_02.png'),
        _d('k9', 'Pendant Lamp', 'modern_ceiling_lamp_01', 73.4, 238.4, 43.2,
            43.2, 95, elevation: _pendantElev, iconName: 'pendant_lamp'),
        _d('k10', 'Vase', 'ceramic_vase_01', 85, 250, 20.4, 20.4, 40,
            elevation: 75),
        _f('k11', 'Plant', 'plant', 325, 280, 70, 66, 0,
            'assets/images/furniture_ph_potted_plant_02.png'),
        _art('k12', 'Wall Clock', 'wall_clock', 396.5, 120, 32, 3.5, 32, wall: 90, elevation: 170),
        _art('k13', 'Landscape Print', 'hanging_picture_frame_02', 0, 70, 75,
            3.3, 50, wall: 270, elevation: 130),
        _d('k14', 'Basket', 'wicker_basket_02', 335, 15, 37.5, 27.1, 22,
            iconName: 'basket'),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: '',
    ),
  ),
  ShowroomRoom(
    name: 'Bright Dining Room',
    description:
        'Walnut floors and warm off-white walls around a table for four, '
        'lit by a pendant and framed by greenery.',
    icon: Icons.table_restaurant,
    design: RoomDesign(
      id: 'showroom-dining',
      name: 'Bright Dining Room',
      roomType: 'dining_room',
      widthCm: 500,
      heightCm: 400,
      walls: _box(500, 400),
      floorFinishType: 'woodPlanks',
      floorFinishColor: 0xFF6B4A32,
      wallFinishType: 'paint',
      wallFinishColor: 0xFFE9E4D9,
      furniture: [
        _f('d1', 'Rug', 'rug', 150, 100, 200, 200, 0,
            'assets/images/furniture_rug_modern.png'),
        FurniturePlacement(
          id: 'd2',
          name: 'Dining Table',
          iconName: 'dining_table',
          x: 185,
          y: 135,
          width: 130,
          height: 130,
          heightCm: 75,
          imageAsset: 'assets/images/furniture_table_dining.png',
        ),
        _f('d3', 'Dining Chair', 'dining_chair', 228.5, 85, 43, 58, 0,
            'assets/images/furniture_ph_dining_chair_02.png'),
        _f('d4', 'Dining Chair', 'dining_chair', 228.5, 257, 43, 58, 180,
            'assets/images/furniture_ph_dining_chair_02.png'),
        _f('d5', 'Dining Chair', 'dining_chair', 135, 178.5, 43, 58, 270,
            'assets/images/furniture_ph_dining_chair_02.png'),
        _f('d6', 'Dining Chair', 'dining_chair', 307, 178.5, 43, 58, 90,
            'assets/images/furniture_ph_dining_chair_02.png'),
        _d('d7', 'Pendant Lamp', 'modern_ceiling_lamp_01', 228.4, 178.4,
            43.2, 43.2, 95, elevation: _pendantElev, iconName: 'pendant_lamp'),
        _d('d8', 'Vase', 'ceramic_vase_01', 240, 190, 20.4, 20.4, 40,
            elevation: 75),
        _f('d9', 'Sideboard', 'tv_stand', 128, 348, 244, 52, 180,
            'assets/images/furniture_ph_modern_wooden_cabinet.png'),
        _art('d10', 'Landscape Print', 'hanging_picture_frame_02', 212.5,
            396.7, 75, 3.3, 50, wall: 180, elevation: 115),
        _d('d11', 'Vase', 'ceramic_vase_02', 160, 362, 21.8, 21.8, 31,
            elevation: 68),
        _f('d12', 'Plant', 'plant', 15, 15, 70, 66, 0,
            'assets/images/furniture_ph_potted_plant_02.png'),
        _d('d13', 'Tall Plant', 'potted_plant_01', 425, 15, 59, 63, 135,
            iconName: 'small_plant'),
        _art('d14', 'Wall Clock', 'wall_clock', 0, 184, 32, 3.5, 32, wall: 270, elevation: 165),
        _art('d15', 'Oval Frame', 'hanging_picture_frame_03', 497.9, 180.75,
            38.5, 2.1, 50, wall: 90, elevation: 130),
        _art('d16', 'Mirror', 'ornate_mirror_01', 225.7, 0, 48.6, 2.6, 74.4,
            wall: 0, elevation: 100),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: '',
    ),
  ),
  ShowroomRoom(
    name: 'Focused Home Office',
    description:
        'Walnut panelling, grey oak floors and a big desk facing the wall — '
        'with a lounge corner for reading.',
    icon: Icons.desk,
    design: RoomDesign(
      id: 'showroom-office',
      name: 'Focused Home Office',
      roomType: 'home_office',
      widthCm: 400,
      heightCm: 350,
      walls: _box(400, 350),
      floorFinishType: 'woodPlanks',
      floorFinishColor: 0xFF9A948A,
      wallFinishType: 'woodPanels',
      wallFinishColor: 0xFF6B4A32,
      furniture: [
        _f('o1', 'Office Desk', 'office_desk', 100, 10, 200, 95, 0,
            'assets/images/furniture_ph_metal_office_desk.png'),
        _f('o2', 'Dining Chair', 'dining_chair', 178.5, 100, 43, 58, 180,
            'assets/images/furniture_ph_dining_chair_02.png'),
        _f('o3', 'Bookshelf', 'bookshelf', 5, 120, 108, 37, 270,
            'assets/images/furniture_ph_wooden_display_shelves_01.png'),
        _f('o4', 'Industrial Shelf', 'industrial_shelf', 345, 110, 110, 50,
            90, 'assets/images/furniture_ph_steel_frame_shelves_01.png'),
        _f('o5', 'Rug', 'rug', 110, 175, 170, 120, 0,
            'assets/images/furniture_rug_modern.png'),
        _f('o6', 'Lounge Chair', 'lounge_chair', 240, 228, 101, 119, 180,
            'assets/images/furniture_ph_mid_century_lounge_chair.png'),
        _f('o7', 'Side Table', 'side_table', 180, 295, 55, 45, 0,
            'assets/images/furniture_ph_side_table_01.png'),
        _f('o8', 'Floor Lamp', 'floor_lamp', 350, 320, 25, 25, 0,
            'assets/images/furniture_lamp_floor.png'),
        _d('o9', 'Tall Plant', 'potted_plant_01', 10, 280, 59, 63, 135,
            iconName: 'small_plant'),
        _d('o10', 'Photo Frame', 'standing_picture_frame_02', 115, 25, 10.2,
            21.7, 26.6, rotation: 90, elevation: 79),
        _art('o11', 'Portrait Print', 'hanging_picture_frame_01', 170.3, 0,
            59.4, 1.6, 84, wall: 0, elevation: 115),
        _art('o12', 'Wall Clock', 'wall_clock', 184, 346.5, 32, 3.5, 32, wall: 180, elevation: 170),
        _d('o13', 'Basket', 'wicker_basket_02', 308, 20, 37.5, 27.1, 22,
            iconName: 'basket'),
        _d('o14', 'Vase', 'ceramic_vase_02', 197, 307, 21.8, 21.8, 31,
            elevation: 55),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: '',
    ),
  ),
  ShowroomRoom(
    name: 'Minimalist Studio',
    description:
        'An L-shaped loft in exposed orange brick and polished cement — '
        'sleep in the nook, lounge by the window.',
    icon: Icons.apartment,
    design: RoomDesign(
      id: 'showroom-studio',
      name: 'Minimalist Studio',
      roomType: 'living_room',
      widthCm: 500,
      heightCm: 400,
      walls: const [
        Offset(0, 0),
        Offset(500, 0),
        Offset(500, 250),
        Offset(300, 250),
        Offset(300, 400),
        Offset(0, 400),
      ],
      floorFinishType: 'cement',
      floorFinishColor: 0xFFC9C6BF,
      wallFinishType: 'brick',
      wallFinishColor: 0xFFBC6A41,
      furniture: [
        FurniturePlacement(
          id: 't1',
          name: 'Bed',
          iconName: 'bed',
          x: 283,
          y: 70,
          width: 170,
          height: 215,
          rotation: 90,
          heightCm: 110,
          imageAsset: 'assets/images/furniture_bed_modern.png',
        ),
        _d('t2', 'Nightstand', 'classicnightstand_01', 456, 10, 56.8, 42.4,
            70, rotation: 90, iconName: 'nightstand'),
        _art('t3', 'Landscape Print', 'hanging_picture_frame_02', 496.7, 117.5,
            75, 3.3, 50, wall: 90, elevation: 125),
        _f('t4', 'Sofa', 'sofa', 5, 150, 180, 90, 270,
            'assets/images/furniture_sofa_modern.png',
            'assets/models/apartment_sofa.glb'),
        _f('t5', 'Rug', 'rug', 85, 160, 160, 160, 0,
            'assets/images/furniture_rug_modern.png'),
        _f('t6', 'Coffee Table', 'coffee_table', 120, 180, 120, 60, 90,
            'assets/images/furniture_ph_modern_coffee_table_01.png'),
        _f('t7', 'Accent Chair', 'accent_chair', 190, 300, 82, 99, 90,
            'assets/images/furniture_ph_modern_arm_chair_01.png'),
        _f('t8', 'Floor Lamp', 'floor_lamp', 15, 345, 25, 25, 0,
            'assets/images/furniture_lamp_floor.png'),
        _f('t9', 'Cabinet', 'cabinet', 20, 5, 114, 49, 0,
            'assets/images/furniture_ph_drawer_cabinet.png'),
        _f('t10', 'Plant', 'plant', 210, 10, 70, 66, 0,
            'assets/images/furniture_ph_potted_plant_02.png'),
        _d('t11', 'Vase', 'ceramic_vase_02', 135, 230, 21.8, 21.8, 31,
            elevation: 39),
        _art('t12', 'Wall Clock', 'wall_clock', 150, 0, 32, 3.5, 32,
            wall: 0, elevation: 170),
        _d('t13', 'Photo Frame', 'standing_picture_frame_02', 470, 25, 10.2,
            21.7, 26.6, rotation: 180, elevation: 70),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: '',
    ),
  ),
];
