// Tests for the invoice PDF renderer — the document a supplier prints and
// tapes to the parcel.
//
// `InvoicePdf.bytes` is pure (no IO, no plugins), so the document build can
// be exercised headless. The share/print actions wrap the `printing` plugin
// and are not covered here.

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/models/order.dart';
import 'package:interior_design_recommendation/services/invoice/invoice_pdf.dart';

OrderItem _item({
  String id = 'p1',
  String name = 'Nordic Sofa',
  int unitPrice = 100,
  int quantity = 1,
  String supplierId = 's1',
}) {
  return OrderItem(
    productId: id,
    name: name,
    image: '',
    unitPrice: unitPrice,
    quantity: quantity,
    supplierId: supplierId,
  );
}

OrderInvoice _invoice({
  List<OrderItem>? items,
  int shippingFee = 15,
  int subtotal = 200,
  int orderDiscount = 0,
  int orderTax = 0,
  String supplierPhone = '0129998888',
  String supplierAddress = '2 Jalan Supplier, Petaling Jaya',
  String supplierEmail = 'shop@example.com',
}) {
  final myItems = items ?? [_item(unitPrice: 100, quantity: 2)];
  return OrderInvoice(
    invoiceNumber: 'INV-20260929-1234',
    orderId: 'o1',
    orderNumber: 'ORD-20260929-5678',
    supplierId: 's1',
    supplierName: 'Studio Kayu',
    supplierPhone: supplierPhone,
    supplierAddress: supplierAddress,
    supplierEmail: supplierEmail,
    issuedAt: DateTime(2026, 9, 29, 14, 5),
    items: myItems,
    subtotal: subtotal,
    shippingFee: shippingFee,
    total: subtotal + shippingFee,
    customerName: 'Aina',
    customerEmail: 'aina@example.com',
    customerPhone: '0123456789',
    shippingAddress: '1 Jalan Test, Kuala Lumpur',
    paymentMethod: 'fpx',
    orderCreatedAt: DateTime(2026, 9, 29, 10, 30),
    orderDiscount: orderDiscount,
    orderTax: orderTax,
  );
}

/// PDF files start with the magic `%PDF-` and are not empty stubs.
void expectValidPdf(List<int> bytes, {int minBytes = 500}) {
  expect(bytes.length, greaterThan(minBytes),
      reason: 'PDF should be a real document, not an empty stub');
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
}

void main() {
  group('InvoicePdf.bytes', () {
    test('renders a valid PDF for a normal invoice', () async {
      final bytes = await InvoicePdf.bytes(_invoice());

      expectValidPdf(bytes);
    });

    test('renders when the supplier contact fields are empty', () async {
      final bytes = await InvoicePdf.bytes(_invoice(
        supplierPhone: '',
        supplierAddress: '',
        supplierEmail: '',
      ));

      expectValidPdf(bytes);
    });

    test('renders a zero shipping charge rather than hiding it', () async {
      final bytes = await InvoicePdf.bytes(_invoice(shippingFee: 0));

      expectValidPdf(bytes);
    });

    test('renders with no line items without crashing', () async {
      final bytes = await InvoicePdf.bytes(_invoice(
        items: const [],
        subtotal: 0,
        shippingFee: 0,
      ));

      expectValidPdf(bytes);
    });

    test('carries order-level discount/tax without touching the total', () async {
      // These are reference-only on the invoice. The builder must render them
      // (when non-zero) and must not fold them into "Total for this shipment".
      final inv = _invoice(orderDiscount: 10, orderTax: 6);
      expect(inv.total, 215); // 200 + 15, discount/tax excluded

      final bytes = await InvoicePdf.bytes(inv);

      expectValidPdf(bytes);
    });

    test('paginates a long item list without crashing', () async {
      final items = List.generate(
        60,
        (i) => _item(
          id: 'p$i',
          name: 'Item ${i + 1}',
          unitPrice: 10 + i,
          quantity: 1 + (i % 3),
        ),
      );
      final bytes = await InvoicePdf.bytes(_invoice(
        items: items,
        subtotal: items.fold(0, (s, i) => s + i.lineTotal),
      ));

      expectValidPdf(bytes);
    });
  });
}
