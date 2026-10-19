import '../../../../models/product.dart';
import '../../../../models/room_design.dart';
import '../../budget/data/budget_estimates.dart';

const double kInstallationRate = 0.10;

const double kDeliveryRate = 0.05;

const Map<String, String> _placementCatalog = {
  'sofa': 'seating',
  'armchair': 'seating',
  'coffee table': 'tables',
  'dining table': 'tables',
  'bed': 'bedroom',
  'cabinet': 'storage',
  'desk': 'office',
  'floor lamp': 'lighting',
  'plant': 'decor',
  'tv stand': 'media',
  'rug': 'decor',
  'bookshelf': 'storage',
};

const Map<String, String> _iconCatalog = {
  'sofa': 'seating',
  'armchair': 'seating',
  'coffee_table': 'tables',
  'dining_table': 'tables',
  'bed': 'bedroom',
  'cabinet': 'storage',
  'desk': 'office',
  'floor_lamp': 'lighting',
  'plant': 'decor',
  'tv_stand': 'media',
  'rug': 'decor',
  'bookshelf': 'storage',
};

const Map<String, String> _catalogToDisplay = {
  'seating': 'Furniture',
  'tables': 'Furniture',
  'bedroom': 'Furniture',
  'storage': 'Furniture',
  'office': 'Furniture',
  'media': 'Furniture',
  'lighting': 'Lighting',
  'decor': 'Decor',
};

String displayCategoryFor(FurniturePlacement placement) {
  final catalog = _placementCatalog[placement.name.trim().toLowerCase()] ??
      _iconCatalog[placement.iconName.trim().toLowerCase()] ??
      'furniture';
  return _catalogToDisplay[catalog] ?? 'Furniture';
}

class DesignItemEstimate {
  const DesignItemEstimate({
    required this.name,
    required this.category,
    required this.estimatedPrice,
    required this.matches,
  });

  final String name;

  final String category;

  final int? estimatedPrice;

  final int matches;

  bool get hasData => estimatedPrice != null;
}

class DesignExpenses {
  const DesignExpenses({
    required this.furniture,
    this.installation,
    this.delivery,
    this.total,
  });

  final int furniture;

  final int? installation;

  final int? delivery;

  final int? total;

  bool get hasData => total != null;
}

class DesignReportData {
  const DesignReportData({
    required this.design,
    required this.items,
    required this.expenses,
    required this.generatedAt,
    this.derivedStyle,
  });

  final RoomDesign design;

  final List<DesignItemEstimate> items;

  final DesignExpenses expenses;

  final DateTime generatedAt;

  final String? derivedStyle;
}

DesignReportData buildDesignReport(
  RoomDesign design,
  List<Product> products,
) {
  final active = products.where((p) => p.isActive).toList();
  final items = <DesignItemEstimate>[];
  final nameMatched = <String, Product>{};
  final categoryMatched = <String, Product>{};

  for (final placement in design.furniture) {
    final category = displayCategoryFor(placement);
    final byName = _nameMatches(placement.name, active);
    final matched =
        byName.isNotEmpty ? byName : _categoryMatches(category, active);
    final prices = [for (final p in matched) p.price];

    final name = placement.name.trim();
    items.add(DesignItemEstimate(
      name: name.isEmpty ? 'Item' : name,
      category: category,
      estimatedPrice: medianPrice(prices),
      matches: matched.length,
    ));

    final sink = byName.isNotEmpty ? nameMatched : categoryMatched;
    for (final p in matched) {
      sink[p.id] = p;
    }
  }

  final styleSources =
      nameMatched.isNotEmpty ? nameMatched.values : categoryMatched.values;

  final furniture = items.fold<int>(0, (sum, i) => sum + (i.estimatedPrice ?? 0));
  final anyPriced = items.any((i) => i.estimatedPrice != null);

  final installation = anyPriced ? (furniture * kInstallationRate).round() : null;
  final delivery = anyPriced ? (furniture * kDeliveryRate).round() : null;

  return DesignReportData(
    design: design,
    items: items,
    expenses: DesignExpenses(
      furniture: furniture,
      installation: installation,
      delivery: delivery,
      total: anyPriced ? furniture + installation! + delivery! : null,
    ),
    generatedAt: DateTime.now(),
    derivedStyle: _majorityStyle(styleSources),
  );
}

List<Product> _nameMatches(String placementName, List<Product> active) {
  final needle = placementName.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  return [
    for (final p in active)
      if (_overlaps(needle, p.name.trim().toLowerCase())) p,
  ];
}

bool _overlaps(String a, String b) =>
    b.isNotEmpty && (a.contains(b) || b.contains(a));

List<Product> _categoryMatches(String category, List<Product> active) {
  final wanted = category.trim().toLowerCase();
  return [
    for (final p in active)
      if (p.category.trim().toLowerCase() == wanted) p,
  ];
}

String? _majorityStyle(Iterable<Product> products) {
  final counts = <String, int>{};
  for (final p in products) {
    final style = p.designStyle.trim();
    if (style.isEmpty) continue;
    counts[style] = (counts[style] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;

  final sorted = counts.keys.toList()..sort();
  var winner = sorted.first;
  for (final style in sorted) {
    if ((counts[style] ?? 0) > (counts[winner] ?? 0)) winner = style;
  }
  return winner;
}
