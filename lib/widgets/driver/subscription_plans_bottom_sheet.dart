import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/glass_card.dart';
import '../../models/subscription_model.dart';
import '../../services/subscription_service.dart';

class SubscriptionPlansBottomSheet extends StatefulWidget {
  const SubscriptionPlansBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SubscriptionPlansBottomSheet(),
    );
  }

  @override
  State<SubscriptionPlansBottomSheet> createState() =>
      _SubscriptionPlansBottomSheetState();
}

class _SubscriptionPlansBottomSheetState
    extends State<SubscriptionPlansBottomSheet> {
  final _service = SubscriptionService.instance;
  String? _selectingPlanId;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    await _service.fetchPlans();
    if (mounted) setState(() {});
  }

  Future<void> _selectPlan(SubscriptionPlanItem plan) async {
    setState(() => _selectingPlanId = plan.id);
    final ok = await _service.requestPlan(plan.id);
    if (!mounted) return;
    setState(() => _selectingPlanId = null);

    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subscription request submitted successfully.'),
          backgroundColor: AppColors.secondary,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_service.lastError ?? 'Could not request plan.'),
        backgroundColor: AppColors.accentRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final text = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final sub = isDark ? AppColors.textLight : AppColors.textGrey;
    final plans = _service.plans;
    final maxHeight = MediaQuery.of(context).size.height * 0.82;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: sub.withAlpha(80),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose a Plan',
                    style: AppTextStyles.heading.copyWith(
                      fontSize: 20,
                      color: text,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: sub),
                ),
              ],
            ),
          ),
          Flexible(
            child: _service.isLoadingPlans
                ? const Center(child: CircularProgressIndicator())
                : plans.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: sub,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _service.lastError ?? 'No plans available.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: sub),
                          ),
                          TextButton(
                            onPressed: _loadPlans,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: plans.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final plan = plans[index];
                      final selecting = _selectingPlanId == plan.id;
                      final highlight = plan.isProPlan;

                      return GlassCard(
                        borderRadius: BorderRadius.circular(18),
                        color: surface,
                        padding: const EdgeInsets.all(16),
                        border: highlight
                            ? Border.all(
                                color: AppColors.secondary.withAlpha(160),
                                width: 1.5,
                              )
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    plan.name,
                                    style: TextStyle(
                                      color: text,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (highlight)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentStrong.withAlpha(
                                        30,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'Most Popular',
                                      style: TextStyle(
                                        color: AppColors.secondary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '₹${plan.price.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: AppColors.secondary,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // ── KM / validity label ──────────────────────
                            // If planType == "unlimited": show
                            //   "Unlimited KMs for X Days"
                            // Otherwise show normal km count + validity.
                            plan.isUnlimited
                                ? Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.secondary.withAlpha(
                                            25,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: AppColors.secondary
                                                .withAlpha(80),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.all_inclusive_rounded,
                                              size: 14,
                                              color: AppColors.secondary,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              plan.validityDays != null
                                                  ? 'Unlimited KMs for ${plan.validityDays} Days'
                                                  : 'Unlimited KMs',
                                              style: const TextStyle(
                                                color: AppColors.secondary,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Text(
                                        '${plan.kmLimit!.toStringAsFixed(0)} km',
                                        style: TextStyle(
                                          color: sub,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (plan.validity != null && plan.validity!.isNotEmpty && plan.validity != 'null') ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 4,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: sub.withAlpha(120),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.calendar_today_outlined,
                                          size: 12,
                                          color: sub,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          plan.validity!,
                                          style: TextStyle(
                                            color: sub,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: selecting
                                    ? null
                                    : () => _selectPlan(plan),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: highlight
                                      ? AppColors.secondary
                                      : AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  selecting ? 'Processing…' : 'Select',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
