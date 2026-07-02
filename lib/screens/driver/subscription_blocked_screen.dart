import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../features/driver/screens/driver_help_center_screen.dart';
import '../../features/driver/screens/driver_home_screen.dart';
import '../../services/subscription_service.dart';
import '../../widgets/driver/subscription_plans_bottom_sheet.dart';

class SubscriptionBlockedScreen extends StatelessWidget {
  const SubscriptionBlockedScreen({super.key});

  Future<void> _onViewPlans(BuildContext context) async {
    await SubscriptionPlansBottomSheet.show(context);
    final service = SubscriptionService.instance;
    await service.fetchSubscription();
    if (!context.mounted) return;
    if (!service.isBlocked) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.background;
    final text = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final sub = isDark ? AppColors.textLight : AppColors.textGrey;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.accentRed.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: AppColors.accentRed,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Rides Paused',
                textAlign: TextAlign.center,
                style: AppTextStyles.heading.copyWith(
                  fontSize: 28,
                  color: text,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your free 300 km is used up. Subscribe to continue accepting rides.',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub, fontSize: 15, height: 1.5),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _onViewPlans(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'View Plans',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DriverHelpCenterScreen(),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppColors.secondary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Contact Admin',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
