import 'package:flutter/material.dart' show IconData, Icons;

// Shared furniture catalog: the planner's picker and the walkthrough's
// picker must offer the same pieces with the same sizes. heightCm is the
// vertical extent the walkthrough's standing view extrudes boxes to.
class RoomCatalogItem {
  const RoomCatalogItem(this.name, this.iconName, this.icon, this.category,
      this.defaultWidth, this.defaultHeight, this.imageAsset,
      [this.heightCm = 80]);

  final String name;
  final String iconName;
  final IconData icon;
  final String category;
  final double defaultWidth;
  final double defaultHeight;
  final String? imageAsset;
  final double heightCm;
}

const roomCatalog = [
  RoomCatalogItem('Sofa', 'sofa', Icons.weekend, 'seating', 180, 90,
      'assets/images/furniture_sofa_modern.png', 80),
  RoomCatalogItem('Armchair', 'armchair', Icons.chair, 'seating', 70, 70,
      'assets/images/furniture_chair_modern.png', 85),
  RoomCatalogItem('Coffee Table', 'coffee_table', Icons.table_bar, 'tables',
      100, 50, 'assets/images/furniture_table_coffee.png', 45),
  RoomCatalogItem('Dining Table', 'dining_table', Icons.table_restaurant,
      'tables', 140, 100, 'assets/images/furniture_table_dining.png', 75),
  RoomCatalogItem(
      'Bed', 'bed', Icons.bed, 'bedroom', 200, 160, 'assets/images/furniture_bed_modern.png', 60),
  RoomCatalogItem('Cabinet', 'cabinet', Icons.inventory_2, 'storage', 90, 50,
      'assets/images/furniture_cabinet_modern.png', 180),
  RoomCatalogItem('Desk', 'desk', Icons.desk, 'office', 120, 60,
      'assets/images/furniture_desk_modern.png', 75),
  RoomCatalogItem('Floor Lamp', 'floor_lamp', Icons.lightbulb, 'lighting', 25,
      25, 'assets/images/furniture_lamp_floor.png', 160),
  RoomCatalogItem(
      'Plant', 'plant', Icons.eco, 'decor', 30, 30, 'assets/images/plant.jpg', 120),
  RoomCatalogItem('TV Stand', 'tv_stand', Icons.tv, 'media', 140, 45, null, 50),
  RoomCatalogItem('Rug', 'rug', Icons.view_agenda, 'decor', 160, 120,
      'assets/images/furniture_rug_modern.png', 2),
  RoomCatalogItem('Bookshelf', 'bookshelf', Icons.menu_book, 'storage', 90, 30,
      null, 200),
];

IconData iconForFurniture(String iconName) {
  for (final c in roomCatalog) {
    if (c.iconName == iconName) return c.icon;
  }
  return Icons.folder;
}

double heightCmForFurniture(String iconName) {
  for (final c in roomCatalog) {
    if (c.iconName == iconName) return c.heightCm;
  }
  return 80;
}
