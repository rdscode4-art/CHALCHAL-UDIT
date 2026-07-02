import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../services/api_service.dart';

/// Fetches banners from [endpoint] (either `/api/user/banners` or
/// `/api/driver/banners`) and renders an auto-scrolling carousel with dot
/// indicators. Silently hides itself when no banners are returned.
///
/// Each banner object from the backend is expected to contain at least one of:
///   - `imageUrl` / `image` / `image_url`  — network image to display
///   - `title`                              — optional overlay text
///   - `subtitle` / `description`          — optional sub-text
///   - `bgColor` / `backgroundColor`       — optional hex colour string
class HomeBannerCarousel extends StatefulWidget {
  /// Pass `ApiService.getUserBanners` or `ApiService.getDriverBanners`.
  final Future<ApiResponse> Function() fetchBanners;

  const HomeBannerCarousel({super.key, required this.fetchBanners});

  @override
  State<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<HomeBannerCarousel> {
  List<Map<String, dynamic>> _banners = [];
  bool _loading = true;
  int _currentPage = 0;

  late final PageController _pageCtrl;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _fetchBanners();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  Future<void> _fetchBanners() async {
    try {
      final res = await widget.fetchBanners();
      debugPrint('[BANNER] success=${res.success} data=${res.data}');
      if (!res.success || !mounted) return;

      // Backend may return the list under various keys.
      List? raw;
      for (final key in ['banners', 'data', 'items', 'results']) {
        if (res.data[key] is List) {
          raw = res.data[key] as List;
          break;
        }
      }
      // Root-level list (e.g. the parsed body is itself a list wrapped in data)
      if (raw == null && res.data['data'] is List) {
        raw = res.data['data'] as List;
      }
      if (raw == null || raw.isEmpty) return;

      final parsed = raw
          .whereType<Map>()
          .map((b) => Map<String, dynamic>.from(b))
          .where((b) => _imageUrl(b) != null || _title(b) != null)
          .toList();

      if (!mounted || parsed.isEmpty) return;
      setState(() {
        _banners = parsed;
        _loading = false;
      });
      _startAutoScroll();
    } catch (e) {
      debugPrint('[BANNER] error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startAutoScroll() {
    if (_banners.length <= 1) return;
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      final next = (_currentPage + 1) % _banners.length;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  static String? _imageUrl(Map<String, dynamic> b) {
    for (final k in ['imageUrl', 'image_url', 'image', 'img', 'bannerImage']) {
      final v = b[k]?.toString().trim() ?? '';
      if (v.isEmpty) continue;
      // Relative path — prepend the backend base URL
      if (v.startsWith('/') || v.startsWith('uploads/')) {
        final base = AppConstants.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
        final path = v.startsWith('/') ? v : '/$v';
        return '$base$path';
      }
      return v; // already absolute
    }
    return null;
  }

  static String? _title(Map<String, dynamic> b) {
    final v = b['title']?.toString().trim() ?? '';
    return v.isEmpty ? null : v;
  }

  static String? _subtitle(Map<String, dynamic> b) {
    for (final k in ['subtitle', 'description', 'body', 'text']) {
      final v = b[k]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  /// Parse an optional hex colour string like "#FF5733" into a [Color].
  /// Falls back to the accent gradient if invalid/absent.
  static Color? _bgColor(Map<String, dynamic> b) {
    for (final k in ['bgColor', 'backgroundColor', 'bg_color', 'color']) {
      final raw = b[k]?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      final hex = raw.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      } else if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    }
    return null;
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Loading: show a slim skeleton placeholder.
    if (_loading) {
      return Container(
        height: 140,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(20),
        ),
      );
    }

    // No banners → render nothing (takes zero height).
    if (_banners.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) =>
                _BannerCard(banner: _banners[index]),
          ),
        ),
        if (_banners.length > 1) ...[
          const SizedBox(height: 10),
          _DotIndicator(count: _banners.length, current: _currentPage),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single banner card
// ─────────────────────────────────────────────────────────────────────────────
class _BannerCard extends StatelessWidget {
  final Map<String, dynamic> banner;
  const _BannerCard({required this.banner});

  @override
  Widget build(BuildContext context) {
    final imageUrl = _HomeBannerCarouselState._imageUrl(banner);
    final title = _HomeBannerCarouselState._title(banner);
    final subtitle = _HomeBannerCarouselState._subtitle(banner);
    final bgColor = _HomeBannerCarouselState._bgColor(banner);

    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final hasText = title != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background: image or gradient ───────────────────────────
            if (hasImage)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _gradientBg(bgColor),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : _gradientBg(bgColor),
              )
            else
              _gradientBg(bgColor),

            // ── Dark scrim for text readability ──────────────────────────
            if (hasText)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.black.withAlpha(160), Colors.transparent],
                  ),
                ),
              ),

            // ── Text overlay ─────────────────────────────────────────────
            if (hasText)
              Positioned(
                left: 18,
                top: 0,
                bottom: 0,
                right: 80,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withAlpha(210),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gradientBg(Color? accent) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          accent ?? AppColors.accentStrong,
          (accent ?? AppColors.secondary).withAlpha(180),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Dot indicator row
// ─────────────────────────────────────────────────────────────────────────────
class _DotIndicator extends StatelessWidget {
  final int count;
  final int current;
  const _DotIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active
                ? AppColors.accentStrong
                : AppColors.accentStrong.withAlpha(60),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
