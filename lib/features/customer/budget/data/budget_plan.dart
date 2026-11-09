// Legacy room types — kept only so old plans migrate to the total budget.
const budgetRooms = ['Kitchen', 'Living Room', 'Bedroom', 'Bathroom'];

const defaultBudgetRoom = 'Whole home';

// The budget is either the total or scoped to a saved design (label plus
// designId); anything without a designId — legacy room types included —
// collapses to the total.
String budgetLabelOf(String room, String designId) {
  final label = room.trim();
  if (designId.trim().isEmpty) return defaultBudgetRoom;
  return label.isEmpty ? defaultBudgetRoom : label;
}

class BudgetPlan {
  const BudgetPlan({
    required this.budgetRm,
    required this.room,
    required this.ecoFriendly,
    required this.updatedAt,
    this.choices = const {},
    this.designId = '',
  });

  final int budgetRm;

  final String room;

  final bool ecoFriendly;

  final DateTime updatedAt;

  final Map<String, String> choices;

  final String designId;

  factory BudgetPlan.fromJson(Map<String, dynamic> json) {
    final room = json['room']?.toString().trim() ?? '';
    final designId = json['designId']?.toString().trim() ?? '';
    return BudgetPlan(
      budgetRm: (json['budgetRm'] is num)
          ? (json['budgetRm'] as num).toInt()
          : int.tryParse(json['budgetRm']?.toString() ?? '') ?? 0,
      room: budgetLabelOf(room, designId),
      ecoFriendly: json['ecoFriendly'] == true,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      choices: _parseChoices(json['choices']),
      designId: designId,
    );
  }

  Map<String, dynamic> toJson() => {
        'budgetRm': budgetRm,
        'room': room,
        'ecoFriendly': ecoFriendly,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'choices': choices,
        'designId': designId,
      };
}

// Old plans predate choices; anything malformed drops to no choices.
Map<String, String> _parseChoices(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, String>{};
  for (final entry in raw.entries) {
    final key = entry.key.toString().trim();
    final value = entry.value;
    if (key.isEmpty || value is! String || value.trim().isEmpty) continue;
    out[key] = value;
  }
  return out;
}
