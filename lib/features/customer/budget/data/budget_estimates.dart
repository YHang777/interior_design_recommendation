import '../../../../core/utils/formatters.dart';
import '../../../../models/product.dart';

class EstimateLine {
  const EstimateLine({
    required this.label,
    required this.price,
    required this.matches,
    this.material,
    this.supplier,
    this.productId,
  });

  final String label;

  final int? price;

  final int matches;

  final String? material;

  final String? supplier;

  final String? productId;

  bool get hasData => price != null;
}

class EstimateOption {
  const EstimateOption({
    required this.productId,
    required this.name,
    required this.supplier,
    required this.price,
    required this.isEcoFriendly,
    required this.inStock,
  });

  final String productId;

  final String name;

  final String? supplier;

  final int price;

  final bool isEcoFriendly;

  final bool inStock;
}

const budgetLineLabels = [
  'Wall Paint',
  'Flooring',
  'Furniture',
  'Lighting',
  'Accessories',
];

const List<List<String>> _budgetLineCategories = [
  ['Paint', 'Wall Covering'],
  ['Flooring'],
  ['Furniture'],
  ['Lighting'],
  ['Decor', 'Textiles'],
];

int? medianPrice(Iterable<int> prices) {
  final sorted = prices.toList()..sort();
  if (sorted.isEmpty) return null;
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return ((sorted[mid - 1] + sorted[mid]) / 2).round();
}

Iterable<Product> _lineProducts(
  List<Product> products,
  int lineIndex, {
  required bool ecoFriendly,
}) sync* {
  final wanted =
      _budgetLineCategories[lineIndex].map((c) => c.toLowerCase()).toSet();
  for (final p in products) {
    if (!p.isActive) continue;
    if (ecoFriendly && !p.isEcoFriendly) continue;
    if (wanted.contains(p.category.trim().toLowerCase())) yield p;
  }
}

String? _supplierName(Product p) {
  final name = p.supplier.name.trim();
  return name.isEmpty ? null : name;
}

List<EstimateLine> buildEstimateLines(
  List<Product> products, {
  required bool ecoFriendly,
}) {
  return [
    for (var i = 0; i < budgetLineLabels.length; i++)
      () {
        Product? cheapest;
        var matches = 0;
        for (final p in _lineProducts(products, i, ecoFriendly: ecoFriendly)) {
          matches++;
          if (cheapest == null || p.price < cheapest.price) cheapest = p;
        }
        if (cheapest == null) {
          return EstimateLine(
            label: budgetLineLabels[i],
            price: null,
            matches: 0,
          );
        }
        return EstimateLine(
          label: budgetLineLabels[i],
          price: cheapest.price,
          matches: matches,
          material: cheapest.name,
          supplier: _supplierName(cheapest),
          productId: cheapest.id,
        );
      }(),
  ];
}

List<EstimateOption> buildLineOptions(
  List<Product> products, {
  required String label,
  required bool ecoFriendly,
}) {
  final index = budgetLineLabels.indexOf(label);
  if (index < 0) return const [];
  final options = [
    for (final p in _lineProducts(products, index, ecoFriendly: ecoFriendly))
      EstimateOption(
        productId: p.id,
        name: p.name,
        supplier: _supplierName(p),
        price: p.price,
        isEcoFriendly: p.isEcoFriendly,
        inStock: !p.isOutOfStock,
      ),
  ];
  return options..sort((a, b) => a.price.compareTo(b.price));
}

int estimateTotal(List<EstimateLine> lines) =>
    lines.fold<int>(0, (sum, l) => sum + (l.price ?? 0));

String buildBudgetReport({
  required String room,
  required int budgetRm,
  required List<EstimateLine> lines,
  required DateTime generatedAt,
  required bool ecoFriendly,
}) {
  final total = estimateTotal(lines);
  final remaining = budgetRm - total;
  final buf = StringBuffer()
    ..writeln('Budget Planner Report — $room')
    ..writeln('Generated ${Formatters.shortDateTime(generatedAt)}')
    ..writeln()
    ..writeln('Budget: ${Formatters.myr(budgetRm)}')
    ..writeln();

  for (final l in lines) {
    buf.writeln(l.hasData
        ? '${l.label}: ${Formatters.myr(l.price!)}'
            '${l.supplier == null ? '' : ' · ${l.supplier}'}'
        : '${l.label}: — (no price data yet)');
  }

  buf
    ..writeln()
    ..writeln('Total estimate: ${Formatters.myr(total)}')
    ..writeln(remaining >= 0
        ? 'Remaining: ${Formatters.myr(remaining)}'
        : 'Over budget by ${Formatters.myr(remaining.abs())}')
    ..writeln()
    ..writeln('Estimates are the lowest prices across active marketplace '
        'listings'
        '${ecoFriendly ? ' (eco-friendly listings only)' : ''}.')
    ..writeln('A line shows "—" when the catalogue has no matching listing yet.');

  return buf.toString();
}
