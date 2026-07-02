import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
    final accent = AppColors.accentStrong;

    return Scaffold(
      backgroundColor: scaffold,
      appBar: AppBar(
        title: Text(
          'Privacy Policy',
          style: AppTextStyles.heading.copyWith(fontSize: 18, color: textPri),
        ),
        backgroundColor: surface,
        foregroundColor: textPri,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 36),
        children: [
          // Last updated badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: accent.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withAlpha(40)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.update_rounded, color: accent, size: 15),
                const SizedBox(width: 7),
                Text(
                  'Last Updated: June 2026',
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12,
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 1. Introduction
          _Section(
            number: '1',
            title: 'Introduction',
            accent: accent,
            textPri: textPri,
            surface: surface,
            border: border,
            child: _BodyText(
              'Chal Chal Gaadi values your privacy and is committed to '
              'protecting your personal information.',
              textSec: textSec,
            ),
          ),

          // 2. Information We Collect
          _Section(
            number: '2',
            title: 'Information We Collect',
            accent: accent,
            textPri: textPri,
            surface: surface,
            border: border,
            child: _BulletList(
              items: const [
                'Name',
                'Phone Number',
                'Email Address',
                'Live Location',
                'Ride History',
                'Device Information',
              ],
              accent: accent,
              textSec: textSec,
            ),
          ),

          // 3. How We Use Information
          _Section(
            number: '3',
            title: 'How We Use Information',
            accent: accent,
            textPri: textPri,
            surface: surface,
            border: border,
            child: _BulletList(
              items: const [
                'To provide ride services',
                'To improve app performance',
                'To ensure safety and security',
                'To contact users regarding rides and support',
              ],
              accent: accent,
              textSec: textSec,
            ),
          ),

          // 4. Location Usage
          _Section(
            number: '4',
            title: 'Location Usage',
            accent: accent,
            textPri: textPri,
            surface: surface,
            border: border,
            child: _BodyText(
              'Location access is used only for ride booking, driver matching, '
              'and live tracking purposes.',
              textSec: textSec,
            ),
          ),

          // 5. Data Security
          _Section(
            number: '5',
            title: 'Data Security',
            accent: accent,
            textPri: textPri,
            surface: surface,
            border: border,
            child: _BodyText(
              'We use secure technologies and encryption practices to protect '
              'user data.',
              textSec: textSec,
            ),
          ),

          // 6. Third-Party Services
          _Section(
            number: '6',
            title: 'Third-Party Services',
            accent: accent,
            textPri: textPri,
            surface: surface,
            border: border,
            child: _BodyText(
              'The app may use trusted third-party services such as maps and '
              'payment providers.',
              textSec: textSec,
            ),
          ),

          // 7. User Rights
          _Section(
            number: '7',
            title: 'Your Rights',
            accent: accent,
            textPri: textPri,
            surface: surface,
            border: border,
            child: _BulletList(
              items: const [
                'Access personal data',
                'Update profile information',
                'Request account deletion',
              ],
              accent: accent,
              textSec: textSec,
            ),
          ),

          // 8. Contact Information
          _Section(
            number: '8',
            title: 'Contact Information',
            accent: accent,
            textPri: textPri,
            surface: surface,
            border: border,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accent.withAlpha(12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withAlpha(35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.mail_outline_rounded, color: accent, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'privacy@chalchalgaadi.com',
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Footer
          Divider(color: border),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Text(
              'By using Chal Chal Gaadi, you agree to this Privacy Policy.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                fontSize: 13,
                color: textSec,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Numbered section wrapper
// ─────────────────────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final String number;
  final String title;
  final Widget child;
  final Color accent, textPri, surface, border;

  const _Section({
    required this.number,
    required this.title,
    required this.child,
    required this.accent,
    required this.textPri,
    required this.surface,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: accent.withAlpha(12),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: AppTextStyles.heading.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: textPri,
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plain body text
// ─────────────────────────────────────────────────────────────────────────────
class _BodyText extends StatelessWidget {
  final String text;
  final Color textSec;

  const _BodyText(this.text, {required this.textSec});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.body.copyWith(
        fontSize: 13,
        color: textSec,
        height: 1.6,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bullet list
// ─────────────────────────────────────────────────────────────────────────────
class _BulletList extends StatelessWidget {
  final List<String> items;
  final Color accent, textSec;

  const _BulletList({
    required this.items,
    required this.accent,
    required this.textSec,
  });

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
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        color: textSec,
                        height: 1.5,
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
