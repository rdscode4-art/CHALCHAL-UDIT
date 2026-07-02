import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class DriverAboutScreen extends StatelessWidget {
  const DriverAboutScreen({super.key});

  static const List<_BenefitItem> _benefits = [
    _BenefitItem(
      icon: Icons.schedule_rounded,
      label: 'Flexible Working Hours',
      color: Color(0xFF5C6BC0),
    ),
    _BenefitItem(
      icon: Icons.bolt_rounded,
      label: 'Fast Ride Matching',
      color: AppColors.accentYellow,
    ),
    _BenefitItem(
      icon: Icons.trending_up_rounded,
      label: 'Real-Time Earnings',
      color: AppColors.accentStrong,
    ),
    _BenefitItem(
      icon: Icons.verified_user_rounded,
      label: 'Secure Ride System',
      color: AppColors.secondary,
    ),
    _BenefitItem(
      icon: Icons.map_rounded,
      label: 'Easy Trip Management',
      color: Color(0xFFEF6C00),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffold = isDark ? AppColors.darkBackground : AppColors.background;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final border = isDark ? AppColors.darkBorder : AppColors.border;
    final textPri = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final textSec = isDark
        ? AppColors.darkOnSurface.withAlpha(160)
        : AppColors.textGrey;

    return Scaffold(
      backgroundColor: scaffold,
      body: CustomScrollView(
        slivers: [
          // ── Gradient App Bar ───────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: isDark ? AppColors.darkSurface : AppColors.primary,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF2E3440),
                      Color(0xFF3B4252),
                      Color(0xFF2E7D32),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(24),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.directions_car_rounded,
                                color: AppColors.accentStrong,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Chal Chal Gaadi',
                                  style: AppTextStyles.body.copyWith(
                                    color: Colors.white.withAlpha(200),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'About Us',
                                  style: AppTextStyles.heading.copyWith(
                                    color: Colors.white,
                                    fontSize: 26,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Body Content ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Introduction
                  _IntroCard(
                    surface: surface,
                    border: border,
                    textPri: textPri,
                    textSec: textSec,
                  ),
                  const SizedBox(height: 20),

                  // Mission
                  _MissionVisionCard(
                    icon: Icons.flag_rounded,
                    iconColor: AppColors.accentStrong,
                    title: 'Our Mission',
                    text:
                        'To empower local drivers with reliable ride opportunities and provide a safe transportation experience.',
                    surface: surface,
                    border: border,
                    textPri: textPri,
                    textSec: textSec,
                  ),
                  const SizedBox(height: 14),

                  // Vision
                  _MissionVisionCard(
                    icon: Icons.visibility_rounded,
                    iconColor: const Color(0xFF5C6BC0),
                    title: 'Our Vision',
                    text:
                        'To build the most trusted and driver-friendly ride booking platform.',
                    surface: surface,
                    border: border,
                    textPri: textPri,
                    textSec: textSec,
                  ),
                  const SizedBox(height: 28),

                  // Driver Benefits
                  _SectionLabel(label: 'Driver Benefits', textSec: textSec),
                  const SizedBox(height: 14),
                  _BenefitsGrid(
                    benefits: _benefits,
                    surface: surface,
                    border: border,
                    textPri: textPri,
                  ),
                  const SizedBox(height: 36),

                  // Footer
                  _Footer(textSec: textSec),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Introduction Card ────────────────────────────────────────────────────────

class _IntroCard extends StatelessWidget {
  final Color surface;
  final Color border;
  final Color textPri;
  final Color textSec;

  const _IntroCard({
    required this.surface,
    required this.border,
    required this.textPri,
    required this.textSec,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accentStrong.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: AppColors.accentStrong,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Chal Chal Gaadi Driver is a smart transportation platform designed to help drivers connect with passengers quickly and efficiently while increasing earning opportunities.',
              style: AppTextStyles.body.copyWith(
                color: textSec,
                fontSize: 14,
                height: 1.65,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mission / Vision Card ────────────────────────────────────────────────────

class _MissionVisionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String text;
  final Color surface;
  final Color border;
  final Color textPri;
  final Color textSec;

  const _MissionVisionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.text,
    required this.surface,
    required this.border,
    required this.textPri,
    required this.textSec,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body.copyWith(
                    color: textPri,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: AppTextStyles.body.copyWith(
                    color: textSec,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Benefits Grid ────────────────────────────────────────────────────────────

class _BenefitItem {
  final IconData icon;
  final String label;
  final Color color;

  const _BenefitItem({
    required this.icon,
    required this.label,
    required this.color,
  });
}

class _BenefitsGrid extends StatelessWidget {
  final List<_BenefitItem> benefits;
  final Color surface;
  final Color border;
  final Color textPri;

  const _BenefitsGrid({
    required this.benefits,
    required this.surface,
    required this.border,
    required this.textPri,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemCount: benefits.length,
      itemBuilder: (_, i) => _BenefitCard(
        item: benefits[i],
        surface: surface,
        border: border,
        textPri: textPri,
      ),
    );
  }
}

class _BenefitCard extends StatelessWidget {
  final _BenefitItem item;
  final Color surface;
  final Color border;
  final Color textPri;

  const _BenefitCard({
    required this.item,
    required this.surface,
    required this.border,
    required this.textPri,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: item.color.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, color: item.color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            item.label,
            style: AppTextStyles.body.copyWith(
              color: textPri,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color textSec;

  const _SectionLabel({required this.label, required this.textSec});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: AppTextStyles.body.copyWith(
        color: textSec,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

// ── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final Color textSec;

  const _Footer({required this.textSec});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(color: textSec.withAlpha(40)),
        const SizedBox(height: 16),
        Text(
          '© 2026 Chal Chal Gaadi Driver.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(
            color: textSec,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'All Rights Reserved.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(
            color: textSec.withAlpha(160),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
