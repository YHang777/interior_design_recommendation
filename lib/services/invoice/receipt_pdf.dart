import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils/formatters.dart';
import '../../models/order.dart';

class ReceiptPdf {
  const ReceiptPdf._();

  static Future<Uint8List> bytes(Order order) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => _body(order),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${order.orderNumber}  ·  '
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: _muted(8),
          ),
        ),
      ),
    );
    return doc.save();
  }

  static Future<void> share(Order order) async {
    await Printing.sharePdf(
      bytes: await bytes(order),
      filename: 'Receipt-${order.orderNumber}.pdf',
    );
  }

  static Future<void> print(Order order) async {
    await Printing.layoutPdf(
      name: 'Receipt ${order.orderNumber}',
      onLayout: (format) => bytes(order),
    );
  }
}

const List<int> _itemFlex = [6, 1, 2, 2];

final pw.TextStyle _cell =
    const pw.TextStyle(fontSize: 10, color: PdfColors.grey900);

List<pw.Widget> _body(Order order) => [
      _header(order),
      pw.SizedBox(height: 24),
      _paidStrip(order),
      pw.SizedBox(height: 18),
      _parties(order),
      pw.SizedBox(height: 22),
      _itemsTable(order),
      pw.SizedBox(height: 18),
      _totals(order),
      pw.SizedBox(height: 22),
      pw.Divider(height: 1, thickness: 0.6, color: PdfColors.grey400),
      pw.SizedBox(height: 8),
      _footerNote(order),
    ];

pw.Widget _header(Order order) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Text(
          'PAYMENT RECEIPT',
          style: pw.TextStyle(
            fontSize: 26,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            order.orderNumber,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            order.paidAt == null
                ? ''
                : 'Paid ${Formatters.shortDate(order.paidAt!)}',
            style: _muted(10),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _paidStrip(Order order) {
  final parts = <String>[
    'Amount paid: ${Formatters.myr(order.total)}',
    if (order.paymentMethodLabel.isNotEmpty) order.paymentMethodLabel,
    if (order.paymentIntentId.isNotEmpty) 'Ref ${order.paymentIntentId}',
  ];
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: pw.BoxDecoration(
      color: PdfColors.green50,
      borderRadius: pw.BorderRadius.circular(4),
      border: pw.Border.all(color: PdfColors.green400, width: 0.8),
    ),
    child: pw.Text(
      'PAID  ·  ${parts.join('  ·  ')}',
      style: pw.TextStyle(
        fontSize: 10.5,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.green800,
      ),
    ),
  );
}

pw.Widget _parties(Order order) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _party('RECEIVED BY', 'Intellar Marketplace', [
          'Payment collected on behalf of the suppliers below',
        ]),
      ),
      pw.SizedBox(width: 24),
      pw.Expanded(
        child: _party('BILLED TO', order.customerName, [
          order.customerPhone,
          order.customerEmail,
        ]),
      ),
    ],
  );
}

pw.Widget _party(String title, String name, List<String> details) {
  final lines = <pw.Widget>[];
  for (final raw in details) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    if (lines.isNotEmpty) lines.add(pw.SizedBox(height: 3));
    lines.add(pw.Text(value, style: _cell));
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _label(title),
      pw.SizedBox(height: 6),
      pw.Text(
        name.trim(),
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
      ...lines,
    ],
  );
}

pw.Widget _itemsTable(Order order) {
  if (order.items.isEmpty) {
    return pw.Text('No items on this receipt.', style: _muted(10));
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
          _label('Qty', align: pw.TextAlign.right),
          _label('Unit price', align: pw.TextAlign.right),
          _label('Amount', align: pw.TextAlign.right),
        ]),
      ),
      for (final item in order.items)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 7),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          child: _tableRow([
            pw.Text(item.name, style: _cell),
            pw.Text('${item.quantity}',
                style: _cell, textAlign: pw.TextAlign.right),
            pw.Text(Formatters.myr(item.unitPrice),
                style: _cell, textAlign: pw.TextAlign.right),
            pw.Text(Formatters.myr(item.lineTotal),
                style: _cell, textAlign: pw.TextAlign.right),
          ]),
        ),
      pw.SizedBox(height: 8),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${order.items.length} line items · '
          '${order.items.fold<int>(0, (sum, i) => sum + i.quantity)} units',
          style: _muted(9),
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

pw.Widget _totals(Order order) {
  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.SizedBox(
      width: 270,
      child: pw.Column(
        children: [
          _totalLine('Subtotal', Formatters.myr(order.subtotal)),
          if (order.discount > 0)
            _totalLine('Discount', '-${Formatters.myr(order.discount)}'),
          _totalLine('Tax', Formatters.myr(order.tax)),
          pw.SizedBox(height: 8),
          pw.Divider(height: 1, thickness: 0.8, color: PdfColors.grey500),
          pw.SizedBox(height: 8),
          _totalLine('Total paid', Formatters.myr(order.total), strong: true),
        ],
      ),
    ),
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

pw.Widget _footerNote(Order order) {
  return pw.Text(
    'Collect your order from each supplier\'s store - the suppliers will '
    'contact you to arrange pickup. Keep this receipt for your records.',
    style: _muted(9),
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
