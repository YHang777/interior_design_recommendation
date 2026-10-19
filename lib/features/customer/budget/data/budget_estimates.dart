import '../../../../core/utils/formatters.dart';
import '../../../../models/product.dart';

class EstimateLine {
  const EstimateLine({
    required this.label,
    required this.price,
    required this.matches,
  });

  final String label;

  final int? price;

  final int matches;

  bool get hasData => price != null;
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

List<EstimateLine> buildEstimateLines(
  List<Product> products, {
  required bool ecoFriendly,
}) {
  final usable = products
      .where((p) => p.isActive && (!ecoFriendly || p.isEcoFriendly));

  return [
    for (var i = 0; i < budgetLineLabels.length; i++)
      () {
        final wanted =
            _budgetLineCategories[i].map((c) => c.toLowerCase()).toSet();
        final prices = [
          for (final p in usable)
            if (wanted.contains(p.category.trim().toLowerCase())) p.price,
        ];
        return EstimateLine(
          label: budgetLineLabels[i],
          price: medianPrice(prices),
          matches: prices.length,
        );
      }(),
  ];
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
        : '${l.label}: — (no price data yet)');
  }

  buf
    ..writeln()
    ..writeln('Total estimate: ${Formatters.myr(total)}')
    ..writeln(remaining >= 0
        ? 'Remaining: ${Formatters.myr(remaining)}'
        : 'Over budget by ${Formatters.myr(remaining.abs())}')
    ..writeln()
    ..writeln('Estimates are median prices of active marketplace listings'
        '${ecoFriendly ? ' (eco-friendly listings only)' : ''}.')
    ..writeln('A line shows "—" when the catalogue has no matching listing yet.');

  return buf.toString();
}
