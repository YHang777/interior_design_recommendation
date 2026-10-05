// Tests for the sales report PDF renderer — the document a supplier shares
// or prints from the Sales Report screen.
//
// `SalesReportPdf.bytes` is pure (no IO, no plugins), so the document build
// can be exercised headless. The share/print actions wrap the `printing`
// plugin and are not covered here.

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/services/invoice/sales_report_pdf.dart';

SalesReportData _data({
  int totalSales = 4820,
  int totalOrders = 12,
  double? averageRating = 4.6,
  double? conversionRate = 0.75,
  int? avgOrderValue = 401,
  double? retentionRate = 0.5,
  double? repeatPurchaseRate = 0.66,
  List<SalesReportMonth>? monthly,
  List<SalesReportProduct>? topProducts,
  int uniqueCustomers = 8,
  int newCustomers = 3,
}) {
  return SalesReportData(
    sellerName: 'Studio Kayu',
    generatedAt: DateTime(2026, 10, 5, 9, 30),
    totalSales: totalSales,
    totalOrders: totalOrders,
    averageRating: averageRating,
    conversionRate: conversionRate,
    monthly: monthly ??
        [
          for (var i = 5; i >= 0; i--)
            SalesReportMonth(month: DateTime(2026, 10 - i, 1), revenue: i * 320),
        ],
    topProducts: topProducts ??
        const [
          SalesReportProduct(name: 'Nordic Sofa', units: 7, revenue: 4900),
          SalesReportProduct(name: 'Arc Floor Lamp', units: 3, revenue: 450),
        ],
    uniqueCustomers: uniqueCustomers,
    newCustomers: newCustomers,
    avgOrderValue: avgOrderValue,
    retentionRate: retentionRate,
    repeatPurchaseRate: repeatPurchaseRate,
  );
}

/// PDF files start with the magic `%PDF-` and are not empty stubs.
void expectValidPdf(List<int> bytes, {int minBytes = 500}) {
  expect(bytes.length, greaterThan(minBytes),
      reason: 'PDF should be a real document, not an empty stub');
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
}

void main() {
  group('SalesReportPdf.bytes', () {
    test('renders a valid PDF for a full report', () async {
      final bytes = await SalesReportPdf.bytes(_data());

      expectValidPdf(bytes);
    });

    test('renders with empty monthly series and no top products', () async {
      final bytes = await SalesReportPdf.bytes(_data(
        totalSales: 0,
        totalOrders: 0,
        averageRating: null,
        conversionRate: null,
        avgOrderValue: null,
        retentionRate: null,
        repeatPurchaseRate: null,
        monthly: const [],
        topProducts: const [],
        uniqueCustomers: 0,
        newCustomers: 0,
      ));

      expectValidPdf(bytes);
    });

    test('renders when every optional metric is null', () async {
      final bytes = await SalesReportPdf.bytes(_data(
        averageRating: null,
        conversionRate: null,
        avgOrderValue: null,
        retentionRate: null,
        repeatPurchaseRate: null,
      ));

      expectValidPdf(bytes);
    });

    test('renders a long product list without crashing', () async {
      final bytes = await SalesReportPdf.bytes(_data(
        topProducts: [
          for (var i = 0; i < 40; i++)
            SalesReportProduct(
                name: 'Product ${i + 1} with a fairly long listing name',
                units: 40 - i,
                revenue: (40 - i) * 125),
        ],
      ));

      expectValidPdf(bytes);
    });
  });
}
