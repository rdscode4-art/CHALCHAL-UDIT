import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model for a T&C section
// ─────────────────────────────────────────────────────────────────────────────
class _TcSection {
  final String number;
  final String title;
  final IconData icon;
  // Either a plain string OR a list of bullet strings
  final String? bodyText;
  final List<String>? bullets;

  const _TcSection({
    required this.number,
    required this.title,
    required this.icon,
    this.bodyText,
    this.bullets,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class TermsConditionsScreen extends StatefulWidget {
  const TermsConditionsScreen({super.key});

  @override
  State<TermsConditionsScreen> createState() => _TermsConditionsScreenState();
}

class _TermsConditionsScreenState extends State<TermsConditionsScreen> {
  // null = all collapsed; index = expanded section
  int? _expandedIndex;

  static const _sections = [
    _TcSection(
      number: '1',
      title: 'Acceptance of Terms',
      icon: Icons.handshake_outlined,
      bodyText:
          'By using Chal Chal Gaadi, you agree to follow these terms and conditions.',
    ),
    _TcSection(
      number: '2',
      title: 'User Responsibilities',
      icon: Icons.person_outline_rounded,
      bullets: [
        'Provide accurate information',
        'Maintain account security',
        'Use services lawfully',
      ],
    ),
    _TcSection(
      number: '3',
      title: 'Ride Booking Rules',
      icon: Icons.directions_car_outlined,
      bullets: [
        'Riders should provide correct pickup and drop locations',
        'Drivers may cancel rides in exceptional situations',
        'Misconduct is strictly prohibited',
      ],
    ),
    _TcSection(
      number: '4',
      title: 'Driver Responsibilities',
      icon: Icons.badge_outlined,
      bullets: [
        'Maintain valid documents',
        'Follow traffic rules',
        'Ensure passenger safety',
      ],
    ),
    _TcSection(
      number: '5',
      title: 'Prohibited Activities',
      icon: Icons.block_rounded,
      bullets: [
        'Fake bookings',
        'Harassment',
        'Fraudulent activities',
        'Misuse of the platform',
      ],
    ),
    _TcSection(
      number: '6',
      title: 'Limitation of Liability',
      icon: Icons.gavel_rounded,
      bodyText:
          'Chal Chal Gaadi is not responsible for delays caused by traffic, weather, or unforeseen circumstances.',
    ),
    _TcSection(
      number: '7',
      title: 'Account Suspension',
      icon: Icons.no_accounts_outlined,
      bodyText:
          'We reserve the right to suspend accounts violating platform rules.',
    ),
    _TcSection(
      number: '8',
      title: 'Changes to Terms',
      icon: Icons.edit_note_rounded,
      bodyText: 'Terms may be updated periodically without prior notice.',
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
      appBar: AppBar(
        title: Text(
          'Terms & Conditions',
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
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
            ],
          ),
          const SizedBox(height: 6),

          // Tap hint
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 16),
            child: Text(
              'Tap any section to read more.',
              style: AppTextStyles.body.copyWith(
                fontSize: 12,
                color: textSec.withAlpha(180),
              ),
            ),
          ),

          // Expandable sections
          ...List.generate(_sections.length, (i) {
            final sec = _sections[i];
            final isExpanded = _expandedIndex == i;
            return _ExpandableSection(
              section: sec,
              isExpanded: isExpanded,
              onTap: () =>
                  setState(() => _expandedIndex = isExpanded ? null : i),
              accent: accent,
              surface: surface,
              cardSoft: cardSoft,
              border: border,
              textPri: textPri,
              textSec: textSec,
            );
          }),

          const SizedBox(height: 8),

          // Section 10: Contact
          Container(
            padding: const EdgeInsets.all(16),
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
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '9',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.contact_mail_outlined, color: accent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Contact Information',
                      style: AppTextStyles.heading.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textPri,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withAlpha(35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mail_outline_rounded, color: accent, size: 17),
                      const SizedBox(width: 10),
                      Text(
                        'legal@chalchalgaadi.com',
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Footer
          Divider(color: border),
          const SizedBox(height: 14),
          Text(
            '© 2026 Chal Chal Gaadi. All Rights Reserved.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              fontSize: 12,
              color: textSec,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable section card
// ─────────────────────────────────────────────────────────────────────────────
class _ExpandableSection extends StatelessWidget {
  final _TcSection section;
  final bool isExpanded;
  final VoidCallback onTap;
  final Color accent, surface, cardSoft, border, textPri, textSec;

  const _ExpandableSection({
    required this.section,
    required this.isExpanded,
    required this.onTap,
    required this.accent,
    required this.surface,
    required this.cardSoft,
    required this.border,
    required this.textPri,
    required this.textSec,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: isExpanded ? surface : cardSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isExpanded ? accent.withAlpha(80) : border,
            width: isExpanded ? 1.3 : 1,
          ),
          boxShadow: isExpanded
              ? [
                  BoxShadow(
                    color: accent.withAlpha(18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      // Number badge
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isExpanded ? accent : accent.withAlpha(40),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          section.number,
                          style: TextStyle(
                            color: isExpanded ? Colors.white : accent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Icon
                      Icon(
                        section.icon,
                        color: isExpanded ? accent : textSec,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      // Title
                      Expanded(
                        child: Text(
                          section.title,
                          style: AppTextStyles.body.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPri,
                          ),
                        ),
                      ),
                      // Chevron
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: isExpanded ? accent : textSec,
                          size: 20,
                        ),
                      ),
                    ],
                  ),

                  // Expandable content
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 220),
                    crossFadeState: isExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: accent.withAlpha(30),
                          ),
                          const SizedBox(height: 12),
                          if (section.bodyText != null)
                            Text(
                              section.bodyText!,
                              style: AppTextStyles.body.copyWith(
                                fontSize: 13,
                                color: textSec,
                                height: 1.6,
                              ),
                            )
                          else if (section.bullets != null)
                            ...section.bullets!.map(
                              (b) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: accent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        b,
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
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
