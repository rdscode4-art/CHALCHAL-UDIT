/// Driver subscription status from `GET /api/driver/subscription/`.
enum SubscriptionStatusType {
  freeTrial,
  active,
  expired,
  blocked,
  unknown;

  static SubscriptionStatusType fromApi(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'free_trial':
        return SubscriptionStatusType.freeTrial;
      case 'active':
        return SubscriptionStatusType.active;
      case 'expired':
        return SubscriptionStatusType.expired;
      case 'blocked':
        return SubscriptionStatusType.blocked;
      default:
        return SubscriptionStatusType.unknown;
    }
  }

  bool get isBlocked => this == SubscriptionStatusType.blocked;
}

class SubscriptionModel {
  final SubscriptionStatusType status;
  final double kmRemaining;
  final double kmUsed;
  final double? kmLimit;
  final String planName;
  final String? validity;

  /// True when the driver has an active unlimited-KM plan right now.
  final bool isUnlimitedActive;

  /// Expiry datetime of the unlimited plan (null when not applicable).
  final DateTime? unlimitedExpiry;

  /// Total KMs purchased (from backend `totalPurchasedKm`).
  final int? totalPurchasedKm;

  const SubscriptionModel({
    required this.status,
    required this.kmRemaining,
    required this.kmUsed,
    required this.kmLimit,
    required this.planName,
    this.validity,
    this.isUnlimitedActive = false,
    this.unlimitedExpiry,
    this.totalPurchasedKm,
  });

  bool get isUnlimited => kmLimit == null || isUnlimitedActive;

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    final nested = json['subscription'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(json['subscription'] as Map)
        : json['data'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;

    final limitRaw =
        nested['km_limit'] ?? nested['kmLimit'] ?? nested['totalPurchasedKm'];
    double? limit = limitRaw == null
        ? null
        : _toDouble(limitRaw, fallback: null);

    final double remaining = _toDouble(
      nested['km_remaining'] ?? nested['kmRemaining'] ?? nested['remainingKm'],
    );

    final valPeriod =
        nested['validity'] ??
        nested['validityPeriod'] ??
        nested['duration'];

    // ── Unlimited plan fields ──────────────────────────────────────────────
    final rawUnlimited =
        nested['isUnlimitedActive'] ?? nested['is_unlimited_active'];
    final bool isUnlimitedActive =
        rawUnlimited == true ||
        rawUnlimited?.toString().toLowerCase() == 'true';

    DateTime? unlimitedExpiry;
    final rawExpiry =
        nested['unlimitedExpiry'] ??
        nested['unlimited_expiry'] ??
        nested['unlimitedExpiresAt'];
    if (rawExpiry != null) {
      unlimitedExpiry = DateTime.tryParse(rawExpiry.toString());
    }

    final rawTotalKm =
        nested['totalPurchasedKm'] ?? nested['total_purchased_km'];
    final int? totalPurchasedKm = rawTotalKm == null
        ? null
        : (rawTotalKm is int
              ? rawTotalKm
              : int.tryParse(rawTotalKm.toString()));

    return SubscriptionModel(
      status: SubscriptionStatusType.fromApi(
        nested['status']?.toString() ?? 'active',
      ),
      kmRemaining: remaining,
      kmUsed: _toDouble(nested['km_used'] ?? nested['kmUsed']),
      kmLimit: isUnlimitedActive ? null : limit,
      planName:
          (nested['plan_name'] ??
                  nested['planName'] ??
                  nested['plan'] ??
                  'Subscription')
              .toString(),
      validity: valPeriod?.toString(),
      isUnlimitedActive: isUnlimitedActive,
      unlimitedExpiry: unlimitedExpiry,
      totalPurchasedKm: totalPurchasedKm,
    );
  }

  static double _toDouble(dynamic value, {double? fallback = 0}) {
    if (value == null) return fallback ?? 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? (fallback ?? 0);
  }
}

/// Plan item from `GET /drivers/subscription-plans`.
class SubscriptionPlanItem {
  final String id;
  final String name;
  final double price;
  final double? kmLimit;
  final bool isActive;
  final String? validity;

  /// Backend field: "unlimited" or "limited"
  final String? planType;

  /// Validity in days (from backend `validityDays` field)
  final int? validityDays;

  const SubscriptionPlanItem({
    required this.id,
    required this.name,
    required this.price,
    required this.kmLimit,
    this.isActive = true,
    this.validity,
    this.planType,
    this.validityDays,
  });

  bool get isUnlimited =>
      kmLimit == null || planType?.toLowerCase() == 'unlimited';

  bool get isProPlan => name.toLowerCase().contains('pro');

  factory SubscriptionPlanItem.fromJson(Map<String, dynamic> json) {
    final kmRaw =
        json['km_limit'] ?? json['kmLimit'] ?? json['km'] ?? json['kmIncluded'];
    final double? kmLimit = kmRaw == null
        ? null
        : SubscriptionModel._toDouble(kmRaw, fallback: null);

    final active = json['active'] ?? json['isActive'];
    final valPeriod =
        json['validity'] ??
        json['validityPeriod'] ??
        json['duration'];

    final rawPlanType =
        json['planType']?.toString() ?? json['plan_type']?.toString();

    final rawValidityDays =
        json['validityDays'] ?? json['validity_days'] ?? json['durationDays'];
    final int? validityDays = rawValidityDays == null
        ? null
        : (rawValidityDays is int
              ? rawValidityDays
              : int.tryParse(rawValidityDays.toString()));

    return SubscriptionPlanItem(
      id: (json['_id'] ?? json['id'] ?? json['planId'] ?? '').toString(),
      name: (json['name'] ?? json['planName'] ?? 'Plan').toString(),
      price: SubscriptionModel._toDouble(json['price'] ?? json['amount']),
      kmLimit: rawPlanType?.toLowerCase() == 'unlimited' ? null : kmLimit,
      isActive: active is bool ? active : true,
      validity: valPeriod.toString(),
      planType: rawPlanType,
      validityDays: validityDays,
    );
  }
}
