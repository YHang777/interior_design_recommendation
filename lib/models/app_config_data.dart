class MembershipTier {
  final String name;
  final int discountPercent;
  final int minOrders;

  const MembershipTier({
    required this.name,
    required this.discountPercent,
    required this.minOrders,
  });

  factory MembershipTier.fromJson(Map<String, dynamic> json) {
    return MembershipTier(
      name: json['name']?.toString() ?? 'Free',
      discountPercent: (json['discountPercent'] as num?)?.toInt() ?? 0,
      minOrders: (json['minOrders'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'discountPercent': discountPercent,
        'minOrders': minOrders,
      };
}

class AppConfigData {
  final String currency;
  final double taxRate;
  final List<MembershipTier> membershipTiers;

  const AppConfigData({
    required this.currency,
    required this.taxRate,
    required this.membershipTiers,
  });

  MembershipTier tierForOrderCount(int orderCount) {
    if (membershipTiers.isEmpty) {
      return const MembershipTier(
          name: 'Free', discountPercent: 0, minOrders: 0);
    }
    final sorted = [...membershipTiers]
      ..sort((a, b) => a.minOrders.compareTo(b.minOrders));
    for (var i = sorted.length - 1; i >= 0; i--) {
      if (orderCount >= sorted[i].minOrders) return sorted[i];
    }
    return sorted.first;
  }

  factory AppConfigData.fromJson(Map<String, dynamic> json) {
    return AppConfigData(
      currency: json['currency']?.toString() ?? 'MYR',
      taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0.06,
      membershipTiers: (json['membershipTiers'] as List<dynamic>?)
              ?.map((e) =>
                  MembershipTier.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  AppConfigData copyWith({double? taxRate}) => AppConfigData(
        currency: currency,
        taxRate: taxRate ?? this.taxRate,
        membershipTiers: membershipTiers,
      );

  Map<String, dynamic> toJson() => {
        'currency': currency,
        'taxRate': taxRate,
        'membershipTiers':
            membershipTiers.map((t) => t.toJson()).toList(),
      };
}
