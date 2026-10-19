const budgetRooms = ['Kitchen', 'Living Room', 'Bedroom', 'Bathroom'];

const defaultBudgetRoom = 'Kitchen';

class BudgetPlan {
  const BudgetPlan({
    required this.budgetRm,
    required this.room,
    required this.ecoFriendly,
    required this.updatedAt,
  });

  final int budgetRm;

  final String room;

  final bool ecoFriendly;

  final DateTime updatedAt;

  factory BudgetPlan.fromJson(Map<String, dynamic> json) {
    final room = json['room']?.toString().trim() ?? '';
    return BudgetPlan(
      budgetRm: (json['budgetRm'] is num)
          ? (json['budgetRm'] as num).toInt()
          : int.tryParse(json['budgetRm']?.toString() ?? '') ?? 0,
      room: budgetRooms.contains(room) ? room : defaultBudgetRoom,
      ecoFriendly: json['ecoFriendly'] == true,
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
