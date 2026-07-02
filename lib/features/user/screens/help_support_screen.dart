import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  // Tracks which FAQ item is expanded
  int? _expandedFaq;

  static const List<Map<String, String>> _faqs = [
    {
      'q': 'How do I book a ride?',
      'a':
          'Enter pickup and drop location, choose ride type, and confirm booking.',
    },
    {
      'q': 'How can I cancel a ride?',
      'a':
          'Open ride details and tap the cancel button before the ride starts.',
    },
    {
      'q': 'How do drivers receive payments?',
      'a': 'Payments are transferred directly to the registered account.',
    },
    {
      'q': 'What if I lose an item in a ride?',
      'a': 'Contact support immediately with your ride details.',
    },
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
    final accent = AppColors.accentStrong;
    final red = AppColors.accentRed;

    return Scaffold(
      backgroundColor: scaffold,
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: surface,
        foregroundColor: textPri,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
        children: [
          // ── Header ──────────────────────────────────────────────────────
          _SectionHeader(
            icon: Icons.support_agent_rounded,
            iconColor: accent,
            title: 'Help & Support',
            subtitle: "We're here to help you anytime.",
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
          ),
          const SizedBox(height: 20),

          // ── Contact Support ──────────────────────────────────────────────
          _sectionLabel('Contact Support', textSec),
          const SizedBox(height: 10),
          _ContactCard(
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            accent: accent,
          ),
          const SizedBox(height: 24),

          // ── FAQ ──────────────────────────────────────────────────────────
          _sectionLabel('Frequently Asked Questions', textSec),
          const SizedBox(height: 10),
          _FaqCard(
            faqs: _faqs,
            expandedIndex: _expandedFaq,
            onToggle: (i) =>
                setState(() => _expandedFaq = _expandedFaq == i ? null : i),
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            accent: accent,
          ),
          const SizedBox(height: 24),

          // ── Emergency ────────────────────────────────────────────────────
          _sectionLabel('Emergency Support', textSec),
          const SizedBox(height: 10),
          _EmergencyCard(
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            red: red,
          ),
          const SizedBox(height: 32),

          // ── Footer ───────────────────────────────────────────────────────
          _Footer(textSec: textSec),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, Color color) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      label,
      style: AppTextStyles.heading.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.4,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Header card
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color surface, border, textPri, textSec;

  const _SectionHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.surface,
    required this.border,
    required this.textPri,
    required this.textSec,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: iconColor.withAlpha(20),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.heading.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textPri,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    color: textSec,
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
// Contact support card
// ─────────────────────────────────────────────────────────────────────────────
class _ContactCard extends StatelessWidget {
  final Color surface, border, textPri, textSec, accent;

  const _ContactCard({
    required this.surface,
    required this.border,
    required this.textPri,
    required this.textSec,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Column(
        children: [
          _ContactRow(
            icon: Icons.email_outlined,
            iconColor: accent,
            label: 'Customer Support Email',
            value: 'support@chalchalgaadi.com',
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            showDivider: true,
          ),
          _ContactRow(
            icon: Icons.phone_outlined,
            iconColor: accent,
            label: 'Phone Number',
            value: '+91 98765 43210',
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            showDivider: true,
          ),
          _ContactRow(
            icon: Icons.access_time_rounded,
            iconColor: accent,
            label: 'Support Hours',
            value: 'Monday to Sunday, 8:00 AM – 10:00 PM',
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color surface, border, textPri, textSec;
  final bool showDivider;

  const _ContactRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.surface,
    required this.border,
    required this.textPri,
    required this.textSec,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 11,
                        color: textSec,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 14,
                        color: textPri,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: border.withAlpha(80)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAQ card with expandable items
// ─────────────────────────────────────────────────────────────────────────────
class _FaqCard extends StatelessWidget {
  final List<Map<String, String>> faqs;
  final int? expandedIndex;
  final ValueChanged<int> onToggle;
  final Color surface, border, textPri, textSec, accent;

  const _FaqCard({
    required this.faqs,
    required this.expandedIndex,
    required this.onToggle,
    required this.surface,
    required this.border,
    required this.textPri,
    required this.textSec,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Column(
        children: List.generate(faqs.length, (i) {
          final isExpanded = expandedIndex == i;
          final isLast = i == faqs.length - 1;
          return Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? const Radius.circular(20) : Radius.zero,
                  bottom: isLast && !isExpanded
                      ? const Radius.circular(20)
                      : Radius.zero,
                ),
                onTap: () => onToggle(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: accent.withAlpha(18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Q',
                          style: AppTextStyles.body.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          faqs[i]['q']!,
                          style: AppTextStyles.body.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPri,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: textSec,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withAlpha(30)),
                  ),
                  child: Text(
                    faqs[i]['a']!,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      color: textPri,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Divider(height: 1, thickness: 1, color: border.withAlpha(80)),
            ],
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Emergency card
// ─────────────────────────────────────────────────────────────────────────────
class _EmergencyCard extends StatelessWidget {
  final Color surface, border, textPri, textSec, red;

  const _EmergencyCard({
    required this.surface,
    required this.border,
    required this.textPri,
    required this.textSec,
    required this.red,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: red.withAlpha(12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: red.withAlpha(60)),
        boxShadow: [
          BoxShadow(
            color: red.withAlpha(20),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: red.withAlpha(20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.emergency_rounded, color: red, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Emergency Helpline',
                  style: AppTextStyles.body.copyWith(
                    fontSize: 11,
                    color: red.withAlpha(180),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '112',
                  style: AppTextStyles.heading.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: red,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'In case of emergency, contact local authorities immediately.',
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    color: textPri,
                    height: 1.5,
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
// Footer
// ─────────────────────────────────────────────────────────────────────────────
class _Footer extends StatelessWidget {
  final Color textSec;

  const _Footer({required this.textSec});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(color: textSec.withAlpha(40)),
        const SizedBox(height: 12),
        Text(
          'Chal Chal Gaadi v1.0',
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textSec,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Thank you for using Chal Chal Gaadi.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(fontSize: 12, color: textSec),
        ),
      ],
    );
  }
}
