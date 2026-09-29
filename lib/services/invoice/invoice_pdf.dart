import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils/formatters.dart';
import '../../models/order.dart';

/// Renders a supplier invoice as a PDF and hands it to the OS.
///
/// [bytes] is pure document generation (no IO, no plugins) so it can be
/// unit-tested headless; [share] and [print] wrap the `printing` plugin.
class InvoicePdf {
  const InvoicePdf._();

  /// Renders [invoice] as PDF bytes. Pure — no IO, no plugins.
  static Future<Uint8List> bytes(OrderInvoice invoice) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => _body(invoice),
        // Long item lists spill onto a second page; the running footer ties
        // every page back to one invoice number.
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${invoice.invoiceNumber}  ·  '
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: _muted(8),
          ),
        ),
      ),
    );
    return doc.save();
  }

  /// Opens the system share sheet for the invoice as `<invoiceNumber>.pdf`.
  static Future<void> share(OrderInvoice invoice) async {
    await Printing.sharePdf(
      bytes: await bytes(invoice),
      filename: '${invoice.invoiceNumber}.pdf',
    );
  }

  /// Opens the OS print dialog for [invoice].
  static Future<void> print(OrderInvoice invoice) async {
    await Printing.layoutPdf(
      name: invoice.invoiceNumber,
      onLayout: (format) => bytes(invoice),
    );
  }
}

// Column flexes for the items table: item name gets the room, the three
// numeric columns stay wide enough for "RM 1,250" without wrapping.
const List<int> _itemFlex = [6, 1, 2, 2];

final pw.TextStyle _cell =
    const pw.TextStyle(fontSize: 10, color: PdfColors.grey900);

List<pw.Widget> _body(OrderInvoice invoice) => [
      _header(invoice),
      pw.SizedBox(height: 24),
      _parties(invoice),
      pw.SizedBox(height: 18),
      _referenceStrip(invoice),
      pw.SizedBox(height: 22),
      _itemsTable(invoice),
      pw.SizedBox(height: 18),
      _totals(invoice),
      pw.SizedBox(height: 22),
      pw.Divider(height: 1, thickness: 0.6, color: PdfColors.grey400),
      pw.SizedBox(height: 8),
      _footerNote(invoice),
    ];

pw.Widget _header(OrderInvoice invoice) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Text(
          'INVOICE',
          style: pw.TextStyle(
            fontSize: 30,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            invoice.invoiceNumber,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Issued ${Formatters.shortDate(invoice.issuedAt)}',
            style: _muted(10),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _parties(OrderInvoice invoice) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _party('FROM', invoice.supplierName, [
          invoice.supplierAddress,
          invoice.supplierPhone,
          invoice.supplierEmail,
        ]),
      ),
      pw.SizedBox(width: 24),
      pw.Expanded(
        child: _party('TO', invoice.customerName, [
          invoice.shippingAddress,
          invoice.customerPhone,
          invoice.customerEmail,
        ]),
      ),
    ],
  );
}

/// One address block. Empty fields are dropped rather than printed blank,
/// because this copy gets taped to a parcel and read at arm's length.
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
      if (name.trim().isNotEmpty)
        pw.Text(
          name.trim(),
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      ...lines,
    ],
  );
}

/// Order/payment reference in one strip so a reader can match the paper to
/// the app without hunting through the table.
pw.Widget _referenceStrip(OrderInvoice invoice) {
  final parts = <String>[
    if (invoice.orderNumber.trim().isNotEmpty)
      Formatters.formatOrderNumber(invoice.orderNumber),
    'Order placed ${Formatters.shortDate(invoice.orderCreatedAt)}',
    if (invoice.paymentMethod.trim().isNotEmpty)
      'Payment: ${invoice.paymentMethod.trim()}',
  ];
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(
      parts.join('  ·  '),
      style: pw.TextStyle(fontSize: 9.5, color: PdfColors.grey800),
    ),
  );
}

pw.Widget _itemsTable(OrderInvoice invoice) {
  if (invoice.items.isEmpty) {
    return pw.Text('No items on this invoice.', style: _muted(10));
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
      for (final item in invoice.items)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 7),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          child: _tableRow([
            pw.Text(item.name, style: _cell),
            pw.Text('${item.quantity}', style: _cell, textAlign: pw.TextAlign.right),
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
          '${invoice.lineCount} line items · ${invoice.unitCount} units',
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

pw.Widget _totals(OrderInvoice invoice) {
  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.SizedBox(
      width: 270,
      child: pw.Column(
        children: [
          _totalLine('Items subtotal', Formatters.myr(invoice.subtotal)),
          _totalLine('Shipping', Formatters.myr(invoice.shippingFee)),
          pw.SizedBox(height: 8),
          pw.Divider(height: 1, thickness: 0.8, color: PdfColors.grey500),
          pw.SizedBox(height: 8),
          _totalLine(
            'Total for this shipment',
            Formatters.myr(invoice.total),
            strong: true,
          ),
          if (invoice.orderDiscount > 0 || invoice.orderTax > 0) ...[
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                _adjustmentNote(invoice),
                textAlign: pw.TextAlign.right,
                style: _muted(8.5),
              ),
            ),
          ],
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

/// Order-level discount/tax exist, but they are not attributable to a single
/// supplier, so they are stated for reference and never enter [OrderInvoice.total].
String _adjustmentNote(OrderInvoice invoice) {
  final parts = <String>[
    if (invoice.orderDiscount > 0)
      'Order-level discount: ${Formatters.myr(invoice.orderDiscount)}',
    if (invoice.orderTax > 0) 'Tax: ${Formatters.myr(invoice.orderTax)}',
  ];
  return '${parts.join(' · ')} (not charged to this shipment)';
}

pw.Widget _footerNote(OrderInvoice invoice) {
  final supplier = invoice.supplierName.trim();
  final coverage = supplier.isEmpty
      ? 'This invoice covers only the items billed on this document.'
      : 'This invoice covers only the items supplied by $supplier.';
  return pw.Text(
    '$coverage The order may include items from other suppliers, '
    'invoiced separately.',
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
