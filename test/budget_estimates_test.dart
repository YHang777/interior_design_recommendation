import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_estimates.dart';
import 'package:interior_design_recommendation/models/product.dart';

Product _product({
  String? id,
  String? name,
  required String category,
  required int price,
  int stock = 10,
  bool isActive = true,
  bool isEcoFriendly = false,
  String supplierName = 'Seller',
}) {
  return Product(
    id: id ?? 'p-$category-$price',
    name: name ?? 'Product $category $price',
    price: price,
    stock: stock,
    image: '',
    description: '',
    designStyle: 'Modern',
    category: category,
    supplier: Supplier(
      id: 's1',
      name: supplierName,
      phone: '',
      address: '',
      email: '',
    ),
    isActive: isActive,
    isEcoFriendly: isEcoFriendly,
  );
}

void main() {
  group('medianPrice', () {
    test('empty input → null (no price data), never 0-as-a-quote', () {
      expect(medianPrice(const []), isNull);
    });

    test('single value', () {
      expect(medianPrice([120]), 120);
    });

    test('odd count → middle value', () {
      expect(medianPrice([300, 100, 200]), 200);
    });

    test('even count → mean of the two middle values', () {
      expect(medianPrice([100, 200, 300, 400]), 250);
    });
  });

  group('buildEstimateLines', () {
    test('empty catalogue → every line honestly has no price data', () {
      final lines = buildEstimateLines(const [], ecoFriendly: false);
      expect(lines, hasLength(budgetLineLabels.length));
      for (final l in lines) {
        expect(l.price, isNull, reason: '${l.label} must not invent a price');
        expect(l.matches, 0);
        expect(l.hasData, isFalse);
      }
      expect(estimateTotal(lines), 0);
    });

    test('maps product categories onto the five budget lines with the '
        'lowest price and its supplier', () {
      final lines = buildEstimateLines([
        _product(category: 'Paint', price: 120),
        _product(category: 'Wall Covering', price: 200),
        _product(category: 'Flooring', price: 300),
        _product(category: 'Furniture', price: 900),
        _product(category: 'Lighting', price: 150),
        _product(category: 'Decor', price: 60),
        _product(category: 'Textiles', price: 80),
      ], ecoFriendly: false);

      expect(lines[0].label, 'Wall Paint');
      expect(lines[0].price, 120);
      expect(lines[0].matches, 2);
      expect(lines[0].supplier, 'Seller');
      expect(lines[0].productId, 'p-Paint-120');
      expect(lines[0].material, 'Product Paint 120');

      expect(lines[1].price, 300);
      expect(lines[2].price, 900);
      expect(lines[3].price, 150);
      expect(lines[4].label, 'Accessories');
      expect(lines[4].price, 60);
      expect(lines[4].matches, 2);

      expect(estimateTotal(lines), 120 + 300 + 900 + 150 + 60);
    });

    test('a tie keeps the first listing in catalogue order', () {
      final lines = buildEstimateLines([
        _product(id: 'first', name: 'Cheapest A', category: 'Furniture',
            price: 500),
        _product(id: 'second', name: 'Cheapest B', category: 'Furniture',
            price: 500),
      ], ecoFriendly: false);
      expect(lines[2].price, 500);
      expect(lines[2].productId, 'first');
      expect(lines[2].material, 'Cheapest A');
    });

    test('a missing supplier name falls back to null, not a blank cell', () {
      final lines = buildEstimateLines([
        _product(category: 'Flooring', price: 300, supplierName: '   '),
      ], ecoFriendly: false);
      expect(lines[1].price, 300);
      expect(lines[1].supplier, isNull);
    });

    test('inactive listings are never priced', () {
      final lines = buildEstimateLines([
        _product(category: 'Furniture', price: 900, isActive: false),
      ], ecoFriendly: false);
      expect(lines[2].label, 'Furniture');
      expect(lines[2].price, isNull);
      expect(lines[2].matches, 0);
    });

    test('eco mode prices only from eco-friendly listings', () {
      final products = [
        _product(category: 'Furniture', price: 900),
        _product(category: 'Furniture', price: 1200, isEcoFriendly: true),
      ];

      final normal =
          buildEstimateLines(products, ecoFriendly: false);
      expect(normal[2].price, 900);
      expect(normal[2].matches, 2);

      final eco = buildEstimateLines(products, ecoFriendly: true);
      expect(eco[2].price, 1200);
      expect(eco[2].matches, 1);
    });

    test('eco mode with no eco listings → no price data (not a fallback lie)',
        () {
      final lines = buildEstimateLines([
        _product(category: 'Furniture', price: 900),
      ], ecoFriendly: true);
      expect(lines[2].price, isNull);
    });

    test('category matching is case-insensitive', () {
      final lines = buildEstimateLines([
        _product(category: 'paint', price: 99),
      ], ecoFriendly: false);
      expect(lines[0].price, 99);
    });
  });

  group('buildLineOptions', () {
    test('sorts cheapest-first and carries supplier, stock and eco flags', () {
      final options = buildLineOptions([
        _product(id: 'b', name: 'Mid', category: 'Furniture', price: 900),
        _product(id: 'a', name: 'Deep', category: 'Furniture', price: 400,
            stock: 0),
        _product(id: 'c', name: 'Pricy', category: 'Furniture', price: 1500,
            isEcoFriendly: true, supplierName: 'GreenCo'),
      ], label: 'Furniture', ecoFriendly: false);

      expect(options, hasLength(3));
      expect(options.map((o) => o.productId), ['a', 'b', 'c']);
      expect(options.first.price, 400);
      expect(options.first.inStock, isFalse);
      expect(options.first.supplier, 'Seller');
      expect(options[1].inStock, isTrue);
      expect(options.last.price, 1500);
      expect(options.last.isEcoFriendly, isTrue);
      expect(options.last.supplier, 'GreenCo');
    });

    test('applies the same active + eco rules as the estimate lines', () {
      final products = [
        _product(id: 'off', category: 'Furniture', price: 100, isActive: false),
        _product(id: 'plain', category: 'Furniture', price: 200),
        _product(id: 'eco', category: 'Furniture', price: 300,
            isEcoFriendly: true),
        _product(id: 'other', category: 'Lighting', price: 50),
      ];

      final all = buildLineOptions(products,
          label: 'Furniture', ecoFriendly: false);
      expect(all.map((o) => o.productId), ['plain', 'eco']);

      final eco = buildLineOptions(products,
          label: 'Furniture', ecoFriendly: true);
      expect(eco.map((o) => o.productId), ['eco']);
    });

    test('unknown label → empty options, never a wrong category', () {
      final options = buildLineOptions([
        _product(category: 'Furniture', price: 900),
      ], label: 'Garage', ecoFriendly: false);
      expect(options, isEmpty);
    });

    test('matches the estimate line price exactly (lowest == options.first)',
        () {
      final products = [
        _product(id: 'x1', category: 'Paint', price: 85),
        _product(id: 'x2', category: 'Paint', price: 95),
      ];
      final line = buildEstimateLines(products, ecoFriendly: false).first;
      final options = buildLineOptions(products,
          label: 'Wall Paint', ecoFriendly: false);
      expect(line.price, options.first.price);
      expect(line.productId, options.first.productId);
      expect(line.matches, options.length);
    });
  });

  group('buildBudgetReport', () {
    final lines = buildEstimateLines([
      _product(category: 'Paint', price: 120),
      _product(category: 'Flooring', price: 300),
    ], ecoFriendly: false);

    test('contains the real budget, estimates and remaining', () {
      final report = buildBudgetReport(
        room: 'Kitchen',
        budgetRm: 5000,
        lines: lines,
        generatedAt: DateTime(2026, 9, 28, 14, 5),
        ecoFriendly: false,
      );
      expect(report, contains('Kitchen'));
      expect(report, contains('Budget: RM 5,000'));
      expect(report, contains('Wall Paint: RM 120'));
      expect(report, contains('Flooring: RM 300'));
      expect(report, contains('Total estimate: RM 420'));
      expect(report, contains('Remaining: RM 4,580'));
      expect(report, contains('28 Sep 2026 · 14:05'));
      expect(report, isNot(contains('mocked')));
    });

    test('lines without price data say so explicitly', () {
      final report = buildBudgetReport(
        room: 'Bedroom',
        budgetRm: 0,
        lines: lines,
        generatedAt: DateTime(2026, 9, 28),
        ecoFriendly: true,
      );
      expect(report, contains('Furniture: — (no price data yet)'));
      expect(report, contains('eco-friendly listings only'));
      expect(report, contains('Over budget by RM 420'));
    });

    test('states the lowest-price basis and names the supplier when known', () {
      final report = buildBudgetReport(
        room: 'Kitchen',
        budgetRm: 5000,
        lines: lines,
        generatedAt: DateTime(2026, 9, 28),
        ecoFriendly: false,
      );
      expect(report, contains('lowest prices across active marketplace'));
      expect(report, isNot(contains('median')));
      expect(report, contains('Wall Paint: RM 120 · Seller'));
    });
  });
}
