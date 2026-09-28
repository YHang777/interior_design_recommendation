// Tests for the persisted BudgetPlan model (users/{uid}.budgetPlan).

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
      );
      final restored = BudgetPlan.fromJson(plan.toJson());
      expect(restored.budgetRm, 7500);
      expect(restored.room, 'Bedroom');
      expect(restored.ecoFriendly, isTrue);
      expect(restored.updatedAt.toUtc(), DateTime.utc(2026, 9, 28, 6, 30));
    });

    test('empty map → zero budget and default room (no seeded 5000)', () {
      final plan = BudgetPlan.fromJson(const {});
      expect(plan.budgetRm, 0);
      expect(plan.room, defaultBudgetRoom);
      expect(plan.ecoFriendly, isFalse);
      // Unknown timestamp reads as epoch, never "now".
      expect(plan.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('unknown room falls back to the dropdown-safe default', () {
      final plan = BudgetPlan.fromJson(const {
        'budgetRm': 1000,
        'room': 'Garage',
      });
      expect(plan.room, defaultBudgetRoom);
      expect(budgetRooms.contains(plan.room), isTrue);
    });

    test('a known room is kept as-is', () {
      final plan = BudgetPlan.fromJson(const {
        'room': 'Living Room',
        'budgetRm': '2500',
      });
      expect(plan.room, 'Living Room');
      expect(plan.budgetRm, 2500);
    });

    test('numeric budget survives num-typed Firestore values', () {
      final plan = BudgetPlan.fromJson(const {'budgetRm': 1800.0});
      expect(plan.budgetRm, 1800);
    });

    test('toJson emits exactly the schema watchBudget parses back', () {
      // BudgetRepository.watchBudget only accepts the field when it comes
      // back as a map and BudgetPlan.fromJson understands every key — so
      // the written schema is a contract: adding/removing/renaming a key
      // here silently breaks persistence round-trips in production.
      final plan = BudgetPlan(
        budgetRm: 4300,
        room: 'Living Room',
        ecoFriendly: true,
        updatedAt: DateTime.utc(2026, 9, 28, 6, 30),
      );
      final json = plan.toJson();
      expect(
        json.keys.toSet(),
        {'budgetRm', 'room', 'ecoFriendly', 'updatedAt'},
      );
      expect(json['budgetRm'], isA<int>());
      expect(json['room'], isA<String>());
      expect(json['ecoFriendly'], isA<bool>());
      expect(json['updatedAt'], isA<String>());

      final restored = BudgetPlan.fromJson(json);
      expect(restored.budgetRm, 4300);
      expect(restored.room, 'Living Room');
      expect(restored.ecoFriendly, isTrue);
      expect(restored.updatedAt.toUtc(), DateTime.utc(2026, 9, 28, 6, 30));
    });

    test('updatedAt is written as UTC ISO-8601 with a Z suffix', () {
      // A local-time DateTime would serialise without the timezone
      // context and drift the instant; toUtc() must be applied on write.
      final local = DateTime(2026, 9, 28, 14, 30); // local wall time
      final plan = BudgetPlan(
        budgetRm: 100,
        room: defaultBudgetRoom,
        ecoFriendly: false,
        updatedAt: local,
      );
      final written = plan.toJson()['updatedAt'] as String;
      expect(written, endsWith('Z'));
      // Round-trip keeps the same instant regardless of the host zone.
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
      );
      final restored = BudgetPlan.fromJson(plan.toJson());
      expect(restored.budgetRm, 0); // never re-seeded to 5000
      expect(restored.ecoFriendly, isFalse); // never flipped to true
      expect(restored.room, 'Bathroom');
    });
  });
}
