// Tests for the budget planner's live-catalogue estimate logic and the
// clipboard report builder.
//
// Pure Dart — no widgets, no Firebase, no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_estimates.dart';
import 'package:interior_design_recommendation/models/product.dart';

Product _product({
  required String category,
  required int price,
  bool isActive = true,
  bool isEcoFriendly = false,
}) {
  return Product(
    id: 'p-$category-$price',
    name: 'Product $category $price',
    price: price,
    stock: 10,
    image: '',
    description: '',
    designStyle: 'Modern',
    category: category,
    supplier: const Supplier(
      id: 's1',
      name: 'Seller',
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

    test('maps product categories onto the five budget lines', () {
      final lines = buildEstimateLines([
        _product(category: 'Paint', price: 120),
        _product(category: 'Wall Covering', price: 200),
        _product(category: 'Flooring', price: 300),
        _product(category: 'Furniture', price: 900),
        _product(category: 'Lighting', price: 150),
        _product(category: 'Decor', price: 60),
        _product(category: 'Textiles', price: 80),
      ], ecoFriendly: false);

      // Wall Paint covers Paint + Wall Covering → median(120, 200) = 160.
      expect(lines[0].label, 'Wall Paint');
      expect(lines[0].price, 160);
      expect(lines[0].matches, 2);

      expect(lines[1].price, 300); // Flooring
      expect(lines[2].price, 900); // Furniture
      expect(lines[3].price, 150); // Lighting
      // Accessories = Decor + Textiles → median(60, 80) = 70.
      expect(lines[4].label, 'Accessories');
      expect(lines[4].price, 70);
      expect(lines[4].matches, 2);

      expect(estimateTotal(lines), 160 + 300 + 900 + 150 + 70);
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
      expect(normal[2].price, medianPrice([900, 1200]));
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
      // Budget 0 with a 420 estimate → honest over-budget line.
      expect(report, contains('Over budget by RM 420'));
    });
  });
}
