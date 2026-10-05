import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils/formatters.dart';

/// One calendar month's revenue in the report's monthly series.
class SalesReportMonth {
  const SalesReportMonth({required this.month, required this.revenue});

  /// First day of the calendar month.
  final DateTime month;
  final int revenue;
}

/// One row of the top-products table.
class SalesReportProduct {
  const SalesReportProduct({
    required this.name,
    required this.units,
    required this.revenue,
  });

  final String name;
  final int units;
  final int revenue;
}

/// Everything the sales report PDF needs — a small self-contained snapshot
/// built by the screen, so [SalesReportPdf.bytes] stays pure (no Riverpod,
/// no IO) and unit-testable headless.
///
/// Money is whole-ringgit RM; rates are 0–1 doubles (`null` prints as '—').
class SalesReportData {
  const SalesReportData({
    required this.sellerName,
    required this.generatedAt,
    required this.totalSales,
    required this.totalOrders,
    required this.monthly,
    required this.topProducts,
    required this.uniqueCustomers,
    required this.newCustomers,
    this.averageRating,
    this.conversionRate,
    this.avgOrderValue,
    this.retentionRate,
    this.repeatPurchaseRate,
  });

  final String sellerName;
  final DateTime generatedAt;

  /// Items + shipping; cancelled excluded.
  final int totalSales;

  /// Sold orders (cancelled excluded).
  final int totalOrders;

  /// ratingCount-weighted across listings — null when unrated.
  final double? averageRating;

  /// Delivered ÷ all orders involving the supplier — null when none.
  final double? conversionRate;

  final List<SalesReportMonth> monthly;
  final List<SalesReportProduct> topProducts;

  final int uniqueCustomers;
  final int newCustomers;
  final int? avgOrderValue;
  final double? retentionRate;
  final double? repeatPurchaseRate;
}

/// Renders a supplier sales report as a PDF and hands it to the OS.
///
/// [bytes] is pure document generation; [share] and [print] wrap the
/// `printing` plugin (same triad as [InvoicePdf]).
class SalesReportPdf {
  const SalesReportPdf._();

  /// Renders [data] as PDF bytes. Pure — no IO, no plugins.
  static Future<Uint8List> bytes(SalesReportData data) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => _body(data),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Sales Report  ·  Page ${context.pageNumber} of ${context.pagesCount}',
            style: _muted(8),
          ),
        ),
      ),
    );
    return doc.save();
  }

  /// Opens the system share sheet as `sales-report-<yyyy-mm-dd>.pdf`.
  static Future<void> share(SalesReportData data) async {
    await Printing.sharePdf(
      bytes: await bytes(data),
      filename: 'sales-report-${_fileDate(data.generatedAt)}.pdf',
    );
  }

  /// Opens the OS print dialog for [data].
  static Future<void> print(SalesReportData data) async {
    await Printing.layoutPdf(
      name: 'Sales Report',
      onLayout: (format) => bytes(data),
    );
  }

  static String _fileDate(DateTime at) {
    final m = at.month.toString().padLeft(2, '0');
    final d = at.day.toString().padLeft(2, '0');
    return '${at.year}-$m-$d';
  }
}

// ── Formatting helpers ───────────────────────────────────────────────────────

/// 0–1 rate as a whole-percent string; null prints a dash so an
/// unmeasurable figure is never shown as 0%. Plain '-' rather than '—':
/// the PDF's built-in Helvetica cannot draw U+2014 (it drops the glyph).
String _percent(double? rate) => rate == null ? '-' : '${(rate * 100).round()}%';

String _rating(double? rating) => rating == null ? '-' : rating.toStringAsFixed(1);

// Column flexes per table: labels/products take the room, numbers stay wide
// enough for "RM 12,345" without wrapping.
const List<int> _flex2 = [3, 1];
const List<int> _flex3 = [4, 1, 2];

final pw.TextStyle _cell =
    const pw.TextStyle(fontSize: 10, color: PdfColors.grey900);

pw.TextStyle _muted(double size) =>
    pw.TextStyle(fontSize: size, color: PdfColors.grey600);

pw.Widget _label(String text, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Text(
    text.toUpperCase(),
    textAlign: align,
    style: pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.grey600,
      letterSpacing: 0.8,
    ),
  );
}

