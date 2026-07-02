import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/glass_card.dart';
import '../../models/subscription_model.dart';
import '../../services/subscription_service.dart';
import 'subscription_plans_bottom_sheet.dart';

class SubscriptionCardWidget extends StatelessWidget {
  final VoidCallback? onActionPressed;

  const SubscriptionCardWidget({super.key, this.onActionPressed});

  String _statusLabel(SubscriptionStatusType status) {
    switch (status) {
      case SubscriptionStatusType.freeTrial:
        return 'Free Trial';
      case SubscriptionStatusType.active:
        return 'Active';
      case SubscriptionStatusType.expired:
        return 'Expired';
      case SubscriptionStatusType.blocked:
        return 'Blocked';
      case SubscriptionStatusType.unknown:
        return 'Inactive';
    }
  }

  Color _statusColor(SubscriptionStatusType status) {
    switch (status) {
      case SubscriptionStatusType.freeTrial:
        return AppColors.accentYellow;
      case SubscriptionStatusType.active:
        return AppColors.secondary;
      case SubscriptionStatusType.expired:
        return AppColors.accentYellow;
      case SubscriptionStatusType.blocked:
        return AppColors.accentRed;
      case SubscriptionStatusType.unknown:
        return AppColors.textGrey;
    }
  }

  String _actionLabel(SubscriptionStatusType status) {
    return 'View Plans';
  }

  @override
  Widget build(BuildContext context) {
    final service = SubscriptionService.instance;
    final subscription = service.subscription;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final text = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final sub = isDark ? AppColors.textLight : AppColors.textGrey;

    if (service.isLoadingSubscription && subscription == null) {
      return GlassCard(
        borderRadius: BorderRadius.circular(20),
        color: surface,
        padding: const EdgeInsets.all(24),
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (subscription == null) {
      return GlassCard(
        borderRadius: BorderRadius.circular(20),
        color: surface,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'KM Subscription',
              style: AppTextStyles.heading.copyWith(fontSize: 16, color: text),
            ),
            const SizedBox(height: 8),
            Text(
              service.lastError ?? 'Could not load subscription.',
              style: TextStyle(color: sub, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => service.fetchSubscription(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final status = subscription.status;
    // Always use backend values for display
    final remaining = subscription.kmRemaining;
    final limit = subscription.kmLimit;
    final used = subscription.kmUsed;
    final progress = (limit != null && limit > 0)
        ? (used / limit).clamp(0.0, 1.0)
        : null;
    return GlassCard(
      borderRadius: BorderRadius.circular(20),
      color: surface,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  subscription.planName,
                  style: AppTextStyles.heading.copyWith(
                    fontSize: 18,
                    color: text,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(status).withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    color: _statusColor(status),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Unlimited plan active → green banner ──────────────────────────
          if (subscription.isUnlimitedActive) ...[
            _UnlimitedActiveBanner(expiry: subscription.unlimitedExpiry),
          ] else ...[
            // ── Normal KM display ─────────────────────────────────────────
            Text(
              '${remaining.toStringAsFixed(1)} km remaining',
              style: TextStyle(
                color: text,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Remaining km from your subscription',
              style: TextStyle(color: sub, fontSize: 12),
            ),
            if (progress != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  color: progress > 0.85
                      ? AppColors.accentRed
                      : AppColors.secondary,
                ),
              ),
            ],
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  onActionPressed ??
                  () => SubscriptionPlansBottomSheet.show(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _actionLabel(status),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Green banner shown when isUnlimitedActive == true
// ─────────────────────────────────────────────────────────────────────────────
class _UnlimitedActiveBanner extends StatelessWidget {
  final DateTime? expiry;
  const _UnlimitedActiveBanner({this.expiry});

  /// Formats the expiry date as "17th June", "3rd July", etc.
  String _formatExpiry(DateTime dt) {
    final day = dt.toLocal().day;
    final suffix = _daySuffix(day);
    final month = DateFormat('MMMM').format(dt.toLocal());
    return '$day$suffix $month';
  }

  String _daySuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = expiry != null
        ? 'Unlimited Plan Active until ${_formatExpiry(expiry!)}'
        : 'Unlimited Plan Active';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.secondary.withAlpha(220),
            AppColors.secondary.withAlpha(180),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withAlpha(70),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.all_inclusive_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
        ],
      ),
    );
  }
}
