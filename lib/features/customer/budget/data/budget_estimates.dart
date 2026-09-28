import '../../../../core/utils/formatters.dart';
import '../../../../models/product.dart';

/// Pure estimation logic for the budget planner: line-item estimates
/// derived from the LIVE marketplace catalogue, plus the text report the
/// planner copies to the clipboard.
///
/// No hardcoded prices anywhere — a category with no matching listings
/// yields `price == null` and is rendered as "— / no price data yet".

/// One row of the planner's cost breakdown.
class EstimateLine {
  const EstimateLine({
    required this.label,
    required this.price,
    required this.matches,
  });

  /// Display label, e.g. "Wall Paint".
  final String label;

  /// Median price of the matching listings, or null when there is no price
  /// data yet (never an invented number).
  final int? price;

  /// How many listings the price was derived from (0 → [price] is null).
  final int matches;

  bool get hasData => price != null;
}

/// The five budget lines, in display order.
const budgetLineLabels = [
  'Wall Paint',
  'Flooring',
  'Furniture',
  'Lighting',
  'Accessories',
];

/// Marketplace product categories that feed each budget line.
const List<List<String>> _budgetLineCategories = [
  ['Paint', 'Wall Covering'],
  ['Flooring'],
  ['Furniture'],
  ['Lighting'],
  ['Decor', 'Textiles'],
];

/// Median of [prices]: the middle value, or the mean of the two middle
/// values for an even count. Robust to a single outlier listing, which is
/// why it beats both "cheapest" and "average" for a rough estimate.
int? medianPrice(Iterable<int> prices) {
  final sorted = prices.toList()..sort();
  if (sorted.isEmpty) return null;
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return ((sorted[mid - 1] + sorted[mid]) / 2).round();
}

/// Builds one [EstimateLine] per budget line from [products].
///
/// - Only ACTIVE listings are priced (a paused listing is not a live quote).
/// - When [ecoFriendly] is on, only eco-friendly listings are considered —
///   a category with no eco listing honestly reports no price data.
/// - Category matching is case-insensitive.
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

/// Total of the lines that have price data (null-priced lines contribute
/// nothing — the summary is explicit that it only covers known data).
int estimateTotal(List<EstimateLine> lines) =>
    lines.fold<int>(0, (sum, l) => sum + (l.price ?? 0));

/// Plain-text report for the planner's "Copy Report" button — a real,
/// shareable summary of what the screen shows, not a mocked PDF.
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
