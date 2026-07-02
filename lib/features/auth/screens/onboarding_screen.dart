import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/custom_button.dart';
import 'welcome_screen.dart';
import '../../../core/localization/app_localizations.dart';


class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Pages 2-4 use logo traffic-light colours for their icon cards
  final List<Map<String, dynamic>> _pages = [
    {
      'titleKey': 'onboardingTitle1',
      'subtitleKey': 'onboardingSub1',
      'icon': Icons.directions_car_rounded,
      'iconBg': [AppColors.darkSurface, AppColors.darkSurfaceSoft],
      'isLogo': true,
    },
    {
      'titleKey': 'onboardingTitle2',
      'subtitleKey': 'onboardingSub2',
      'icon': Icons.location_searching_rounded,
      'iconBg': [Color(0xFF1B5E20), Color(0xFF43A047)], // logo green shades
      'isLogo': false,
    },
    {
      'titleKey': 'onboardingTitle3',
      'subtitleKey': 'onboardingSub3',
      'icon': Icons.shield_rounded,
      'iconBg': [Color(0xFF2E3440), Color(0xFF4C566A)], // charcoal shades
      'isLogo': false,
    },
    {
      'titleKey': 'onboardingTitle4',
      'subtitleKey': 'onboardingSub4',
      'icon': Icons.flash_on_rounded,
      'iconBg': [Color(0xFFF57F17), Color(0xFFFDD835)], // logo yellow shades
      'isLogo': false,
    },
  ];

  void _goNext() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    }
  }

  void _skip() => Navigator.of(
    context,
  ).pushReplacement(MaterialPageRoute(builder: (_) => const WelcomeScreen()));

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.background;
    final textColor = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final subColor = isDark
        ? AppColors.darkOnSurface.withValues(alpha: 0.65)
        : AppColors.textGrey;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              // Top bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.tr('getStarted'),
                    style: AppTextStyles.heading.copyWith(
                      fontSize: 20,
                      color: textColor,
                    ),
                  ),
                  Row(
                    children: [
                      if (_currentPage < _pages.length - 1)
                        TextButton(
                          onPressed: _skip,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.accentStrong,
                          ),
                          child: Text(
                            context.tr('skip'),
                            style: AppTextStyles.body.copyWith(
                              color: AppColors.accentStrong,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: AppTheme.themeMode,
                        builder: (ctx, mode, _) {
                          final dark =
                              mode == ThemeMode.dark ||
                              (mode == ThemeMode.system &&
                                  MediaQuery.of(ctx).platformBrightness ==
                                      Brightness.dark);
                          return IconButton(
                            onPressed: AppTheme.toggleMode,
                            icon: Icon(
                              dark
                                  ? Icons.wb_sunny_rounded
                                  : Icons.nights_stay_rounded,
                            ),
                            color: textColor,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Pages
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (_, i) =>
                      _buildPage(_pages[i], isDark, textColor, subColor),
                ),
              ),

              const SizedBox(height: 20),

              // Indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final active = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    width: active ? 28 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.accentStrong
                          : (isDark ? AppColors.darkBorder : AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 28),

              CustomButton(
                label: _currentPage < _pages.length - 1
                    ? context.tr('next')
                    : context.tr('getStarted'),
                color: AppColors.accentStrong,
                onPressed: _goNext,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(
    Map<String, dynamic> page,
    bool isDark,
    Color textColor,
    Color subColor,
  ) {
    final isLogo = page['isLogo'] as bool;
    final gradColors = page['iconBg'] as List<Color>;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLogo)
          ChalChalGadiLogo(size: 180)
              .animate()
              .scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1, 1),
                duration: 420.ms,
                curve: Curves.easeOutBack,
              )
              .fade(duration: 300.ms)
        else
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradColors,
              ),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: gradColors[1].withValues(alpha: 0.35),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Center(
              child:
                  Icon(page['icon'] as IconData, size: 76, color: Colors.white)
                      .animate()
                      .scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1, 1),
                        duration: 420.ms,
                        curve: Curves.easeOutBack,
                      )
                      .fade(duration: 300.ms),
            ),
          ),

        const SizedBox(height: 40),

        Text(
          context.tr(page['titleKey'] as String),
          textAlign: TextAlign.center,
          style: AppTextStyles.heading.copyWith(
            fontSize: 24,
            color: textColor,
            height: 1.3,
          ),
        ),

        const SizedBox(height: 14),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            context.tr(page['subtitleKey'] as String),
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              color: subColor,
              fontSize: 15,
              height: 1.7,
            ),
          ),
        ),
      ],
    );
  }
}
