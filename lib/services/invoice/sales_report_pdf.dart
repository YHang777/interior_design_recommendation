import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils/formatters.dart';

class SalesReportMonth {
  const SalesReportMonth({required this.month, required this.revenue});

  final DateTime month;
  final int revenue;
}

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

  final int totalSales;

  final int totalOrders;

  final double? averageRating;

  final double? conversionRate;

  final List<SalesReportMonth> monthly;
  final List<SalesReportProduct> topProducts;

  final int uniqueCustomers;
  final int newCustomers;
  final int? avgOrderValue;
  final double? retentionRate;
  final double? repeatPurchaseRate;
}

class SalesReportPdf {
  const SalesReportPdf._();

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

  static Future<void> share(SalesReportData data) async {
    await Printing.sharePdf(
      bytes: await bytes(data),
      filename: 'sales-report-${_fileDate(data.generatedAt)}.pdf',
    );
  }

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

String _percent(double? rate) => rate == null ? '-' : '${(rate * 100).round()}%';

String _rating(double? rating) => rating == null ? '-' : rating.toStringAsFixed(1);

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

pw.Widget _footerNote() {
  return pw.Text(
    'Conversion rate = collected ÷ all orders. Customer metrics derived '
    'from your order history. Cancelled orders excluded.',
    style: _muted(9),
  );
}
