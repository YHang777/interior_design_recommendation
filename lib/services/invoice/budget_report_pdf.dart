import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils/formatters.dart';
import '../../features/customer/budget/data/budget_estimates.dart';

class BudgetReportPdf {
  const BudgetReportPdf._();

  static Future<Uint8List> bytes({
    required String room,
    required int budgetRm,
    required List<EstimateLine> lines,
    required DateTime generatedAt,
    required bool ecoFriendly,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => _body(
          room: room,
          budgetRm: budgetRm,
          lines: lines,
          generatedAt: generatedAt,
          ecoFriendly: ecoFriendly,
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Budget Report  ·  '
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: _muted(8),
          ),
        ),
      ),
    );
    return doc.save();
  }

  static Future<void> share({
    required String room,
    required int budgetRm,
    required List<EstimateLine> lines,
    required DateTime generatedAt,
    required bool ecoFriendly,
  }) async {
    await Printing.sharePdf(
      bytes: await bytes(
        room: room,
        budgetRm: budgetRm,
        lines: lines,
        generatedAt: generatedAt,
        ecoFriendly: ecoFriendly,
      ),
      filename: _filename(room, generatedAt),
    );
  }

  static Future<void> print({
    required String room,
    required int budgetRm,
    required List<EstimateLine> lines,
    required DateTime generatedAt,
    required bool ecoFriendly,
  }) async {
    await Printing.layoutPdf(
      name: _filename(room, generatedAt),
      onLayout: (format) => bytes(
        room: room,
        budgetRm: budgetRm,
        lines: lines,
        generatedAt: generatedAt,
        ecoFriendly: ecoFriendly,
      ),
    );
  }
}

const List<int> _lineFlex = [3, 1];

List<pw.Widget> _body({
  required String room,
  required int budgetRm,
  required List<EstimateLine> lines,
  required DateTime generatedAt,
  required bool ecoFriendly,
}) {
  final total = estimateTotal(lines);
  final remaining = budgetRm - total;
  return [
    _header(room, generatedAt),
    pw.SizedBox(height: 22),
    _sectionTitle('Budget Overview'),
    pw.SizedBox(height: 8),
    _overviewRow('Budget', Formatters.myr(budgetRm)),
    _overviewRow('Total estimate', Formatters.myr(total)),
    _overviewRow(
      remaining >= 0 ? 'Remaining' : 'Over budget by',
      Formatters.myr(remaining >= 0 ? remaining : remaining.abs()),
    ),
    pw.SizedBox(height: 20),
    _sectionTitle('Cost Breakdown'),
    pw.SizedBox(height: 8),
    _linesTable(lines),
    pw.SizedBox(height: 18),
    pw.Divider(height: 1, thickness: 0.6, color: PdfColors.grey400),
    pw.SizedBox(height: 8),
    _footnote(ecoFriendly: ecoFriendly),
  ];
}

pw.Widget _header(String room, DateTime generatedAt) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'BUDGET REPORT',
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '$room renovation',
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
          pw.Text(
            'Generated ${Formatters.shortDate(generatedAt)}',
            style: _muted(10),
          ),
        ],
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

pw.Widget _linesTable(List<EstimateLine> lines) {
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
          _label('Category'),
          _label('Price', align: pw.TextAlign.right),
        ]),
      ),
      for (final line in lines)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 7),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          child: _tableRow([
            pw.Text(line.label, style: _cell),
            pw.Text(
              line.hasData ? Formatters.myr(line.price!) : 'No price data yet',
              style: _cell,
              textAlign: pw.TextAlign.right,
            ),
          ]),
        ),
    ],
  );
}

pw.Widget _tableRow(List<pw.Widget> cells) {
  return pw.Row(
    children: [
      for (var i = 0; i < cells.length; i++)
        pw.Expanded(flex: _lineFlex[i], child: cells[i]),
    ],
  );
}

pw.Widget _footnote({required bool ecoFriendly}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Estimates are median prices of active marketplace listings'
        '${ecoFriendly ? ' (eco-friendly listings only)' : ''}.',
        style: _muted(9),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        "A line shows 'No price data yet' when the catalogue has no "
        'matching listing.',
        style: _muted(9),
      ),
    ],
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

final pw.TextStyle _cell =
    const pw.TextStyle(fontSize: 10, color: PdfColors.grey900);

pw.TextStyle _muted(double size) =>
    pw.TextStyle(fontSize: size, color: PdfColors.grey600);

String _filename(String room, DateTime generatedAt) {
  final slug = room
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final d = generatedAt;
  final stamp = '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  return 'budget-report-${slug.isEmpty ? 'room' : slug}-$stamp.pdf';
}
