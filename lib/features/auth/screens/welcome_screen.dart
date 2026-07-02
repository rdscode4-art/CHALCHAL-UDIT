import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/localization/app_localizations.dart';
import 'user_auth_screen.dart';
import 'driver_auth_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkSurface : AppColors.surface;
    final textColor = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final subColor = isDark
        ? AppColors.darkOnSurface.withValues(alpha: 0.65)
        : AppColors.textGrey;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Theme and Language toggle row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ValueListenableBuilder<Locale>(
                      valueListenable: LanguageManager.localeNotifier,
                      builder: (ctx, locale, _) {
                        final isHindi = locale.languageCode == 'hi';
                        return TextButton.icon(
                          onPressed: () {
                            LanguageManager.setLocale(
                              isHindi ? const Locale('en') : const Locale('hi'),
                            );
                          },
                          icon: const Icon(Icons.translate_rounded, size: 18),
                          label: Text(
                            isHindi ? 'English' : 'हिन्दी',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: textColor,
                          ),
                        );
                      },
                    ),
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: AppTheme.themeMode,
                      builder: (ctx, mode, _) {
                        final dark =
                            mode == ThemeMode.dark ||
                            (mode == ThemeMode.system &&
                                MediaQuery.of(ctx).platformBrightness ==
                                    Brightness.dark);
                        return IconButton(
                          onPressed: AppTheme.toggleMode,
                          icon: Icon(
                            dark
                                ? Icons.wb_sunny_rounded
                                : Icons.nights_stay_rounded,
                          ),
                          color: textColor,
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Hero — charcoal background matching logo
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppColors.darkSurface, // #2E3440 — exact logo bg
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(36),
                    bottomRight: Radius.circular(36),
                  ),
                ),
                child: Stack(
                  children: [
                    // Subtle decorative circles using logo colours
                    Positioned(
                      right: -16,
                      top: 16,
                      child: _decorCircle(
                        110,
                        AppColors.accentYellow.withValues(alpha: 0.06),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      bottom: 20,
                      child: _decorCircle(
                        80,
                        AppColors.accentStrong.withValues(alpha: 0.07),
                      ),
                    ),
                    Positioned(
                      left: -10,
                      top: 60,
                      child: _decorCircle(
                        60,
                        AppColors.accentRed.withValues(alpha: 0.05),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                      child: Column(
                        children: [
                          // Logo centred
                          Center(
                            child: ChalChalGadiLogo(
                              size: MediaQuery.of(context).size.width * 0.54,
                            ),
                          ),
                          const SizedBox(height: 28),
                          // Feature badges using logo traffic-light colours
                          Row(
                            children: [
                              _FeatureBadge(
                                icon: Icons.flash_on_rounded,
                                label: context.tr('fastBooking'),
                                color: AppColors.accentYellow,
                              ),
                              const SizedBox(width: 10),
                              _FeatureBadge(
                                icon: Icons.shield_rounded,
                                label: context.tr('secureTrips'),
                                color: AppColors.accentStrong,
                              ),
                              const SizedBox(width: 10),
                              _FeatureBadge(
                                icon: Icons.location_on_rounded,
                                label: context.tr('liveTracking'),
                                color: AppColors.accentRed,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Action card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.border,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.3 : 0.07,
                        ),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Small logo-colour accent bar
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppColors.accentStrong,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            context.tr('readyToRide'),
                            style: AppTextStyles.heading.copyWith(
                              fontSize: 22,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.tr('riderProfile'),
                        style: AppTextStyles.body.copyWith(color: subColor),
                      ),
                      const SizedBox(height: 24),

                      // Rider button — green (logo green dot)
                      CustomButton(
                        label: context.tr('imRider'),
                        color: AppColors.accentStrong,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UserAuthScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Driver button — outlined charcoal/yellow
                      CustomButton(
                        label: context.tr('imDriver'),
                        isOutlined: true,
                        color: AppColors.accentStrong,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DriverAuthScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _decorCircle(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _FeatureBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _FeatureBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
