import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_estimates.dart';
import 'package:interior_design_recommendation/services/invoice/budget_report_pdf.dart';

List<EstimateLine> _pricedLines() => const [
      EstimateLine(label: 'Wall Paint', price: 90, matches: 4),
      EstimateLine(label: 'Flooring', price: 1200, matches: 6),
      EstimateLine(label: 'Furniture', price: 1050, matches: 12),
      EstimateLine(label: 'Lighting', price: 150, matches: 3),
      EstimateLine(label: 'Accessories', price: 50, matches: 7),
    ];

List<EstimateLine> _unpricedLines() => const [
      EstimateLine(label: 'Wall Paint', price: null, matches: 0),
      EstimateLine(label: 'Flooring', price: null, matches: 0),
    ];

void expectValidPdf(List<int> bytes, {int minBytes = 500}) {
  expect(bytes.length, greaterThan(minBytes),
      reason: 'PDF should be a real document, not an empty stub');
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
}

void main() {
  group('BudgetReportPdf.bytes', () {
    test('renders a valid PDF for a fully priced budget', () async {
      final bytes = await BudgetReportPdf.bytes(
        room: 'Kitchen',
        budgetRm: 5000,
        lines: _pricedLines(),
        generatedAt: DateTime(2026, 10, 5),
        ecoFriendly: false,
      );

      expectValidPdf(bytes);
    });

    test('renders when no line has price data without crashing',
        () async {
      final bytes = await BudgetReportPdf.bytes(
        room: 'Living Room',
        budgetRm: 0,
        lines: _unpricedLines(),
        generatedAt: DateTime(2026, 10, 5),
        ecoFriendly: true,
      );

      expectValidPdf(bytes);
    });

    test('paginates a long line list without crashing', () async {
      final lines = List.generate(
        60,
        (i) => EstimateLine(label: 'Line ${i + 1}', price: (i + 1) * 10,
            matches: 1),
      );
      final bytes = await BudgetReportPdf.bytes(
        room: 'Kitchen',
        budgetRm: 100000,
        lines: lines,
        generatedAt: DateTime(2026, 10, 5),
        ecoFriendly: false,
      );

      expectValidPdf(bytes);
    });
  });
}
