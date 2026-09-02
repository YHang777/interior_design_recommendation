import 'package:flutter/material.dart';

/// An AR-placeable furniture item backed by a bundled .glb model.
class ArFurnitureItem {
  const ArFurnitureItem({
    required this.name,
    required this.modelFile,
    required this.widthMeters,
    this.icon = Icons.chair,
  });

  /// Display name (shown in the AR catalog bar).
  final String name;

  /// File name under `assets/models/` (bundled Flutter assets).
  /// Models are MIT-licensed, sourced from github.com/chayanforyou/ARFurniture.
  final String modelFile;

  /// Target max dimension of the model in meters.
  /// The plugin passes this as SceneView's `scaleToUnits`, i.e. the model's
  /// bounding box is normalized to this size when placed.
  final double widthMeters;

  final IconData icon;

  /// URI used with `NodeType.localGLTF2`. The plugin resolves these URIs
  /// through Flutter's `getLookupKeyForAsset`, i.e. against the app's
  /// bundled Flutter assets. The files therefore live in `assets/models/`
  /// (registered in pubspec.yaml under `flutter/assets`); the asset key
  /// passed to `getLookupKeyForAsset` omits the leading `assets/`, so the
  /// key is `models/<file>.glb`. Paths are case-sensitive at runtime.
  String get uri => 'models/$modelFile';
}

/// Maps the app's furniture catalog / product categories to the bundled
/// 3D models so saved floor plans can be viewed in real AR.
class ArFurnitureLibrary {
  ArFurnitureLibrary._();

  // ─── All available bundled models ───
  static const List<ArFurnitureItem> all = [
    ArFurnitureItem(
        name: 'Sofa',
        modelFile: 'three_seater_sofa.glb',
        widthMeters: 2.2,
        icon: Icons.weekend),
    ArFurnitureItem(
        name: 'Corner Sofa',
        modelFile: 'corner_sofa.glb',
        widthMeters: 2.6,
        icon: Icons.weekend_outlined),
    ArFurnitureItem(
        name: 'Apartment Sofa',
        modelFile: 'apartment_sofa.glb',
        widthMeters: 2.0,
        icon: Icons.weekend_outlined),
    ArFurnitureItem(
        name: 'Tuxedo Sofa',
        modelFile: 'tuxedo_sofa.glb',
        widthMeters: 2.2,
        icon: Icons.weekend_outlined),
    ArFurnitureItem(
        name: 'Armchair',
        modelFile: 'bauhaus_chair.glb',
        widthMeters: 0.85,
        icon: Icons.chair),
    ArFurnitureItem(
        name: 'Dining Table',
        modelFile: 'dining_table.glb',
        widthMeters: 1.6,
        icon: Icons.table_restaurant),
    ArFurnitureItem(
        name: 'Dining Set',
        modelFile: 'dining_table_set.glb',
        widthMeters: 2.0,
        icon: Icons.table_restaurant_outlined),
    ArFurnitureItem(
        name: 'Coffee Table',
        modelFile: 'folding_table.glb',
        widthMeters: 1.0,
        icon: Icons.table_bar),
    ArFurnitureItem(
        name: 'Bed',
        modelFile: 'double_bed.glb',
        widthMeters: 2.1,
        icon: Icons.bed),
    ArFurnitureItem(
        name: 'Standing Desk',
        modelFile: 'standing_desk.glb',
        widthMeters: 1.4,
        icon: Icons.desk),
  ];

  /// Placeholder used when no matching 3D model exists for an item.
  static const ArFurnitureItem _fallback = ArFurnitureItem(
      name: 'Furniture',
      modelFile: 'folding_table.glb',
      widthMeters: 1.0,
      icon: Icons.chair);

