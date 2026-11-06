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
        modelFile: 'folding_table.glb',
        widthMeters: 1.0,
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
        modelFile: 'folding_table.glb',
        widthMeters: 1.0,
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
        modelFile: 'folding_table.glb',
        widthMeters: 1.0,
        icon: Icons.inventory_2,
        placement: PlacementType.floor),
    'bookshelf': ArFurnitureItem(
        name: 'Bookshelf',
        modelFile: 'standing_desk.glb',
        widthMeters: 1.4,
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
        modelFile: 'bauhaus_chair.glb',
        widthMeters: 0.5,
        icon: Icons.eco,
        placement: PlacementType.floor),
    'tv_stand': ArFurnitureItem(
        name: 'TV Stand',
        modelFile: 'folding_table.glb',
        widthMeters: 1.4,
        icon: Icons.tv,
        placement: PlacementType.floor),
    'rug': ArFurnitureItem(
        name: 'Rug',
        modelFile: 'folding_table.glb',
        widthMeters: 1.2,
        icon: Icons.view_agenda,
        placement: PlacementType.floor),
  };

  static ArFurnitureItem forIconName(String? iconName) {
    if (iconName == null) return _fallback;
    return _byIconName[iconName.toLowerCase()] ?? _fallback;
  }

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
