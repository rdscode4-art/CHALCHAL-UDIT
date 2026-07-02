import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class SavedPlacesScreen extends StatefulWidget {
  final List<Map<String, dynamic>> savedPlaces;
  final void Function(Map<String, dynamic> place) onRemove;
  final void Function(String address) onSelect;

  const SavedPlacesScreen({
    super.key,
    required this.savedPlaces,
    required this.onRemove,
    required this.onSelect,
  });

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  late List<Map<String, dynamic>> _places;

  @override
  void initState() {
    super.initState();
    _places = List.from(widget.savedPlaces);
  }

  void _remove(Map<String, dynamic> place) {
    setState(() => _places.remove(place));
    widget.onRemove(place);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Adaptive colours
    final cardBg = cs.surface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;
    final titleColor = cs.onSurface;
    final subtitleColor = cs.onSurface.withValues(alpha: 0.55);
    final iconBg = AppColors.accentStrong.withValues(
      alpha: isDark ? 0.18 : 0.10,
    );
    final badgeBg = AppColors.accentYellow.withValues(
      alpha: isDark ? 0.22 : 0.12,
    );
    final deleteBg = Colors.red.withValues(alpha: isDark ? 0.18 : 0.08);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Icon(
              Icons.arrow_back_ios_new,
              size: 16,
              color: cs.onSurface,
            ),
          ),
        ),
        title: Text(
          'Saved Places',
          style: AppTextStyles.heading.copyWith(
            fontSize: 20,
            color: cs.onSurface,
          ),
        ),
        centerTitle: false,
      ),
      body: _places.isEmpty
          ? _buildEmpty(cs, subtitleColor)
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _places.length,
              itemBuilder: (_, i) => _buildCard(
                _places[i],
                cardBg: cardBg,
                borderColor: borderColor,
                titleColor: titleColor,
                subtitleColor: subtitleColor,
                iconBg: iconBg,
                badgeBg: badgeBg,
                deleteBg: deleteBg,
              ),
            ),
    );
  }

  Widget _buildEmpty(ColorScheme cs, Color subtitleColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.accentStrong.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bookmark_border,
                size: 48,
                color: AppColors.accentStrong,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No saved places yet',
              style: AppTextStyles.heading.copyWith(
                fontSize: 18,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Save this place" after entering a destination to add it here.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                fontSize: 13,
                color: subtitleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    Map<String, dynamic> place, {
    required Color cardBg,
    required Color borderColor,
    required Color titleColor,
    required Color subtitleColor,
    required Color iconBg,
    required Color badgeBg,
    required Color deleteBg,
  }) {
    return GestureDetector(
      onTap: () {
        widget.onSelect(place['address'] as String);
        Navigator.pop(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon bubble
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                place['icon'] as IconData? ?? Icons.location_on,
                color: AppColors.accentStrong,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          place['label'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.cardTitle.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: titleColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Saved',
                          style: AppTextStyles.body.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentYellow,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    place['address'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      height: 1.5,
                      color: subtitleColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.touch_app, size: 13, color: subtitleColor),
                      const SizedBox(width: 5),
                      Text(
                        'Tap to use as destination',
                        style: AppTextStyles.body.copyWith(
                          fontSize: 11,
                          color: subtitleColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Delete button
            GestureDetector(
              onTap: () => _remove(place),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: deleteBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
