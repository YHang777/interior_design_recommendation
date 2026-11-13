import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'glb_bounds.dart';

enum PlacementType {
  floor,

  wall,

  any,
}

class ArFurnitureItem {
  const ArFurnitureItem({
    required this.name,
    required this.modelFile,
    required this.widthMeters,
    this.icon = Icons.chair,
    this.placement = PlacementType.floor,
  });

  // Const instances → footprint cache lives here, keyed by model file
  // (several catalogue entries share a file; null results memoize too).
  static final Map<
      String,
      ({double widthM, double depthM, double centerX, double centerZ})?>
      _footprintCache = {};

  final String name;

  final String modelFile;

  final double widthMeters;

  final IconData icon;

  final PlacementType placement;

  String get uri => 'assets/models/$modelFile';

  // World-space footprint: the library scales the GLB so its longest edge
  // equals widthMeters (SceneView scaleToUnits = units / largestEdge), so
  // every bounds component scales by widthMeters / maxExtent. Null when the
  // asset can't be parsed → callers fail open.
  Future<({double widthM, double depthM, double centerX, double centerZ})?>
      worldFootprint() async {
    final cached = _footprintCache[modelFile];
    if (cached != null || _footprintCache.containsKey(modelFile)) return cached;
    ({double widthM, double depthM, double centerX, double centerZ})? fp;
    try {
      final data = await rootBundle.load(uri);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final b = GlbBounds.fromGlbBytes(bytes);
      final extent = b.maxExtent;
      if (extent.isFinite && extent > 0) {
        final s = widthMeters / extent;
        fp = (
          widthM: b.widthM * s,
          depthM: b.depthM * s,
          centerX: b.centerX * s,
          centerZ: b.centerZ * s,
        );
      }
    } catch (_) {
      fp = null;
    }
    _footprintCache[modelFile] = fp;
    return fp;
  }
}

class ArFurnitureLibrary {
  ArFurnitureLibrary._();

  // ─── All available bundled models ───
  static const List<ArFurnitureItem> all = [
    ArFurnitureItem(
        name: 'Sofa',
        modelFile: 'three_seater_sofa.glb',
        widthMeters: 2.2,
        icon: Icons.weekend,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Corner Sofa',
        modelFile: 'corner_sofa.glb',
        widthMeters: 2.6,
        icon: Icons.weekend_outlined,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Apartment Sofa',
        modelFile: 'apartment_sofa.glb',
        widthMeters: 2.0,
        icon: Icons.weekend_outlined,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Tuxedo Sofa',
        modelFile: 'tuxedo_sofa.glb',
        widthMeters: 2.2,
        icon: Icons.weekend_outlined,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Armchair',
        modelFile: 'bauhaus_chair.glb',
        widthMeters: 0.85,
        icon: Icons.chair,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Dining Table',
        modelFile: 'dining_table.glb',
        widthMeters: 1.6,
        icon: Icons.table_restaurant,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Dining Set',
        modelFile: 'dining_table_set.glb',
        widthMeters: 2.0,
        icon: Icons.table_restaurant_outlined,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Coffee Table',
        modelFile: 'ph_modern_coffee_table_01.glb',
        widthMeters: 1.2,
        icon: Icons.table_bar,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Bed',
        modelFile: 'double_bed.glb',
        widthMeters: 2.1,
        icon: Icons.bed,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Standing Desk',
        modelFile: 'standing_desk.glb',
        widthMeters: 1.4,
        icon: Icons.desk,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Lounge Chair',
        modelFile: 'ph_mid_century_lounge_chair.glb',
        widthMeters: 1.01,
        icon: Icons.event_seat,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Accent Chair',
        modelFile: 'ph_modern_arm_chair_01.glb',
        widthMeters: 0.82,
        icon: Icons.chair_alt,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Dining Chair',
        modelFile: 'ph_dining_chair_02.glb',
        widthMeters: 0.43,
        icon: Icons.chair,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Ottoman',
        modelFile: 'ph_ottoman_01.glb',
        widthMeters: 0.88,
        icon: Icons.crop_square,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Chesterfield Sofa',
        modelFile: 'ph_sofa_02.glb',
        widthMeters: 1.81,
        icon: Icons.weekend,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Bar Stool',
        modelFile: 'ph_bar_chair_round_01.glb',
        widthMeters: 0.48,
        icon: Icons.chair_alt,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Side Table',
        modelFile: 'ph_side_table_01.glb',
        widthMeters: 0.55,
        icon: Icons.table_bar,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Round Coffee Table',
        modelFile: 'ph_coffee_table_round_01.glb',
        widthMeters: 1.3,
        icon: Icons.circle_outlined,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Chest of Drawers',
        modelFile: 'ph_vintage_wooden_drawer_01.glb',
        widthMeters: 1.72,
        icon: Icons.inventory,
        placement: PlacementType.floor),
    ArFurnitureItem(
        name: 'Office Desk',
        modelFile: 'ph_metal_office_desk.glb',
        widthMeters: 2.0,
        icon: Icons.desk,
        placement: PlacementType.floor),
  ];

  static const ArFurnitureItem _fallback = ArFurnitureItem(
      name: 'Furniture',
      modelFile: 'folding_table.glb',
      widthMeters: 1.0,
      icon: Icons.chair,
      placement: PlacementType.floor);

