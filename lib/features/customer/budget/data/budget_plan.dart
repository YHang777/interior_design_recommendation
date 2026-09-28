/// Rooms the budget planner can plan for — single source of truth for the
/// dropdown and for validating a plan loaded back from Firestore.
const budgetRooms = ['Kitchen', 'Living Room', 'Bedroom', 'Bathroom'];

/// The room used before anything has been saved.
const defaultBudgetRoom = 'Kitchen';

/// The customer's saved budget-planner inputs.
///
/// One plan per user, persisted as the `budgetPlan` map field on the user's
/// own `users/{uid}` document (see `BudgetRepository` for why the field
/// lives on the document rather than in a subcollection).
///
/// Both the planner screen and the dashboard's Budget tile read this same
/// store, so the two screens can never disagree.
class BudgetPlan {
  const BudgetPlan({
    required this.budgetRm,
    required this.room,
    required this.ecoFriendly,
    required this.updatedAt,
  });

  /// Total budget in whole ringgit. 0 means "entered as zero / cleared" —
  /// a plan that was never saved at all is represented by `null` at the
  /// provider level, never by a fabricated number.
  final int budgetRm;

  /// The room currently being planned (one of [budgetRooms]).
  final String room;

  /// Whether the estimate should only price from eco-friendly listings.
  final bool ecoFriendly;

  final DateTime updatedAt;

  factory BudgetPlan.fromJson(Map<String, dynamic> json) {
    final room = json['room']?.toString().trim() ?? '';
    return BudgetPlan(
      // Tolerates int, double or string-encoded values (mirrors how
      // Product.fromJson treats price).
      budgetRm: (json['budgetRm'] is num)
          ? (json['budgetRm'] as num).toInt()
          : int.tryParse(json['budgetRm']?.toString() ?? '') ?? 0,
      // Unknown/missing rooms fall back to the default so a stale document
      // can never put an invalid value into the dropdown.
      room: budgetRooms.contains(room) ? room : defaultBudgetRoom,
      ecoFriendly: json['ecoFriendly'] == true,
      // Missing timestamp → epoch (honest "unknown"), never "now".
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'budgetRm': budgetRm,
        'room': room,
        'ecoFriendly': ecoFriendly,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}
