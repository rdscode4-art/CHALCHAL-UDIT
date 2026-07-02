import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../localization/app_localizations.dart';

enum LanguageToggleStyle { pill, outlined }

class LanguageToggleButton extends StatelessWidget {
  const LanguageToggleButton({
    super.key,
    this.style = LanguageToggleStyle.pill,
    this.color,
    this.borderColor,
  });

  final LanguageToggleStyle style;
  final Color? color;
  final Color? borderColor;

  void _toggle(bool isHindi) {
    LanguageManager.setLocale(
      isHindi ? const Locale('en') : const Locale('hi'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.accentStrong;
    final border = borderColor ?? AppColors.border;

    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageManager.localeNotifier,
      builder: (ctx, locale, _) {
        final isHindi = locale.languageCode == 'hi';
        final label = isHindi ? 'English' : 'हिन्दी';

        if (style == LanguageToggleStyle.outlined) {
          return InkWell(
            onTap: () => _toggle(isHindi),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.translate_rounded, color: accent, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () => _toggle(isHindi),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textDark.withAlpha(12),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.translate_rounded, color: accent, size: 16),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
