import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class DriverPrivacyPolicyScreen extends StatelessWidget {
  const DriverPrivacyPolicyScreen({super.key});

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
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: surface,
        foregroundColor: textPri,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
        children: [
          // Last updated badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentStrong.withAlpha(20),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.update_rounded,
                      size: 13,
                      color: AppColors.accentStrong,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Last Updated: June 2026',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.accentStrong,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 1. Introduction
          _PolicyCard(
            icon: Icons.shield_outlined,
            iconColor: AppColors.accentStrong,
            title: 'Introduction',
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            child: _BodyText(
              text:
                  'Chal Chal Gaadi Driver values driver privacy and is committed to protecting personal information.',
              textSec: textSec,
            ),
          ),
          const SizedBox(height: 14),

          // 2. Information We Collect
          _PolicyCard(
            icon: Icons.folder_open_rounded,
            iconColor: const Color(0xFF5C6BC0),
            title: 'Information We Collect',
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            child: _BulletList(
              items: const [
                'Driver Name',
                'Phone Number',
                'Email Address',
                'Live Location',
                'Vehicle Details',
                'Driving License Information',
                'Trip History',
                'Device Information',
              ],
              textSec: textSec,
            ),
          ),
          const SizedBox(height: 14),

          // 3. How Information Is Used
          _PolicyCard(
            icon: Icons.settings_applications_rounded,
            iconColor: const Color(0xFFEF6C00),
            title: 'How Information Is Used',
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            child: _BulletList(
              items: const [
                'To provide ride services',
                'To verify driver identity',
                'To improve app performance',
                'To ensure safety and security',
                'To process earnings and ride activity',
              ],
              textSec: textSec,
            ),
          ),
          const SizedBox(height: 14),

          // 4. Location Access
          _PolicyCard(
            icon: Icons.location_on_outlined,
            iconColor: AppColors.accentRed,
            title: 'Location Access',
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            child: _BodyText(
              text:
                  'Driver location is used for ride matching, navigation, and live tracking purposes.',
              textSec: textSec,
            ),
          ),
          const SizedBox(height: 14),

          // 5. Data Security
          _PolicyCard(
            icon: Icons.lock_outline_rounded,
            iconColor: AppColors.secondary,
            title: 'Data Security',
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            child: _BodyText(
              text:
                  'We use secure systems and encryption practices to protect driver data.',
              textSec: textSec,
            ),
          ),
          const SizedBox(height: 14),

          // 6. Third-Party Services
          _PolicyCard(
            icon: Icons.account_tree_outlined,
            iconColor: const Color(0xFF5C6BC0),
            title: 'Third-Party Services',
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            child: _BodyText(
              text:
                  'The app may use trusted third-party services such as maps and payment systems.',
              textSec: textSec,
            ),
          ),
          const SizedBox(height: 14),

          // 7. Driver Rights
          _PolicyCard(
            icon: Icons.how_to_reg_rounded,
            iconColor: AppColors.accentStrong,
            title: 'Driver Rights',
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            child: _BulletList(
              items: const [
                'Access account data',
                'Update personal information',
                'Request account removal',
              ],
              textSec: textSec,
            ),
          ),
          const SizedBox(height: 14),

          // 8. Contact Information
          _PolicyCard(
            icon: Icons.email_outlined,
            iconColor: const Color(0xFFEF6C00),
            title: 'Contact Information',
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            child: Row(
              children: [
                const Icon(
                  Icons.alternate_email_rounded,
                  size: 15,
                  color: AppColors.accentStrong,
                ),
                const SizedBox(width: 8),
                Text(
                  'privacy@chalchalgaadi.com',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.accentStrong,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.accentStrong.withAlpha(12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.accentStrong.withAlpha(40)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppColors.accentStrong,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'By using Chal Chal Gaadi Driver, you agree to this Privacy Policy.',
                    style: AppTextStyles.body.copyWith(
                      color: textSec,
                      fontSize: 13,
                      height: 1.55,
                    ),
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

// ── Policy Card ──────────────────────────────────────────────────────────────

class _PolicyCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;
  final Color surface;
  final Color border;
  final Color textPri;
  final Color textSec;

  const _PolicyCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    required this.surface,
    required this.border,
    required this.textPri,
    required this.textSec,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 17),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: AppTextStyles.body.copyWith(
                  color: textPri,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: border),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Body Text ────────────────────────────────────────────────────────────────

class _BodyText extends StatelessWidget {
  final String text;
  final Color textSec;

  const _BodyText({required this.text, required this.textSec});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.body.copyWith(
        color: textSec,
        fontSize: 13,
        height: 1.65,
      ),
    );
  }
}

// ── Bullet List ──────────────────────────────────────────────────────────────

class _BulletList extends StatelessWidget {
  final List<String> items;
  final Color textSec;

  const _BulletList({required this.items, required this.textSec});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.accentStrong,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: AppTextStyles.body.copyWith(
                        color: textSec,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
