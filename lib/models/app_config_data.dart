/// Membership tier as defined by admin in server config.
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

/// App-wide configuration loaded from server `/config` endpoint.
class AppConfigData {
  final int shippingFee;
  final int freeShippingThreshold;
  final String currency;
  final double taxRate;
  final List<MembershipTier> membershipTiers;

  const AppConfigData({
    required this.shippingFee,
    required this.freeShippingThreshold,
    required this.currency,
    required this.taxRate,
    required this.membershipTiers,
  });

  factory AppConfigData.fromJson(Map<String, dynamic> json) {
    return AppConfigData(
      shippingFee: (json['shippingFee'] as num?)?.toInt() ?? 25,
      freeShippingThreshold:
          (json['freeShippingThreshold'] as num?)?.toInt() ?? 500,
      currency: json['currency']?.toString() ?? 'MYR',
      taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0.06,
      membershipTiers: (json['membershipTiers'] as List<dynamic>?)
              ?.map((e) =>
                  MembershipTier.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'shippingFee': shippingFee,
        'freeShippingThreshold': freeShippingThreshold,
        'currency': currency,
        'taxRate': taxRate,
        'membershipTiers':
            membershipTiers.map((t) => t.toJson()).toList(),
      };
}
