import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class DriverTermsScreen extends StatefulWidget {
  const DriverTermsScreen({super.key});

  @override
  State<DriverTermsScreen> createState() => _DriverTermsScreenState();
}

class _DriverTermsScreenState extends State<DriverTermsScreen> {
  // Track which expandable sections are open
  final Set<int> _expanded = {};

  void _toggle(int index) {
    setState(() {
      if (_expanded.contains(index)) {
        _expanded.remove(index);
      } else {
        _expanded.add(index);
      }
    });
  }

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

    final sections = _buildSections(surface, border, textPri, textSec);

    return Scaffold(
      backgroundColor: scaffold,
      appBar: AppBar(
        title: const Text('Terms & Conditions'),
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

          // Expandable section tiles
          ...List.generate(sections.length, (i) {
            final s = sections[i];
            final isOpen = _expanded.contains(i);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TermsTile(
                index: i + 1,
                title: s.title,
                iconData: s.icon,
                iconColor: s.iconColor,
                isOpen: isOpen,
                onTap: () => _toggle(i),
                surface: surface,
                border: border,
                textPri: textPri,
                textSec: textSec,
                child: s.content,
              ),
            );
          }),

          const SizedBox(height: 10),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.accentStrong.withAlpha(12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.accentStrong.withAlpha(40)),
            ),
            child: Column(
              children: [
                Text(
                  '© 2026 Chal Chal Gaadi Driver.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    color: textPri,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'All Rights Reserved.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    color: textSec,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_SectionData> _buildSections(
    Color surface,
    Color border,
    Color textPri,
    Color textSec,
  ) {
    return [
      _SectionData(
        title: 'Acceptance of Terms',
        icon: Icons.handshake_outlined,
        iconColor: AppColors.accentStrong,
        content: _BodyText(
          text:
              'By using Chal Chal Gaadi Driver, you agree to follow these terms and conditions.',
          textSec: textSec,
        ),
      ),
      _SectionData(
        title: 'Driver Responsibilities',
        icon: Icons.badge_outlined,
        iconColor: const Color(0xFF5C6BC0),
        content: _BulletList(
          items: const [
            'Maintain valid documents',
            'Follow traffic laws',
            'Ensure passenger safety',
            'Keep vehicle information updated',
            'Behave professionally with riders',
          ],
          textSec: textSec,
        ),
      ),
      _SectionData(
        title: 'Ride Rules',
        icon: Icons.route_rounded,
        iconColor: const Color(0xFFEF6C00),
        content: _BulletList(
          items: const [
            'Drivers should accept genuine ride requests',
            'Ride cancellations should be minimized',
            'Drivers must reach pickup locations on time',
          ],
          textSec: textSec,
        ),
      ),
      _SectionData(
        title: 'Prohibited Activities',
        icon: Icons.block_rounded,
        iconColor: AppColors.accentRed,
        content: _BulletList(
          items: const [
            'Fake ride activity',
            'Harassment or misconduct',
            'Unsafe driving',
            'Fraudulent behavior',
            'Misuse of the platform',
          ],
          textSec: textSec,
          bulletColor: AppColors.accentRed,
        ),
      ),
      _SectionData(
        title: 'Account Suspension',
        icon: Icons.gpp_bad_outlined,
        iconColor: AppColors.accentRed,
        content: _BodyText(
          text:
              'Accounts violating platform policies may be suspended or permanently blocked.',
          textSec: textSec,
        ),
      ),
      _SectionData(
        title: 'Limitation of Liability',
        icon: Icons.info_outline_rounded,
        iconColor: const Color(0xFF5C6BC0),
        content: _BodyText(
          text:
              'Chal Chal Gaadi Driver is not responsible for delays caused by traffic, weather, or unforeseen situations.',
          textSec: textSec,
        ),
      ),
      _SectionData(
        title: 'Changes to Terms',
        icon: Icons.edit_note_rounded,
        iconColor: const Color(0xFFEF6C00),
        content: _BodyText(
          text: 'These terms may be updated periodically without prior notice.',
          textSec: textSec,
        ),
      ),
      _SectionData(
        title: 'Contact Information',
        icon: Icons.email_outlined,
        iconColor: AppColors.accentStrong,
        content: Row(
          children: [
            const Icon(
              Icons.alternate_email_rounded,
              size: 15,
              color: AppColors.accentStrong,
            ),
            const SizedBox(width: 8),
            Text(
              'legal@chalchalgaadi.com',
              style: AppTextStyles.body.copyWith(
                color: AppColors.accentStrong,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

// ── Section Data Model ───────────────────────────────────────────────────────

class _SectionData {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget content;

  const _SectionData({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.content,
  });
}

// ── Expandable Tile ──────────────────────────────────────────────────────────

class _TermsTile extends StatefulWidget {
  final int index;
  final String title;
  final IconData iconData;
  final Color iconColor;
  final bool isOpen;
  final VoidCallback onTap;
  final Widget child;
  final Color surface;
  final Color border;
  final Color textPri;
  final Color textSec;

  const _TermsTile({
    required this.index,
    required this.title,
    required this.iconData,
    required this.iconColor,
    required this.isOpen,
    required this.onTap,
    required this.child,
    required this.surface,
    required this.border,
    required this.textPri,
    required this.textSec,
  });

  @override
  State<_TermsTile> createState() => _TermsTileState();
}

class _TermsTileState extends State<_TermsTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _iconTurn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
      value: widget.isOpen ? 1.0 : 0.0,
    );
    _iconTurn = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(_TermsTile old) {
    super.didUpdateWidget(old);
    if (widget.isOpen != old.isOpen) {
      widget.isOpen ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isOpen ? widget.iconColor.withAlpha(80) : widget.border,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Header row
            InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    // Section number badge
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.iconColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.index}',
                        style: AppTextStyles.body.copyWith(
                          color: widget.iconColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: widget.iconColor.withAlpha(16),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        widget.iconData,
                        color: widget.iconColor,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: AppTextStyles.body.copyWith(
                          color: widget.textPri,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
            // Expandable content
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: [
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: widget.border,
                    indent: 14,
                    endIndent: 14,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: widget.child,
                  ),
                ],
              ),
              crossFadeState: widget.isOpen
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
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
  final Color bulletColor;

  const _BulletList({
    required this.items,
    required this.textSec,
    this.bulletColor = AppColors.accentStrong,
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
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: bulletColor,
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
