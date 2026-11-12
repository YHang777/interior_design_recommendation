import 'package:flutter/material.dart' show IconData, Icons, Offset;

import '../../../../models/room_design.dart';

// Curated predesigned rooms the walkthrough's showroom offers for
// inspiration: each is a full RoomDesign so the same controller/painter
// walks it — no special-case rendering for canned rooms.

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
    );

List<Offset> _box(double w, double h) =>
    [Offset.zero, Offset(w, 0), Offset(w, h), Offset(0, h)];

final showroomRooms = <ShowroomRoom>[
  ShowroomRoom(
    name: 'Modern Living Room',
    description:
        'Warm oak tones, a deep sofa and soft rug — a calm base for family life.',
    icon: Icons.weekend,
    design: RoomDesign(
      id: 'showroom-living',
      name: 'Modern Living Room',
      roomType: 'living_room',
      widthCm: 500,
      heightCm: 400,
      walls: _box(500, 400),
      furniture: [
        _f('s1', 'Sofa', 'sofa', 160, 305, 180, 90, 0,
            'assets/images/furniture_sofa_modern.png'),
        _f('s2', 'Coffee Table', 'coffee_table', 200, 235, 100, 50, 0,
            'assets/images/furniture_table_coffee.png'),
        _f('s3', 'TV Stand', 'tv_stand', 180, 5, 140, 45),
        _f('s4', 'Rug', 'rug', 170, 180, 160, 120, 0,
            'assets/images/furniture_rug_modern.png'),
        _f('s5', 'Armchair', 'armchair', 400, 200, 70, 70, 0,
            'assets/images/furniture_chair_modern.png'),
        _f('s6', 'Floor Lamp', 'floor_lamp', 25, 25, 25, 25, 0,
            'assets/images/furniture_lamp_floor.png'),
        _f('s7', 'Plant', 'plant', 445, 345, 30, 30, 0,
            'assets/images/plant.jpg'),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: '',
    ),
  ),
  ShowroomRoom(
    name: 'Cozy Bedroom',
    description:
        'A quiet retreat: generous bed, warm lamp light and room to breathe.',
    icon: Icons.bed,
    design: RoomDesign(
      id: 'showroom-bedroom',
      name: 'Cozy Bedroom',
      roomType: 'bedroom',
      widthCm: 450,
      heightCm: 400,
      walls: _box(450, 400),
      furniture: [
        _f('b1', 'Bed', 'bed', 125, 235, 200, 160, 0,
            'assets/images/furniture_bed_modern.png'),
        _f('b2', 'Rug', 'rug', 145, 95, 160, 120, 0,
            'assets/images/furniture_rug_modern.png'),
        _f('b3', 'Cabinet', 'cabinet', 10, 10, 90, 50, 0,
            'assets/images/furniture_cabinet_modern.png'),
        _f('b4', 'Floor Lamp', 'floor_lamp', 395, 25, 25, 25, 0,
            'assets/images/furniture_lamp_floor.png'),
        _f('b5', 'Plant', 'plant', 395, 345, 30, 30, 0,
            'assets/images/plant.jpg'),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: '',
    ),
  ),
  ShowroomRoom(
    name: 'Family Kitchen',
    description:
        'Eat-in kitchen where cooking and homework happen at the same table.',
    icon: Icons.kitchen,
    design: RoomDesign(
      id: 'showroom-kitchen',
      name: 'Family Kitchen',
      roomType: 'kitchen',
      widthCm: 400,
      heightCm: 350,
      walls: _box(400, 350),
      furniture: [
        _f('k1', 'Dining Table', 'dining_table', 230, 125, 140, 100, 0,
            'assets/images/furniture_table_dining.png'),
        _f('k2', 'Armchair', 'armchair', 250, 35, 70, 70, 0,
            'assets/images/furniture_chair_modern.png'),
        _f('k3', 'Armchair', 'armchair', 250, 235, 70, 70, 0,
            'assets/images/furniture_chair_modern.png'),
        _f('k4', 'Cabinet', 'cabinet', 15, 10, 90, 50, 0,
            'assets/images/furniture_cabinet_modern.png'),
        _f('k5', 'Cabinet', 'cabinet', 115, 10, 90, 50, 0,
            'assets/images/furniture_cabinet_modern.png'),
        _f('k6', 'Plant', 'plant', 25, 295, 30, 30, 0,
            'assets/images/plant.jpg'),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: '',
    ),
  ),
  ShowroomRoom(
    name: 'Bright Dining Room',
    description:
        'A table made for long dinners, framed by soft light and greenery.',
    icon: Icons.table_restaurant,
    design: RoomDesign(
      id: 'showroom-dining',
      name: 'Bright Dining Room',
      roomType: 'dining_room',
      widthCm: 450,
      heightCm: 350,
      walls: _box(450, 350),
      furniture: [
        _f('d1', 'Dining Table', 'dining_table', 250, 125, 140, 100, 0,
            'assets/images/furniture_table_dining.png'),
        _f('d2', 'Armchair', 'armchair', 265, 35, 70, 70, 0,
            'assets/images/furniture_chair_modern.png'),
        _f('d3', 'Armchair', 'armchair', 265, 235, 70, 70, 0,
            'assets/images/furniture_chair_modern.png'),
        _f('d4', 'Armchair', 'armchair', 135, 125, 70, 70, 0,
            'assets/images/furniture_chair_modern.png'),
        _f('d5', 'Rug', 'rug', 235, 115, 160, 120, 0,
            'assets/images/furniture_rug_modern.png'),
        _f('d6', 'Plant', 'plant', 25, 25, 30, 30, 0,
            'assets/images/plant.jpg'),
        _f('d7', 'Floor Lamp', 'floor_lamp', 400, 25, 25, 25, 0,
            'assets/images/furniture_lamp_floor.png'),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: '',
    ),
  ),
  ShowroomRoom(
    name: 'Focused Home Office',
    description:
        'Clear desk, clear head — a workspace that keeps distractions out.',
    icon: Icons.desk,
    design: RoomDesign(
      id: 'showroom-office',
      name: 'Focused Home Office',
      roomType: 'home_office',
      widthCm: 400,
      heightCm: 350,
      walls: _box(400, 350),
      furniture: [
        _f('o1', 'Desk', 'desk', 140, 15, 120, 60, 0,
            'assets/images/furniture_desk_modern.png'),
        _f('o2', 'Bookshelf', 'bookshelf', 355, 25, 90, 30, 90),
        _f('o3', 'Armchair', 'armchair', 45, 235, 70, 70, 0,
            'assets/images/furniture_chair_modern.png'),
        _f('o4', 'Rug', 'rug', 120, 140, 160, 120, 0,
            'assets/images/furniture_rug_modern.png'),
        _f('o5', 'Floor Lamp', 'floor_lamp', 25, 25, 25, 25, 0,
            'assets/images/furniture_lamp_floor.png'),
        _f('o6', 'Plant', 'plant', 345, 295, 30, 30, 0,
            'assets/images/plant.jpg'),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: '',
    ),
  ),
  ShowroomRoom(
    name: 'Minimalist Studio',
    description:
        'One open L-shaped space that lives large — sleep, lounge, repeat.',
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
      furniture: [
        _f('t1', 'Sofa', 'sofa', 30, 305, 180, 90, 0,
            'assets/images/furniture_sofa_modern.png'),
        _f('t2', 'Coffee Table', 'coffee_table', 70, 225, 100, 50, 0,
            'assets/images/furniture_table_coffee.png'),
        _f('t3', 'Bed', 'bed', 290, 80, 200, 160, 0,
            'assets/images/furniture_bed_modern.png'),
        _f('t4', 'Cabinet', 'cabinet', 25, 15, 90, 50, 0,
            'assets/images/furniture_cabinet_modern.png'),
        _f('t5', 'Plant', 'plant', 245, 315, 30, 30, 0,
            'assets/images/plant.jpg'),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: '',
    ),
  ),
];
