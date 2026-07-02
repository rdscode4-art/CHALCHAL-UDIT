import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class RecentPlacesScreen extends StatefulWidget {
  final List<Map<String, dynamic>> recentLocations;
  final List<Map<String, dynamic>> savedPlaces;
  final void Function(Map<String, dynamic> place) onSave;
  final void Function(String address) onSelect;

  const RecentPlacesScreen({
    super.key,
    required this.recentLocations,
    required this.savedPlaces,
    required this.onSave,
    required this.onSelect,
  });

  @override
  State<RecentPlacesScreen> createState() => _RecentPlacesScreenState();
}

class _RecentPlacesScreenState extends State<RecentPlacesScreen> {
  late List<Map<String, dynamic>> _recent;
  late List<Map<String, dynamic>> _saved;

  @override
  void initState() {
    super.initState();
    _recent = List.from(widget.recentLocations);
    _saved = List.from(widget.savedPlaces);
  }

  bool _isSaved(String address) =>
      _saved.any((item) => item['address'] == address);

  void _save(Map<String, dynamic> location) {
    if (_isSaved(location['address'] as String)) return;
    setState(() => _saved.add(location));
    widget.onSave(location);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${location['label']}" saved to your places'),
        duration: const Duration(milliseconds: 1200),
      ),
    );
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
          'Recent Places',
          style: AppTextStyles.heading.copyWith(
            fontSize: 20,
            color: cs.onSurface,
          ),
        ),
        centerTitle: false,
      ),
      body: _recent.isEmpty
          ? _buildEmpty(cs, subtitleColor)
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _recent.length,
              itemBuilder: (_, i) => _buildCard(
                _recent[i],
                cardBg: cardBg,
                borderColor: borderColor,
                titleColor: titleColor,
                subtitleColor: subtitleColor,
                iconBg: iconBg,
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
                Icons.history,
                size: 48,
                color: AppColors.accentStrong,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No recent places yet',
              style: AppTextStyles.heading.copyWith(
                fontSize: 18,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Destinations you select will appear here for quick reuse.',
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
    Map<String, dynamic> location, {
    required Color cardBg,
    required Color borderColor,
    required Color titleColor,
    required Color subtitleColor,
    required Color iconBg,
  }) {
    final address = location['address'] as String;
    final saved = _isSaved(address);

    final bookmarkBg = saved
        ? AppColors.accentYellow.withValues(alpha: 0.18)
        : AppColors.accentStrong.withValues(alpha: 0.12);
    final bookmarkColor = saved
        ? AppColors.accentYellow
        : AppColors.accentStrong;

    return GestureDetector(
      onTap: () {
        widget.onSelect(address);
        Navigator.pop(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // History icon bubble
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.history,
                color: AppColors.accentStrong,
                size: 22,
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
                          location['label'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.cardTitle.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: titleColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Recent',
                        style: AppTextStyles.body.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentStrong,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    address,
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
            const SizedBox(width: 8),
            // Bookmark button
            GestureDetector(
              onTap: () => _save(location),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bookmarkBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  saved ? Icons.bookmark : Icons.bookmark_border,
                  size: 18,
                  color: bookmarkColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
