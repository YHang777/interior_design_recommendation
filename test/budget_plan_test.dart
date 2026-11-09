import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_plan.dart';

void main() {
  group('BudgetPlan.fromJson / toJson', () {
    test('round-trips every field', () {
      final plan = BudgetPlan(
        budgetRm: 7500,
        room: 'Bedroom',
        ecoFriendly: true,
        updatedAt: DateTime.utc(2026, 9, 28, 6, 30),
        choices: const {'Furniture': 'p-1', 'Lighting': 'p-2'},
        designId: 'design-9',
      );
      final restored = BudgetPlan.fromJson(plan.toJson());
      expect(restored.budgetRm, 7500);
      expect(restored.room, 'Bedroom');
      expect(restored.designId, 'design-9');
      expect(restored.ecoFriendly, isTrue);
      expect(restored.updatedAt.toUtc(), DateTime.utc(2026, 9, 28, 6, 30));
      expect(restored.choices, {'Furniture': 'p-1', 'Lighting': 'p-2'});
    });

    test('empty map → zero budget and default room (no seeded 5000)', () {
      final plan = BudgetPlan.fromJson(const {});
      expect(plan.budgetRm, 0);
      expect(plan.room, defaultBudgetRoom);
      expect(plan.designId, '');
      expect(plan.ecoFriendly, isFalse);
      expect(plan.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(plan.choices, isEmpty);
    });

    test('a legacy plan with no choices key still loads with no choices', () {
      final plan = BudgetPlan.fromJson(const {
        'budgetRm': 4300,
        'room': 'Living Room',
        'ecoFriendly': true,
        'updatedAt': '2026-09-28T06:30:00.000Z',
      });
      expect(plan.budgetRm, 4300);
      expect(plan.choices, isEmpty);
      // Legacy room type without a designId → total budget.
      expect(plan.room, defaultBudgetRoom);
    });

    test('malformed choices degrade to an empty map, not a crash', () {
      expect(BudgetPlan.fromJson(const {'choices': 'nope'}).choices, isEmpty);
      expect(BudgetPlan.fromJson(const {'choices': 7}).choices, isEmpty);
      expect(
        BudgetPlan.fromJson(const {
          'choices': {'Furniture': 42, '': 'p-1', 'Lighting': '  '},
        }).choices,
        isEmpty,
      );
      expect(
        BudgetPlan.fromJson(const {
          'choices': {'Furniture': 'p-9', 'Lighting': 42},
        }).choices,
        {'Furniture': 'p-9'},
      );
    });

    test('unknown room falls back to the total budget', () {
      final plan = BudgetPlan.fromJson(const {
        'budgetRm': 1000,
        'room': 'Garage',
      });
      expect(plan.room, defaultBudgetRoom);
      expect(budgetRooms.contains(plan.room), isFalse);
    });

    test('a legacy room-type label migrates to the total budget', () {
      final plan = BudgetPlan.fromJson(const {
        'room': 'Living Room',
        'budgetRm': '2500',
      });
      expect(plan.room, defaultBudgetRoom);
      expect(plan.designId, '');
      expect(plan.budgetRm, 2500);
    });

    test('a design-scoped plan keeps its label and designId', () {
      final plan = BudgetPlan.fromJson(const {
        'room': 'Bedroom',
        'designId': 'design-7',
        'budgetRm': 1500,
      });
      expect(plan.room, 'Bedroom');
      expect(plan.designId, 'design-7');
    });

    test('a label without a designId collapses to the total budget', () {
      final plan = BudgetPlan.fromJson(const {'room': 'My Reno'});
      expect(plan.room, defaultBudgetRoom);
    });

    test('numeric budget survives num-typed Firestore values', () {
      final plan = BudgetPlan.fromJson(const {'budgetRm': 1800.0});
      expect(plan.budgetRm, 1800);
    });

    test('toJson emits exactly the schema watchBudget parses back', () {
      final plan = BudgetPlan(
        budgetRm: 4300,
        room: 'Living Room',
        ecoFriendly: true,
        updatedAt: DateTime.utc(2026, 9, 28, 6, 30),
        choices: const {'Flooring': 'p-floor-1'},
        designId: 'design-42',
      );
      final json = plan.toJson();
      expect(
        json.keys.toSet(),
        {
          'budgetRm',
          'room',
          'ecoFriendly',
          'updatedAt',
          'choices',
          'designId',
        },
      );
      expect(json['budgetRm'], isA<int>());
      expect(json['room'], isA<String>());
      expect(json['ecoFriendly'], isA<bool>());
      expect(json['updatedAt'], isA<String>());
      expect(json['choices'], isA<Map<String, String>>());
      expect(json['designId'], isA<String>());

      final restored = BudgetPlan.fromJson(json);
      expect(restored.budgetRm, 4300);
      expect(restored.room, 'Living Room');
      expect(restored.designId, 'design-42');
      expect(restored.ecoFriendly, isTrue);
      expect(restored.updatedAt.toUtc(), DateTime.utc(2026, 9, 28, 6, 30));
      expect(restored.choices, {'Flooring': 'p-floor-1'});
    });

    test('updatedAt is written as UTC ISO-8601 with a Z suffix', () {
      final local = DateTime(2026, 9, 28, 14, 30);
      final plan = BudgetPlan(
        budgetRm: 100,
        room: defaultBudgetRoom,
        ecoFriendly: false,
        updatedAt: local,
      );
      final written = plan.toJson()['updatedAt'] as String;
      expect(written, endsWith('Z'));
      expect(
        BudgetPlan.fromJson(plan.toJson()).updatedAt.toUtc(),
        local.toUtc(),
      );
    });

    test('an eco-off, zero-budget plan round-trips without inventing '
        'defaults on the way back', () {
      final plan = BudgetPlan(
        budgetRm: 0,
        room: 'Bathroom',
        ecoFriendly: false,
        updatedAt: DateTime.utc(2026, 1, 1),
        designId: 'design-3',
      );
      final restored = BudgetPlan.fromJson(plan.toJson());
      expect(restored.budgetRm, 0);
      expect(restored.ecoFriendly, isFalse);
      expect(restored.room, 'Bathroom');
      expect(restored.designId, 'design-3');
    });
  });
}