pw.Widget _headerRow(List<String> cells, List<int> flex) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.8),
      ),
    ),
    child: pw.Row(
      children: [
        for (var i = 0; i < cells.length; i++)
          pw.Expanded(
            flex: flex[i],
            child: _label(cells[i],
                align: i == 0 ? pw.TextAlign.left : pw.TextAlign.right),
          ),
      ],
    ),
  );
}

pw.Widget _dataRow(List<String> cells, List<int> flex) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 7),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
    ),
    child: pw.Row(
      children: [
        for (var i = 0; i < cells.length; i++)
          pw.Expanded(
            flex: flex[i],
            child: pw.Text(
              cells[i],
              style: _cell,
              textAlign: i == 0 ? pw.TextAlign.left : pw.TextAlign.right,
            ),
          ),
      ],
    ),
  );
}

pw.Widget _sectionTitle(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
    );

// ── Body ─────────────────────────────────────────────────────────────────────

List<pw.Widget> _body(SalesReportData data) => [
      _header(data),
      pw.SizedBox(height: 22),
      _kpiTable(data),
      pw.SizedBox(height: 20),
      _monthlyTable(data),
      pw.SizedBox(height: 20),
      _topProductsTable(data),
      pw.SizedBox(height: 20),
      _insightsTable(data),
      pw.SizedBox(height: 22),
      pw.Divider(height: 1, thickness: 0.6, color: PdfColors.grey400),
      pw.SizedBox(height: 8),
      _footerNote(),
    ];

pw.Widget _header(SalesReportData data) {
  final seller = data.sellerName.trim();
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'SALES REPORT',
              style: pw.TextStyle(
                fontSize: 30,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            if (seller.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(seller, style: pw.TextStyle(fontSize: 13)),
            ],
          ],
        ),
      ),
      pw.Text(
        'Generated ${Formatters.shortDate(data.generatedAt)}',
        style: _muted(10),
      ),
    ],
  );
}

pw.Widget _kpiTable(SalesReportData data) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle('Key Performance Metrics'),
      _headerRow(['Metric', 'Value'], _flex2),
      _dataRow(['Total sales', Formatters.myr(data.totalSales)], _flex2),
      _dataRow(['Total orders', '${data.totalOrders}'], _flex2),
      _dataRow(['Average rating', _rating(data.averageRating)], _flex2),
      _dataRow(['Conversion rate', _percent(data.conversionRate)], _flex2),
    ],
  );
}

pw.Widget _monthlyTable(SalesReportData data) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle('Monthly Sales Performance'),
      if (data.monthly.isEmpty)
        pw.Text('No monthly data.', style: _muted(10))
      else ...[
        _headerRow(['Month', 'Revenue'], _flex2),
        for (final point in data.monthly)
          _dataRow([
            '${Formatters.monthShort(point.month.month)} ${point.month.year}',
            Formatters.myr(point.revenue),
          ], _flex2),
      ],
    ],
  );
}

pw.Widget _topProductsTable(SalesReportData data) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle('Top-Performing Products'),
      if (data.topProducts.isEmpty)
        pw.Text('No sales yet - orders will appear here.', style: _muted(10))
      else ...[
        _headerRow(['Product', 'Units', 'Revenue'], _flex3),
        for (final product in data.topProducts)
          _dataRow([
            product.name,
            '${product.units}',
            Formatters.myr(product.revenue),
          ], _flex3),
      ],
    ],
  );
}

pw.Widget _insightsTable(SalesReportData data) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle('Customer Insights'),
      _headerRow(['Metric', 'Value'], _flex2),
      _dataRow([
        'Avg order value',
        data.avgOrderValue == null ? '-' : Formatters.myr(data.avgOrderValue!),
      ], _flex2),
      _dataRow(['Retention rate', _percent(data.retentionRate)], _flex2),
      _dataRow(['New customers (6 mo)', '${data.newCustomers}'], _flex2),
      _dataRow(
          ['Repeat purchase rate', _percent(data.repeatPurchaseRate)], _flex2),
      _dataRow(['Unique customers', '${data.uniqueCustomers}'], _flex2),
    ],
  );
}

/// Definitions printed with every report so the numbers can't be
/// misread as an ad/click funnel or as including refunds.
pw.Widget _footerNote() {
  return pw.Text(
    'Conversion rate = delivered ÷ all orders. Customer metrics derived '
    'from your order history. Cancelled orders excluded.',
    style: _muted(9),
  );
}
