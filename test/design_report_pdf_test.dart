import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/design_report.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/room_design.dart';
import 'package:interior_design_recommendation/services/invoice/design_report_pdf.dart';

Product _product({
  required String name,
  required int price,
  String category = 'Furniture',
  String designStyle = 'Modern',
}) {
  return Product(
    id: 'p-$name-$price',
    name: name,
    price: price,
    stock: 10,
    image: '',
    description: '',
    designStyle: designStyle,
    category: category,
    supplier: const Supplier(
      id: 's1',
      name: 'Seller',
      phone: '',
      address: '',
      email: '',
    ),
  );
}

FurniturePlacement _place(String name, String iconName) {
  return FurniturePlacement(
    id: 'f-$name',
    name: name,
    iconName: iconName,
    x: 0,
    y: 0,
    width: 180,
    height: 90,
  );
}

DesignReportData _report({List<FurniturePlacement> furniture = const []}) {
  final design = RoomDesign(
    id: 'd1',
    name: 'Living Room Refresh',
    roomType: 'living_room',
    furniture: furniture,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 28),
    userId: 'u1',
  );
  return buildDesignReport(design, [
    _product(name: 'Sofa XL', price: 1000),
    _product(name: 'Coffee Table Oak', price: 500),
    _product(name: 'Floor Lamp Arc', price: 150, category: 'Lighting'),
  ]);
}

void expectValidPdf(List<int> bytes, {int minBytes = 500}) {
  expect(bytes.length, greaterThan(minBytes),
      reason: 'PDF should be a real document, not an empty stub');
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
}

void main() {
  group('DesignReportPdf.bytes', () {
    test('renders a valid PDF for a design with items', () async {
      final report = _report(furniture: [
        _place('Sofa', 'sofa'),
        _place('Coffee Table', 'coffee_table'),
        _place('Floor Lamp', 'floor_lamp'),
      ]);

      expect(report.items, hasLength(3));
      expect(report.expenses.hasData, isTrue);

      final bytes = await DesignReportPdf.bytes(report);

      expectValidPdf(bytes);
    });

    test('renders with an empty furniture list without crashing', () async {
      final report = _report();

      expect(report.items, isEmpty);
      expect(report.expenses.hasData, isFalse);

      final bytes = await DesignReportPdf.bytes(report);

      expectValidPdf(bytes);
    });

    test('paginates a long item list without crashing', () async {
      final furniture = List.generate(
        60,
        (i) => _place('Item ${i + 1}', 'sofa'),
      );
      final bytes = await DesignReportPdf.bytes(
        _report(furniture: furniture),
      );

      expectValidPdf(bytes);
    });
  });
}
