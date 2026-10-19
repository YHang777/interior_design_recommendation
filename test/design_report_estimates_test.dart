import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/design_report.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

Product _product({
  required String name,
  required int price,
  String category = 'Furniture',
  String designStyle = 'Modern',
  bool isActive = true,
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
    isActive: isActive,
  );
}

FurniturePlacement _place({
  String name = 'Sofa',
  String iconName = 'sofa',
}) {
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

RoomDesign _design({List<FurniturePlacement> furniture = const []}) {
  return RoomDesign(
    id: 'd1',
    name: 'Living Room Refresh',
    roomType: 'living_room',
    furniture: furniture,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 28),
    userId: 'u1',
  );
}

void main() {
  group('displayCategoryFor', () {
    test('maps known placements to marketplace display categories', () {
      expect(displayCategoryFor(_place(name: 'Sofa')), 'Furniture');
      expect(displayCategoryFor(_place(name: 'TV Stand')), 'Furniture');
      expect(displayCategoryFor(_place(name: 'Floor Lamp')), 'Lighting');
      expect(displayCategoryFor(_place(name: 'Plant')), 'Decor');
      expect(displayCategoryFor(_place(name: 'Rug')), 'Decor');
    });

    test('falls back to the icon name, then to Furniture', () {
      expect(
        displayCategoryFor(_place(name: 'Lounge Seat', iconName: 'sofa')),
        'Furniture',
      );
      expect(
        displayCategoryFor(_place(name: 'Glow', iconName: 'floor_lamp')),
        'Lighting',
      );
      expect(
        displayCategoryFor(_place(name: 'Mystery', iconName: 'mystery')),
        'Furniture',
      );
    });
  });

  group('buildDesignReport — item prices', () {
    test('name match beats category match', () {
      final report = buildDesignReport(
        _design(furniture: [_place(name: 'Sofa')]),
        [
          _product(name: 'Sofa XL', price: 900),
          _product(name: 'Accent Chair', price: 300),
          _product(name: 'Dining Bench', price: 500),
        ],
      );

      final item = report.items.single;
      expect(item.estimatedPrice, 900,
          reason: 'only the name-matched listing may price this item');
      expect(item.matches, 1);
      expect(item.category, 'Furniture');
    });

    test('median of an even count is the mean of the two middle values', () {
      final report = buildDesignReport(
        _design(furniture: [_place(name: 'Sofa')]),
        [
          _product(name: 'Sofa A', price: 100),
          _product(name: 'Sofa B', price: 400),
          _product(name: 'Sofa C', price: 200),
          _product(name: 'Sofa D', price: 300),
        ],
      );

      expect(report.items.single.matches, 4);
      expect(report.items.single.estimatedPrice, 250);
    });

    test('no matching listing → null price, never an invented number', () {
      final report = buildDesignReport(
        _design(furniture: [_place(name: 'Sofa')]),
        [_product(name: 'Toaster', price: 80, category: 'Appliances')],
      );

      final item = report.items.single;
      expect(item.estimatedPrice, isNull);
      expect(item.matches, 0);
      expect(item.hasData, isFalse);
      expect(report.expenses.hasData, isFalse);
    });

    test('category match is the fallback when no name matches', () {
      final report = buildDesignReport(
        _design(furniture: [_place(name: 'Plant')]),
        [
          _product(name: 'Monstera', price: 150, category: 'Decor'),
          _product(name: 'Fiddle Leaf', price: 250, category: 'Decor'),
          _product(name: 'Sofa', price: 900, category: 'Furniture'),
        ],
      );

      final item = report.items.single;
      expect(item.category, 'Decor');
      expect(item.estimatedPrice, 200);
      expect(item.matches, 2);
    });

    test('inactive listings are never priced', () {
      final report = buildDesignReport(
        _design(furniture: [_place(name: 'Sofa')]),
        [_product(name: 'Sofa XL', price: 900, isActive: false)],
      );

      expect(report.items.single.estimatedPrice, isNull);
      expect(report.items.single.matches, 0);
    });

    test('empty furniture list → no items, no data', () {
      final report = buildDesignReport(_design(), const []);

      expect(report.items, isEmpty);
      expect(report.expenses.hasData, isFalse);
      expect(report.derivedStyle, isNull);
    });
  });

  group('buildDesignReport — expenses', () {
    test('installation is 10%, delivery 5%, total sums the three', () {
      final report = buildDesignReport(
        _design(furniture: [
          _place(name: 'Sofa'),
          _place(name: 'Coffee Table', iconName: 'coffee_table'),
        ]),
        [
          _product(name: 'Sofa XL', price: 1000),
          _product(name: 'Coffee Table Oak', price: 500),
        ],
      );

      expect(report.expenses.furniture, 1500);
      expect(report.expenses.installation, 150);
      expect(report.expenses.delivery, 75);
      expect(report.expenses.total, 1500 + 150 + 75);
      expect(report.expenses.hasData, isTrue);
    });

    test('items without price data contribute nothing to the sum', () {
      final report = buildDesignReport(
        _design(furniture: [
          _place(name: 'Sofa'),
          _place(name: 'Floor Lamp', iconName: 'floor_lamp'),
        ]),
        [_product(name: 'Sofa XL', price: 1000)],
      );

      expect(report.items[0].estimatedPrice, 1000);
      expect(report.items[1].estimatedPrice, isNull);
      expect(report.expenses.furniture, 1000);
      expect(report.expenses.installation, 100);
      expect(report.expenses.delivery, 50);
      expect(report.expenses.total, 1150);
    });
  });

  group('buildDesignReport — derived style', () {
    test('majority style among name-matched products wins', () {
      final report = buildDesignReport(
        _design(furniture: [_place(name: 'Sofa')]),
        [
          _product(name: 'Sofa A', price: 900, designStyle: 'Modern'),
          _product(name: 'Sofa B', price: 800, designStyle: 'Modern'),
          _product(name: 'Sofa C', price: 700, designStyle: 'Scandinavian'),
        ],
      );

      expect(report.derivedStyle, 'Modern');
    });

    test('ties break deterministically to the first style alphabetically', () {
      final report = buildDesignReport(
        _design(furniture: [_place(name: 'Sofa')]),
        [
          _product(name: 'Sofa A', price: 900, designStyle: 'Modern'),
          _product(name: 'Sofa B', price: 800, designStyle: 'Modern'),
          _product(name: 'Sofa C', price: 700, designStyle: 'Industrial'),
          _product(name: 'Sofa D', price: 600, designStyle: 'Industrial'),
        ],
      );

      expect(report.derivedStyle, 'Industrial');
    });

    test('falls back to category matches when nothing matched by name', () {
      final report = buildDesignReport(
        _design(furniture: [_place(name: 'Plant')]),
        [
          _product(name: 'Monstera', price: 150, category: 'Decor',
              designStyle: 'Boho'),
          _product(name: 'Fiddle Leaf', price: 250, category: 'Decor',
              designStyle: 'Boho'),
          _product(name: 'Fern', price: 50, category: 'Decor',
              designStyle: 'Minimalist'),
        ],
      );

      expect(report.derivedStyle, 'Boho');
    });

    test('no matches → null (UI shows "Not specified")', () {
      final report = buildDesignReport(
        _design(furniture: [_place(name: 'Sofa')]),
        const [],
      );

      expect(report.derivedStyle, isNull);
    });
  });
}
