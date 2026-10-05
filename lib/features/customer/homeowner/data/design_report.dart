import '../../../../models/product.dart';
import '../../../../models/room_design.dart';
import '../../budget/data/budget_estimates.dart';

/// Pure synthesis for the customer Design Report.
///
/// A saved design carries no prices of its own, so this module derives
/// honest estimates from the LIVE marketplace catalogue — the median price
/// of the listings that match each placed item — and never invents a number:
/// an item with no matching listing reports `estimatedPrice == null` and the
/// UI/PDF say "No price data yet" (the same honesty rule as `EstimateLine`).
///
/// No IO, no widgets — unit-testable headless.

/// Service-line rates, kept as top-level constants so they are trivially
/// tunable (marketing copy in the UI/PDF describes them as percentages).
const double kInstallationRate = 0.10;

const double kDeliveryRate = 0.05;

/// Placement name (lowercase) → the scanner's `_catalog` category. Mirrors
/// the taxonomy of the private `_catalog` in `room_scanner_screen.dart`
/// without refactoring that list.
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

/// Same taxonomy keyed by the catalog icon name — the fallback when a
/// placement's display name was renamed by detection.
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

/// Scanner catalog category → the marketplace display category buyers
/// browse under (same grouping `buildEstimateLines` prices against).
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

/// Marketplace display category for one placed item: name match first,
/// icon-name fallback second, `'Furniture'` when neither is recognised.
String displayCategoryFor(FurniturePlacement placement) {
  final catalog = _placementCatalog[placement.name.trim().toLowerCase()] ??
      _iconCatalog[placement.iconName.trim().toLowerCase()] ??
      'furniture';
  return _catalogToDisplay[catalog] ?? 'Furniture';
}

/// One placed item's derived estimate.
class DesignItemEstimate {
  const DesignItemEstimate({
    required this.name,
    required this.category,
    required this.estimatedPrice,
    required this.matches,
  });

  final String name;

  /// Marketplace display category ('Furniture' / 'Lighting' / 'Decor').
  final String category;

  /// Median price of the matching ACTIVE listings, or null when the
  /// catalogue has no matching listing yet (never an invented number).
  final int? estimatedPrice;

  /// How many listings the price was derived from (0 → price is null).
  final int matches;

  bool get hasData => estimatedPrice != null;
}

/// The report's cost block — every line is an estimate, footnoted as such.
class DesignExpenses {
  const DesignExpenses({
    required this.furniture,
    this.installation,
    this.delivery,
    this.total,
  });

  /// Sum of the non-null item prices (0 when nothing is priced).
  final int furniture;

  /// [furniture] × [kInstallationRate], rounded — null when no item
  /// has price data (nothing to take a percentage of).
  final int? installation;

  /// [furniture] × [kDeliveryRate], rounded — null when no item has
  /// price data.
  final int? delivery;

  /// furniture + installation + delivery — null when no item has price data.
  final int? total;

  /// Whether ANY placed item has a price (drives '—' vs numbers in UI/PDF).
  bool get hasData => total != null;
}

/// Everything the Design Report screen and PDF render for one design.
class DesignReportData {
  const DesignReportData({
    required this.design,
    required this.items,
    required this.expenses,
    required this.generatedAt,
    this.derivedStyle,
  });

  final RoomDesign design;

  /// One estimate per placed furniture item, in placement order.
  final List<DesignItemEstimate> items;

  final DesignExpenses expenses;

  final DateTime generatedAt;

  /// Majority `Product.designStyle` among the products matched to this
  /// design's furniture; null when nothing matched ("Not specified").
  final String? derivedStyle;
}

/// Builds the full report for [design] against the marketplace [products].
///
/// Only ACTIVE listings are considered (a paused listing is not a live
/// quote). Per item:
///  1. name match (case-insensitive containment either way) → median price;
///  2. else category match (same rule as `buildEstimateLines`) → median;
///  3. else `estimatedPrice == null`, `matches == 0`.
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

    // Deduped by id so one listing matched by several placements (or a
    // product appearing twice) cannot skew the derived style.
    final sink = byName.isNotEmpty ? nameMatched : categoryMatched;
    for (final p in matched) {
      sink[p.id] = p;
    }
  }

  // The style is derived from NAME matches when any exist; category matches
  // are the honest fallback for items the catalogue never names the same way.
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

/// ACTIVE listings whose name overlaps [placementName] either way
/// (case-insensitive substring containment, both directions).
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

/// ACTIVE listings in exactly [category] — same case-insensitive trimmed
/// equality `buildEstimateLines` uses.
List<Product> _categoryMatches(String category, List<Product> active) {
  final wanted = category.trim().toLowerCase();
  return [
    for (final p in active)
      if (p.category.trim().toLowerCase() == wanted) p,
  ];
}

/// Majority `designStyle` among [products]; ties break to the first style
/// alphabetically so the report is deterministic; no usable style → null.
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
