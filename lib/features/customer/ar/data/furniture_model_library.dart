import 'package:flutter/material.dart';

/// Where an AR furniture item should be placed.
enum PlacementType {
  /// Must be placed on a horizontal (floor/table) surface.
  floor,

  /// Must be placed on a vertical (wall) surface.
  wall,

  /// Can be placed on any detected surface.
  any,
}

/// An AR-placeable furniture item backed by a bundled .glb model.
class ArFurnitureItem {
  const ArFurnitureItem({
    required this.name,
    required this.modelFile,
    required this.widthMeters,
    this.icon = Icons.chair,
    this.placement = PlacementType.floor,
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

  /// Which surface type this item should be placed on.
  final PlacementType placement;

  /// URI used with `NodeType.localGLTF2`. The plugin (`ArView.kt`) resolves
  /// these URIs through Flutter's `getLookupKeyForAsset`, which expects the
  /// FULL pubspec-relative asset key — the same string used with
  /// `rootBundle.load`, including the leading `assets/` segment. The files
  /// live in `assets/models/` (registered in pubspec.yaml under
  /// `flutter: assets:`), so the key — and therefore the URI — is
  /// `assets/models/<file>.glb`; at runtime it resolves to
  /// `flutter_assets/assets/models/<file>.glb` inside the packaged app.
  /// Do NOT drop the `assets/` prefix: `models/<file>.glb` is not a
  /// registered asset key and the plugin fails to load the model.
  /// Paths are case-sensitive at runtime.
  String get uri => 'assets/models/$modelFile';
}

/// Bundled 3D models for the ROOM SCANNER / SAVED-DESIGNS browsing catalog.
///
/// This library is a BROWSING feature only: the room planner lets users pick
/// a bundled model to place in a scanned room. It is NOT a model source for
/// marketplace products — a product's AR model is its Tripo AI model
/// rescaled to the seller's dimensions (see ModelGlbResolver), and no
/// category-based lookup exists for products anymore.
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

  /// Placeholder used when no matching 3D model exists for an item.
  static const ArFurnitureItem _fallback = ArFurnitureItem(
      name: 'Furniture',
      modelFile: 'folding_table.glb',
      widthMeters: 1.0,
      icon: Icons.chair,
      placement: PlacementType.floor);

  /// Maps the room-scanner catalog `iconName`s to 3D models.
  /// Entries marked (placeholder) have no exact model and reuse the closest
  /// available shape — the chip still shows the real item name.
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
    // Placeholders — no exact model bundled yet
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

  /// Returns the AR model for a room-scanner catalog `iconName`.
  static ArFurnitureItem forIconName(String? iconName) {
    if (iconName == null) return _fallback;
    return _byIconName[iconName.toLowerCase()] ?? _fallback;
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
}
