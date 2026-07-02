import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  static const _features = [
    (
      Icons.book_online_rounded,
      'Easy Ride Booking',
      'Book rides in seconds with just pickup and drop.',
    ),
    (
      Icons.location_on_rounded,
      'Live Ride Tracking',
      'Track your ride in real-time on the map.',
    ),
    (
      Icons.verified_user_rounded,
      'Secure Driver Verification',
      'Every driver is verified before joining the platform.',
    ),
    (
      Icons.currency_rupee_rounded,
      'Affordable Pricing',
      'Competitive fares with no hidden charges.',
    ),
    (
      Icons.electric_bolt_rounded,
      'Fast Pickup Service',
      'Nearby drivers reach you quickly.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffold = isDark ? AppColors.darkBackground : AppColors.background;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final cardSoft = isDark ? AppColors.darkSurfaceSoft : AppColors.surfaceSoft;
    final border = isDark ? AppColors.darkBorder : AppColors.border;
    final textPri = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final textSec = isDark
        ? AppColors.darkOnSurface.withAlpha(160)
        : AppColors.textGrey;
    final accent = AppColors.accentStrong;

    return Scaffold(
      backgroundColor: scaffold,
      body: CustomScrollView(
        slivers: [
          // ── Gradient header ────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: accent,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(
                left: 20,
                bottom: 16,
                right: 20,
              ),
              title: Text(
                'About Us',
                style: AppTextStyles.heading.copyWith(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent,
                      accent.withAlpha(200),
                      AppColors.accentYellow.withAlpha(180),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    // Decorative circles
                    Positioned(
                      top: -30,
                      right: -30,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(18),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: -40,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(12),
                        ),
                      ),
                    ),
                    // Logo / icon
                    Positioned(
                      top: 48,
                      right: 28,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.electric_rickshaw_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Company Introduction ─────────────────────────────────
                _InfoCard(
                  icon: Icons.info_outline_rounded,
                  iconColor: accent,
                  title: 'Chal Chal Gaadi',
                  body:
                      'Chal Chal Gaadi is a smart local transportation platform '
                      'designed to provide safe, affordable, and reliable rides '
                      'for everyone. Our mission is to simplify daily travel and '
                      'empower local drivers with better earning opportunities.',
                  surface: surface,
                  border: border,
                  textPri: textPri,
                  textSec: textSec,
                ),
                const SizedBox(height: 16),

                // ── Mission ──────────────────────────────────────────────
                _InfoCard(
                  icon: Icons.flag_rounded,
                  iconColor: AppColors.accentYellow,
                  title: 'Our Mission',
                  body:
                      'To make local transportation accessible, convenient, and '
                      'secure for every passenger and driver.',
                  surface: surface,
                  border: border,
                  textPri: textPri,
                  textSec: textSec,
                ),
                const SizedBox(height: 16),

                // ── Vision ───────────────────────────────────────────────
                _InfoCard(
                  icon: Icons.visibility_rounded,
                  iconColor: Colors.deepPurpleAccent,
                  title: 'Our Vision',
                  body:
                      'To become the most trusted ride booking platform for '
                      'local communities.',
                  surface: surface,
                  border: border,
                  textPri: textPri,
                  textSec: textSec,
                ),
                const SizedBox(height: 24),

                // ── Features heading ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 12),
                  child: Text(
                    'What We Offer',
                    style: AppTextStyles.heading.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textPri,
                    ),
                  ),
                ),

                // ── Feature cards grid ───────────────────────────────────
                ...AboutUsScreen._features.map(
                  (f) => _FeatureRow(
                    icon: f.$1,
                    title: f.$2,
                    subtitle: f.$3,
                    cardSoft: cardSoft,
                    border: border,
                    textPri: textPri,
                    textSec: textSec,
                    accent: accent,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Developer info ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(14),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withAlpha(40)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.code_rounded, color: accent, size: 24),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Developed with dedication to improve local '
                          'transportation experience.',
                          style: AppTextStyles.body.copyWith(
                            fontSize: 13,
                            color: textPri,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // ── Footer ───────────────────────────────────────────────
                Divider(color: border),
                const SizedBox(height: 12),
                Text(
                  '© 2026 Chal Chal Gaadi. All Rights Reserved.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12,
                    color: textSec,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 11,
                    color: textSec.withAlpha(160),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable info card (intro / mission / vision)
// ─────────────────────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final Color surface, border, textPri, textSec;

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: iconColor.withAlpha(18),
              borderRadius: BorderRadius.circular(14),
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
                  style: AppTextStyles.heading.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: textPri,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    color: textSec,
                    height: 1.55,
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

// ─────────────────────────────────────────────────────────────────────────────
// Feature row card
// ─────────────────────────────────────────────────────────────────────────────
class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color cardSoft, border, textPri, textSec, accent;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cardSoft,
    required this.border,
    required this.textPri,
    required this.textSec,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withAlpha(18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPri,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12,
                    color: textSec,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle_rounded,
            color: accent.withAlpha(160),
            size: 18,
          ),
        ],
      ),
    );
  }
}
