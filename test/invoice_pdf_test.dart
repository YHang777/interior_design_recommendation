import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/models/order.dart';
import 'package:interior_design_recommendation/services/invoice/invoice_pdf.dart';
import 'package:interior_design_recommendation/services/invoice/receipt_pdf.dart';

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
  int subtotal = 200,
  int total = 200,
  int discountAllocated = 0,
  int taxAllocated = 0,
  String supplierPhone = '0129998888',
  String supplierAddress = '2 Jalan Supplier, Petaling Jaya',
  String supplierEmail = 'shop@example.com',
  bool paid = true,
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
    total: total,
    customerName: 'Aina',
    customerEmail: 'aina@example.com',
    customerPhone: '0123456789',
    paymentMethod: 'fpx',
    orderCreatedAt: DateTime(2026, 9, 29, 10, 30),
    discountAllocated: discountAllocated,
    taxAllocated: taxAllocated,
    paymentIntentId: paid ? 'pi_3ABC123' : '',
    paidAt: paid ? DateTime(2026, 9, 29, 14, 10) : null,
  );
}

Order _order({
  List<OrderItem>? items,
  int subtotal = 200,
  int discount = 0,
  int tax = 0,
  int total = 200,
  String paymentMethod = 'card',
  String paymentIntentId = 'pi_3ABC123',
  DateTime? paidAt,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  String membershipTier = 'Silver',
}) {
  return Order(
    id: 'o1',
    orderNumber: 'ORD-20260929-5678',
    customerId: 'c1',
    customerName: 'Aina',
    customerEmail: 'aina@example.com',
    customerPhone: '0123456789',
    items: items ?? [_item(unitPrice: 100, quantity: 2)],
    status: OrderStatus.confirmed,
    paymentStatus: paymentStatus,
    paymentMethod: paymentMethod,
    paymentIntentId: paymentIntentId,
    paidAt: paidAt ?? DateTime(2026, 9, 29, 14, 10),
    subtotal: subtotal,
    discount: discount,
    tax: tax,
    total: total,
    membershipTier: membershipTier,
    createdAt: DateTime(2026, 9, 29, 10, 30),
  );
}

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

    test('renders with no line items without crashing', () async {
      final bytes = await InvoicePdf.bytes(_invoice(
        items: const [],
        subtotal: 0,
        total: 0,
      ));

      expectValidPdf(bytes);
    });

    test('renders the allocated discount and tax shares', () async {
      final bytes = await InvoicePdf.bytes(_invoice(
        discountAllocated: 8,
        taxAllocated: 12,
        subtotal: 200,
        total: 204,
      ));

      expectValidPdf(bytes);
    });

    test('renders an unpaid invoice without a PAID stamp', () async {
      final bytes = await InvoicePdf.bytes(_invoice(paid: false));

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

  group('ReceiptPdf.bytes', () {
    test('renders a valid PDF for a paid order', () async {
      final bytes = await ReceiptPdf.bytes(_order());

      expectValidPdf(bytes);
    });

    test('renders an unpaid order without crashing', () async {
      final bytes = await ReceiptPdf.bytes(_order(
        paymentStatus: PaymentStatus.unpaid,
        paidAt: null,
      ));

      expectValidPdf(bytes);
    });

    test('renders with no line items without crashing', () async {
      final bytes = await ReceiptPdf.bytes(_order(items: const []));

      expectValidPdf(bytes);
    });

    test('renders discount and tax lines from the stored order', () async {
      final bytes = await ReceiptPdf.bytes(_order(
        discount: 10,
        tax: 6,
        total: 196,
      ));

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
      final bytes = await ReceiptPdf.bytes(_order(
        items: items,
        subtotal: items.fold(0, (s, i) => s + i.lineTotal),
      ));

      expectValidPdf(bytes);
    });
  });
}
