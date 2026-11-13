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
  RoomCatalogItem('Coffee Table', 'coffee_table', Icons.table_bar, 'tables', 120, 60,
      'assets/images/furniture_ph_modern_coffee_table_01.png', 39),
  RoomCatalogItem('Dining Table', 'dining_table', Icons.table_restaurant,
      'tables', 140, 100, 'assets/images/furniture_table_dining.png', 75),
  RoomCatalogItem(
      'Bed', 'bed', Icons.bed, 'bedroom', 200, 160, 'assets/images/furniture_bed_modern.png', 60),
  RoomCatalogItem('Cabinet', 'cabinet', Icons.inventory_2, 'storage', 114, 49,
      'assets/images/furniture_ph_drawer_cabinet.png', 188),
  RoomCatalogItem('Desk', 'desk', Icons.desk, 'office', 120, 60,
      'assets/images/furniture_desk_modern.png', 75),
  RoomCatalogItem('Floor Lamp', 'floor_lamp', Icons.lightbulb, 'lighting', 25,
      25, 'assets/images/furniture_lamp_floor.png', 160),
  RoomCatalogItem('Plant', 'plant', Icons.eco, 'decor', 70, 66,
      'assets/images/furniture_ph_potted_plant_02.png', 84),
  RoomCatalogItem('TV Stand', 'tv_stand', Icons.tv, 'media', 244, 52,
      'assets/images/furniture_ph_modern_wooden_cabinet.png', 68),
  RoomCatalogItem('Rug', 'rug', Icons.view_agenda, 'decor', 160, 120,
      'assets/images/furniture_rug_modern.png', 2),
  RoomCatalogItem('Bookshelf', 'bookshelf', Icons.menu_book, 'storage', 108, 37,
      'assets/images/furniture_ph_wooden_display_shelves_01.png', 156),
  // Models from Poly Haven and the Khronos glTF samples — see assets/models/CREDITS.md.
  RoomCatalogItem('Lounge Chair', 'lounge_chair', Icons.event_seat, 'seating', 101, 119,
      'assets/images/furniture_ph_mid_century_lounge_chair.png', 117),
  RoomCatalogItem('Accent Chair', 'accent_chair', Icons.chair_alt, 'seating', 82, 99,
      'assets/images/furniture_ph_modern_arm_chair_01.png', 102),
  RoomCatalogItem('Dining Chair', 'dining_chair', Icons.chair, 'seating', 43, 58,
      'assets/images/furniture_ph_dining_chair_02.png', 97),
  RoomCatalogItem('Ottoman', 'ottoman', Icons.crop_square, 'seating', 88, 62,
      'assets/images/furniture_ph_ottoman_01.png', 62),
  RoomCatalogItem('Chesterfield Sofa', 'chesterfield_sofa', Icons.weekend, 'seating', 181, 82,
      'assets/images/furniture_ph_sofa_02.png', 71),
  RoomCatalogItem('Bar Stool', 'bar_stool', Icons.chair_alt, 'seating', 48, 49,
      'assets/images/furniture_ph_bar_chair_round_01.png', 75),
  RoomCatalogItem('Side Table', 'side_table', Icons.table_bar, 'tables', 55, 45,
      'assets/images/furniture_ph_side_table_01.png', 55),
  RoomCatalogItem('Round Coffee Table', 'round_coffee_table', Icons.circle_outlined, 'tables', 130, 130,
      'assets/images/furniture_ph_coffee_table_round_01.png', 49),
  RoomCatalogItem('Chest of Drawers', 'chest_of_drawers', Icons.inventory, 'storage', 172, 101,
      'assets/images/furniture_ph_vintage_wooden_drawer_01.png', 109),
  RoomCatalogItem('Office Desk', 'office_desk', Icons.desk, 'office', 200, 95,
      'assets/images/furniture_ph_metal_office_desk.png', 79),
  RoomCatalogItem('Velvet Sofa', 'velvet_sofa', Icons.weekend, 'seating', 219, 102,
      'assets/images/furniture_kh_glam_velvet_sofa.png', 79),
  RoomCatalogItem('Velvet Chair', 'velvet_chair', Icons.chair, 'seating', 83, 57,
      'assets/images/furniture_kh_sheen_chair.png', 69),
  RoomCatalogItem('Round Dining Table', 'round_dining_table', Icons.table_restaurant, 'tables', 140, 140,
      'assets/images/furniture_ph_round_wooden_table_01.png', 75),
  RoomCatalogItem('Industrial Shelf', 'industrial_shelf', Icons.shelves, 'storage', 110, 50,
      'assets/images/furniture_ph_steel_frame_shelves_01.png', 214),
  RoomCatalogItem('Plant Stand', 'plant_stand', Icons.local_florist, 'decor', 38, 38,
      'assets/images/furniture_ph_side_table_tall_01.png', 76),
  RoomCatalogItem('Succulent Pot', 'succulent', Icons.spa, 'decor', 17, 18,
      'assets/images/furniture_ph_potted_plant_04.png', 27),
  RoomCatalogItem('Nightstand', 'nightstand', Icons.table_bar, 'bedroom', 57, 42,
      'assets/images/furniture_ph_classicnightstand_01.png', 70),
  RoomCatalogItem('Stove', 'stove', Icons.kitchen, 'kitchen', 50, 65,
      'assets/images/furniture_ph_electric_stove.png', 86),
  RoomCatalogItem('Storage Basket', 'basket', Icons.shopping_basket, 'decor', 38, 27,
      'assets/images/furniture_ph_wicker_basket_02.png', 22),
  RoomCatalogItem('Tall Plant', 'small_plant', Icons.local_florist, 'decor', 59, 63,
      'assets/images/furniture_ph_potted_plant_01.png', 135),
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