  /// Maps the room-scanner catalog `iconName`s to 3D models.
  /// Entries marked (placeholder) have no exact model and reuse the closest
  /// available shape — the chip still shows the real item name.
  static const Map<String, ArFurnitureItem> _byIconName = {
    'sofa': ArFurnitureItem(
        name: 'Sofa',
        modelFile: 'three_seater_sofa.glb',
        widthMeters: 2.2,
        icon: Icons.weekend),
    'armchair': ArFurnitureItem(
        name: 'Armchair',
        modelFile: 'bauhaus_chair.glb',
        widthMeters: 0.85,
        icon: Icons.chair),
    'coffee_table': ArFurnitureItem(
        name: 'Coffee Table',
        modelFile: 'folding_table.glb',
        widthMeters: 1.0,
        icon: Icons.table_bar),
    'dining_table': ArFurnitureItem(
        name: 'Dining Table',
        modelFile: 'dining_table.glb',
        widthMeters: 1.6,
        icon: Icons.table_restaurant),
    'bed': ArFurnitureItem(
        name: 'Bed',
        modelFile: 'double_bed.glb',
        widthMeters: 2.1,
        icon: Icons.bed),
    'desk': ArFurnitureItem(
        name: 'Desk',
        modelFile: 'standing_desk.glb',
        widthMeters: 1.4,
        icon: Icons.desk),
    // Placeholders — no exact model bundled yet
    'cabinet': ArFurnitureItem(
        name: 'Cabinet',
        modelFile: 'folding_table.glb',
        widthMeters: 1.0,
        icon: Icons.inventory_2),
    'bookshelf': ArFurnitureItem(
        name: 'Bookshelf',
        modelFile: 'standing_desk.glb',
        widthMeters: 1.4,
        icon: Icons.menu_book),
    'floor_lamp': ArFurnitureItem(
        name: 'Floor Lamp',
        modelFile: 'standing_desk.glb',
        widthMeters: 0.6,
        icon: Icons.lightbulb),
    'plant': ArFurnitureItem(
        name: 'Plant',
        modelFile: 'bauhaus_chair.glb',
        widthMeters: 0.5,
        icon: Icons.eco),
    'tv_stand': ArFurnitureItem(
        name: 'TV Stand',
        modelFile: 'folding_table.glb',
        widthMeters: 1.4,
        icon: Icons.tv),
    'rug': ArFurnitureItem(
        name: 'Rug',
        modelFile: 'folding_table.glb',
        widthMeters: 1.2,
        icon: Icons.view_agenda),
  };

  /// Maps marketplace product categories to 3D models.
  static const Map<String, ArFurnitureItem> _byCategory = {
    'furniture': ArFurnitureItem(
        name: 'Furniture',
        modelFile: 'three_seater_sofa.glb',
        widthMeters: 2.2,
        icon: Icons.weekend),
    'lighting': ArFurnitureItem(
        name: 'Lighting',
        modelFile: 'standing_desk.glb',
        widthMeters: 1.4,
        icon: Icons.lightbulb),
    'decor': ArFurnitureItem(
        name: 'Decor',
        modelFile: 'bauhaus_chair.glb',
        widthMeters: 0.85,
        icon: Icons.chair),
    'flooring': ArFurnitureItem(
        name: 'Flooring',
        modelFile: 'folding_table.glb',
        widthMeters: 1.0,
        icon: Icons.view_agenda),
    'wall': ArFurnitureItem(
        name: 'Wall',
        modelFile: 'folding_table.glb',
        widthMeters: 1.0,
        icon: Icons.view_agenda),
    'textiles': ArFurnitureItem(
        name: 'Textiles',
        modelFile: 'corner_sofa.glb',
        widthMeters: 2.6,
        icon: Icons.weekend_outlined),
  };

  /// Returns the AR model for a room-scanner catalog `iconName`.
  static ArFurnitureItem forIconName(String? iconName) {
    if (iconName == null) return _fallback;
    return _byIconName[iconName.toLowerCase()] ?? _fallback;
  }

  /// Returns the AR model for a marketplace product category.
  static ArFurnitureItem forCategory(String? category) {
    if (category == null) return _fallback;
    return _byCategory[category.toLowerCase()] ?? _fallback;
  }

  /// Builds the AR catalog for a list of catalog icon names
  /// (e.g. the furniture of a saved design), in order, without duplicates.
  static List<ArFurnitureItem> fromIconNames(List<String> iconNames) {
    final result = <ArFurnitureItem>[];
    final seen = <String>{};
    for (final name in iconNames) {
      final item = forIconName(name);
      if (seen.add(item.modelFile)) result.add(item);
    }
    return result.isEmpty ? all : result;
  }

  /// Builds a single-item catalog for a marketplace product category.
  static List<ArFurnitureItem> fromCategory(String? category) =>
      [forCategory(category)];
}