  static const Map<String, ArFurnitureItem> _byIconName = {
    'sofa': ArFurnitureItem(
        name: 'Sofa',
        modelFile: 'three_seater_sofa.glb',
        widthMeters: 2.2,
        icon: Icons.weekend,
        placement: PlacementType.floor),
    'armchair': ArFurnitureItem(
        name: 'Armchair',
        modelFile: 'bauhaus_chair.glb',
        widthMeters: 0.85,
        icon: Icons.chair,
        placement: PlacementType.floor),
    'coffee_table': ArFurnitureItem(
        name: 'Coffee Table',
        modelFile: 'ph_modern_coffee_table_01.glb',
        widthMeters: 1.2,
        icon: Icons.table_bar,
        placement: PlacementType.floor),
    'dining_table': ArFurnitureItem(
        name: 'Dining Table',
        modelFile: 'dining_table.glb',
        widthMeters: 1.6,
        icon: Icons.table_restaurant,
        placement: PlacementType.floor),
    'bed': ArFurnitureItem(
        name: 'Bed',
        modelFile: 'double_bed.glb',
        widthMeters: 2.1,
        icon: Icons.bed,
        placement: PlacementType.floor),
    'desk': ArFurnitureItem(
        name: 'Desk',
        modelFile: 'standing_desk.glb',
        widthMeters: 1.4,
        icon: Icons.desk,
        placement: PlacementType.floor),
    'cabinet': ArFurnitureItem(
        name: 'Cabinet',
        modelFile: 'ph_drawer_cabinet.glb',
        widthMeters: 1.14,
        icon: Icons.inventory_2,
        placement: PlacementType.floor),
    'bookshelf': ArFurnitureItem(
        name: 'Bookshelf',
        modelFile: 'ph_wooden_display_shelves_01.glb',
        widthMeters: 1.08,
        icon: Icons.menu_book,
        placement: PlacementType.floor),
    'floor_lamp': ArFurnitureItem(
        name: 'Floor Lamp',
        modelFile: 'standing_desk.glb',
        widthMeters: 0.6,
        icon: Icons.lightbulb,
        placement: PlacementType.floor),
    'plant': ArFurnitureItem(
        name: 'Plant',
        modelFile: 'ph_potted_plant_02.glb',
        widthMeters: 0.7,
        icon: Icons.eco,
        placement: PlacementType.floor),
    'tv_stand': ArFurnitureItem(
        name: 'TV Stand',
        modelFile: 'ph_modern_wooden_cabinet.glb',
        widthMeters: 2.44,
        icon: Icons.tv,
        placement: PlacementType.floor),
    'rug': ArFurnitureItem(
        name: 'Rug',
        modelFile: 'folding_table.glb',
        widthMeters: 1.2,
        icon: Icons.view_agenda,
        placement: PlacementType.floor),
    'lounge_chair': ArFurnitureItem(
        name: 'Lounge Chair',
        modelFile: 'ph_mid_century_lounge_chair.glb',
        widthMeters: 1.01,
        icon: Icons.event_seat,
        placement: PlacementType.floor),
    'accent_chair': ArFurnitureItem(
        name: 'Accent Chair',
        modelFile: 'ph_modern_arm_chair_01.glb',
        widthMeters: 0.82,
        icon: Icons.chair_alt,
        placement: PlacementType.floor),
    'dining_chair': ArFurnitureItem(
        name: 'Dining Chair',
        modelFile: 'ph_dining_chair_02.glb',
        widthMeters: 0.43,
        icon: Icons.chair,
        placement: PlacementType.floor),
    'ottoman': ArFurnitureItem(
        name: 'Ottoman',
        modelFile: 'ph_ottoman_01.glb',
        widthMeters: 0.88,
        icon: Icons.crop_square,
        placement: PlacementType.floor),
    'chesterfield_sofa': ArFurnitureItem(
        name: 'Chesterfield Sofa',
        modelFile: 'ph_sofa_02.glb',
        widthMeters: 1.81,
        icon: Icons.weekend,
        placement: PlacementType.floor),
    'bar_stool': ArFurnitureItem(
        name: 'Bar Stool',
        modelFile: 'ph_bar_chair_round_01.glb',
        widthMeters: 0.48,
        icon: Icons.chair_alt,
        placement: PlacementType.floor),
    'side_table': ArFurnitureItem(
        name: 'Side Table',
        modelFile: 'ph_side_table_01.glb',
        widthMeters: 0.55,
        icon: Icons.table_bar,
        placement: PlacementType.floor),
    'round_coffee_table': ArFurnitureItem(
        name: 'Round Coffee Table',
        modelFile: 'ph_coffee_table_round_01.glb',
        widthMeters: 1.3,
        icon: Icons.circle_outlined,
        placement: PlacementType.floor),
    'chest_of_drawers': ArFurnitureItem(
        name: 'Chest of Drawers',
        modelFile: 'ph_vintage_wooden_drawer_01.glb',
        widthMeters: 1.72,
        icon: Icons.inventory,
        placement: PlacementType.floor),
    'office_desk': ArFurnitureItem(
        name: 'Office Desk',
        modelFile: 'ph_metal_office_desk.glb',
        widthMeters: 2.0,
        icon: Icons.desk,
        placement: PlacementType.floor),
  };

  static ArFurnitureItem forIconName(String? iconName) {
    if (iconName == null) return _fallback;
    return _byIconName[iconName.toLowerCase()] ?? _fallback;
  }

  // True only for an explicit library entry — unknown names fall back to a
  // stand-in shape, so callers that care about shape ask this first.
  static bool hasModelFor(String? iconName) =>
      iconName != null && _byIconName.containsKey(iconName.toLowerCase());

  static List<ArFurnitureItem> fromIconNames(List<String> iconNames) {
    final result = <ArFurnitureItem>[];
    final seen = <String>{};
    for (final name in iconNames) {
      final item = forIconName(name);
      if (seen.add(item.modelFile)) result.add(item);
    }
    return result.isEmpty ? all : result;
  }
}
