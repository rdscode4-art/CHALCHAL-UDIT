import 'package:flutter/material.dart';

import '../../services/category_service.dart';

/// Displays the category image for a given [vehicleType] key (e.g. "bike", "auto", "sedan", "suv").
///
/// Listens to [CategoryService] and automatically rebuilds when the image
/// cache is populated — eliminating the race condition on first load.
///
/// Falls back to [fallbackEmoji] (default: 🚗) if no image is found.
///
/// Example:
/// ```dart
/// CategoryVehicleImage(vehicleType: 'bike', size: 48)
/// ```
class CategoryVehicleImage extends StatefulWidget {
  final String vehicleType;
  final double size;
  final String fallbackEmoji;
  final BoxFit fit;

  const CategoryVehicleImage({
    super.key,
    required this.vehicleType,
    this.size = 48,
    this.fallbackEmoji = '🚗',
    this.fit = BoxFit.contain,
  });

  /// Returns an emoji fallback based on the vehicle type.
  static String emojiForType(String vehicleType) {
    final type = vehicleType.toLowerCase().trim();
    if (type.contains('bike') || type.contains('moto')) return '🛵';
    if (type.contains('auto') || type.contains('rickshaw')) return '🛺';
    if (type.contains('ev') || type.contains('electric')) return '⚡';
    if (type.contains('suv')) return '🚙';
    if (type.contains('sedan')) return '🚕';
    if (type.contains('luxury') || type.contains('premium')) return '🚘';
    return '🚗';
  }

  @override
  State<CategoryVehicleImage> createState() => _CategoryVehicleImageState();
}

class _CategoryVehicleImageState extends State<CategoryVehicleImage> {
  @override
  void initState() {
    super.initState();
    CategoryService.instance.addListener(_onCacheUpdate);
  }

  @override
  void dispose() {
    CategoryService.instance.removeListener(_onCacheUpdate);
    super.dispose();
  }

  void _onCacheUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = CategoryService.instance.imageUrlForVehicleType(
      widget.vehicleType,
    );

    if (imageUrl.isEmpty) {
      return _EmojiBox(
        emoji: CategoryVehicleImage.emojiForType(widget.vehicleType),
        size: widget.size,
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Image.network(
        imageUrl,
        width: widget.size,
        height: widget.size,
        fit: widget.fit,
        errorBuilder: (_, _, _) => _EmojiBox(
          emoji: CategoryVehicleImage.emojiForType(widget.vehicleType),
          size: widget.size,
        ),
        loadingBuilder: (_, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmojiBox extends StatelessWidget {
  final String emoji;
  final double size;

  const _EmojiBox({required this.emoji, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: size * 0.75)),
      ),
    );
  }
}
