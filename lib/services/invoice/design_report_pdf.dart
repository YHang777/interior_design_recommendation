import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils/formatters.dart';
import '../../features/customer/homeowner/data/design_report.dart';

class DesignReportPdf {
  const DesignReportPdf._();

  static Future<Uint8List> bytes(DesignReportData report) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => _body(report),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Design Report  ·  '
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: _muted(8),
          ),
        ),
      ),
    );
    return doc.save();
  }

  static Future<void> share(DesignReportData report) async {
    await Printing.sharePdf(
      bytes: await bytes(report),
      filename: _filename(report),
    );
  }

  static Future<void> print(DesignReportData report) async {
    await Printing.layoutPdf(
      name: _filename(report),
      onLayout: (format) => bytes(report),
    );
  }
}

const List<int> _itemFlex = [6, 2, 2];

final pw.TextStyle _cell =
    const pw.TextStyle(fontSize: 10, color: PdfColors.grey900);

List<pw.Widget> _body(DesignReportData report) => [
      _header(report),
      pw.SizedBox(height: 22),
      _sectionTitle('Design Overview'),
      pw.SizedBox(height: 8),
      _overview(report),
      pw.SizedBox(height: 20),
      _sectionTitle('Furniture & Items'),
      pw.SizedBox(height: 8),
      _itemsTable(report),
      pw.SizedBox(height: 20),
      _sectionTitle('Expenses Breakdown'),
      pw.SizedBox(height: 8),
      _expenses(report),
      pw.SizedBox(height: 18),
      pw.Divider(height: 1, thickness: 0.6, color: PdfColors.grey400),
      pw.SizedBox(height: 8),
      _footnote(),
    ];

pw.Widget _header(DesignReportData report) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'DESIGN REPORT',
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              report.design.name,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(report.design.roomTypeLabel, style: _muted(10)),
          pw.SizedBox(height: 3),
          pw.Text(
            'Generated ${Formatters.shortDate(report.generatedAt)}',
            style: _muted(10),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _overview(DesignReportData report) {
  return pw.Column(
    children: [
      _overviewRow('Room type', report.design.roomTypeLabel),
      _overviewRow(
        'Design style',
        report.derivedStyle ?? 'Not specified',
      ),
      _overviewRow(
        'Creation date',
        Formatters.shortDate(report.design.createdAt),
      ),
      _overviewRow(
        'Total expenses',
        report.expenses.hasData
            ? Formatters.myr(report.expenses.total!)
            : '-',
      ),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          report.expenses.hasData
              ? 'Service lines are percentage estimates of furniture cost.'
              : "No priced items yet - totals show as '-'.",
          style: _muted(8.5),
        ),
      ),
    ],
  );
}

pw.Widget _overviewRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(label, style: _muted(10))),
        pw.SizedBox(width: 16),
        pw.Text(
          value,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(fontSize: 10.5, color: PdfColors.grey900),
        ),
      ],
    ),
  );
}

pw.Widget _itemsTable(DesignReportData report) {
  if (report.items.isEmpty) {
    return pw.Text(
      'No furniture placed in this design yet.',
      style: _muted(10),
    );
  }
  return pw.Column(
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.8),
          ),
        ),
        child: _tableRow([
          _label('Item'),
          _label('Category'),
          _label('Price', align: pw.TextAlign.right),
        ]),
      ),
      for (final item in report.items)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 7),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          child: _tableRow([
            pw.Text(item.name, style: _cell),
            pw.Text(item.category, style: _cell),
            pw.Text(
              item.hasData ? Formatters.myr(item.estimatedPrice!) : 'No price data yet',
              style: _cell,
              textAlign: pw.TextAlign.right,
            ),
          ]),
        ),
      pw.SizedBox(height: 8),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Furniture subtotal  ·  '
          '${report.expenses.hasData ? Formatters.myr(report.expenses.furniture) : '-'}',
          style: pw.TextStyle(
            fontSize: 10.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey900,
          ),
        ),
      ),
    ],
  );
}

pw.Widget _tableRow(List<pw.Widget> cells) {
  return pw.Row(
    children: [
      for (var i = 0; i < cells.length; i++)
        pw.Expanded(flex: _itemFlex[i], child: cells[i]),
    ],
  );
}

pw.Widget _expenses(DesignReportData report) {
  final expenses = report.expenses;
  final money = expenses.hasData;
  return pw.Column(
    children: [
      _totalLine(
        'Furniture',
        money ? Formatters.myr(expenses.furniture) : '-',
      ),
      _totalLine(
        'Installation (est.)',
        money ? Formatters.myr(expenses.installation!) : '-',
      ),
      _totalLine(
        'Delivery (est.)',
        money ? Formatters.myr(expenses.delivery!) : '-',
      ),
      pw.SizedBox(height: 8),
      pw.Divider(height: 1, thickness: 0.8, color: PdfColors.grey500),
      pw.SizedBox(height: 8),
      _totalLine(
        'Total expenses',
        money ? Formatters.myr(expenses.total!) : '-',
        strong: true,
      ),
    ],
  );
}

pw.Widget _totalLine(String label, String value, {bool strong = false}) {
  final style = strong
      ? pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)
      : const pw.TextStyle(fontSize: 10.5);
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(label, style: style)),
        pw.SizedBox(width: 16),
        pw.Text(value, style: style, textAlign: pw.TextAlign.right),
      ],
    ),
  );
}

pw.Widget _footnote() {
  return pw.Text(
    'Prices are estimated from current marketplace listings (median). '
    'Installation and delivery are estimated percentages of furniture cost.',
    style: _muted(9),
  );
}

pw.Widget _sectionTitle(String text) {
  return pw.Text(
    text.toUpperCase(),
    style: pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.grey600,
      letterSpacing: 0.8,
    ),
  );
}

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

pw.TextStyle _muted(double size) =>
    pw.TextStyle(fontSize: size, color: PdfColors.grey600);

String _filename(DesignReportData report) {
  final slug = report.design.name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final d = report.generatedAt;
  final stamp = '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  return 'design-report-${slug.isEmpty ? 'design' : slug}-$stamp.pdf';
}
