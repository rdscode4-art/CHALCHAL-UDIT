import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class DriverHelpCenterScreen extends StatelessWidget {
  const DriverHelpCenterScreen({super.key});

  static const List<_FaqItem> _faqs = [
    _FaqItem(
      question: 'How do I start accepting rides?',
      answer:
          'Go online from the home screen and start receiving ride requests.',
    ),
    _FaqItem(
      question: 'What should I do if a rider cancels?',
      answer:
          'The cancelled ride will automatically appear in your trip history.',
    ),
    _FaqItem(
      question: 'How do I update my documents?',
      answer: 'Open Profile > Documents and upload updated files.',
    ),
    _FaqItem(
      question: 'What if I face an issue during a ride?',
      answer:
          'Use the emergency support option or contact driver support immediately.',
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
      appBar: AppBar(
        title: const Text('Help Center'),
        backgroundColor: surface,
        foregroundColor: textPri,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
        children: [
          // ── Header ────────────────────────────────────────────────────────
          _HeaderSection(textPri: textPri, textSec: textSec),
          const SizedBox(height: 28),

          // ── Support Contact ───────────────────────────────────────────────
          _SectionLabel(label: 'Support Contact', textSec: textSec),
          const SizedBox(height: 12),
          _SupportContactCard(
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
          ),
          const SizedBox(height: 28),

          // ── FAQs ──────────────────────────────────────────────────────────
          _SectionLabel(label: 'Frequently Asked Questions', textSec: textSec),
          const SizedBox(height: 12),
          _FaqSection(
            faqs: _faqs,
            surface: surface,
            border: border,
            textPri: textPri,
            textSec: textSec,
          ),
          const SizedBox(height: 28),

          // ── Emergency Support ─────────────────────────────────────────────
          _SectionLabel(label: 'Emergency Support', textSec: textSec),
          const SizedBox(height: 12),
          _EmergencyCard(surface: surface, border: border, textPri: textPri),
          const SizedBox(height: 36),

          // ── Footer ────────────────────────────────────────────────────────
          _Footer(textSec: textSec),
        ],
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _HeaderSection extends StatelessWidget {
  final Color textPri;
  final Color textSec;

  const _HeaderSection({required this.textPri, required this.textSec});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accentStrong.withAlpha(24),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.headset_mic_rounded,
                color: AppColors.accentStrong,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Help Center',
                    style: AppTextStyles.heading.copyWith(
                      color: textPri,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Need help? We are here for you.',
                    style: AppTextStyles.body.copyWith(
                      color: textSec,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
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

// ── Support Contact Card ─────────────────────────────────────────────────────

class _SupportContactCard extends StatelessWidget {
  final Color surface;
  final Color border;
  final Color textPri;
  final Color textSec;

  const _SupportContactCard({
    required this.surface,
    required this.border,
    required this.textPri,
    required this.textSec,
  });

  void _copyToClipboard(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied: $value'),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.accentStrong,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          _ContactRow(
            icon: Icons.email_outlined,
            label: 'Driver Support Email',
            value: 'driver.support@chalchalgaadi.com',
            iconColor: AppColors.accentStrong,
            textPri: textPri,
            textSec: textSec,
            onTap: () =>
                _copyToClipboard(context, 'driver.support@chalchalgaadi.com'),
            showDivider: true,
            border: border,
          ),
          _ContactRow(
            icon: Icons.phone_outlined,
            label: 'Driver Helpline',
            value: '+91 98765 43210',
            iconColor: AppColors.secondary,
            textPri: textPri,
            textSec: textSec,
            onTap: () => _copyToClipboard(context, '+91 98765 43210'),
            showDivider: true,
            border: border,
          ),
          _ContactRow(
            icon: Icons.access_time_rounded,
            label: 'Support Timing',
            value: 'Mon – Sun  ·  6:00 AM – 11:00 PM',
            iconColor: AppColors.accentYellow,
            textPri: textPri,
            textSec: textSec,
            showDivider: false,
            border: border,
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color textPri;
  final Color textSec;
  final VoidCallback? onTap;
  final bool showDivider;
  final Color border;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.textPri,
    required this.textSec,
    required this.showDivider,
    required this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.body.copyWith(
                          color: textSec,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: AppTextStyles.body.copyWith(
                          color: textPri,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: textSec.withAlpha(160),
                  ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: border,
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }
}

// ── FAQ Section ──────────────────────────────────────────────────────────────

class _FaqSection extends StatelessWidget {
  final List<_FaqItem> faqs;
  final Color surface;
  final Color border;
  final Color textPri;
  final Color textSec;

  const _FaqSection({
    required this.faqs,
    required this.surface,
    required this.border,
    required this.textPri,
    required this.textSec,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: List.generate(faqs.length, (i) {
            return _FaqTile(
              item: faqs[i],
              textPri: textPri,
              textSec: textSec,
              border: border,
              showDivider: i < faqs.length - 1,
            );
          }),
        ),
      ),
    );
  }
}

class _FaqItem {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});
}

class _FaqTile extends StatefulWidget {
  final _FaqItem item;
  final Color textPri;
  final Color textSec;
  final Color border;
  final bool showDivider;

  const _FaqTile({
    required this.item,
    required this.textPri,
    required this.textSec,
    required this.border,
    required this.showDivider,
  });

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _controller;
  late Animation<double> _iconTurn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );
    _iconTurn = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.accentStrong.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.help_outline_rounded,
                    color: AppColors.accentStrong,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.question,
                    style: AppTextStyles.body.copyWith(
                      color: widget.textPri,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                RotationTransition(
                  turns: _iconTurn,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: widget.textSec,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(52, 0, 16, 14),
            child: Text(
              widget.item.answer,
              style: AppTextStyles.body.copyWith(
                color: widget.textSec,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        if (widget.showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: widget.border,
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }
}

// ── Emergency Card ───────────────────────────────────────────────────────────

class _EmergencyCard extends StatelessWidget {
  final Color surface;
  final Color border;
  final Color textPri;

  const _EmergencyCard({
    required this.surface,
    required this.border,
    required this.textPri,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withAlpha(16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accentRed.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accentRed.withAlpha(24),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.emergency_rounded,
              color: AppColors.accentRed,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Emergency',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.accentRed,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentRed,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '112',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'In case of emergency, contact local authorities immediately.',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.accentRed.withAlpha(200),
                    fontSize: 13,
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
          'Chal Chal Gaadi Driver v1.0',
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(
            color: textSec,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Thank you for driving with Chal Chal Gaadi.',
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
