import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

class CustomButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final bool isOutlined;

  /// Override the text/border color for outlined buttons independently.
  /// Useful when the background context makes [color] hard to read.
  final Color? outlinedTextColor;

  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.isOutlined = false,
    this.outlinedTextColor,
  });

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool _pressed = false;

  void _onTapDown(TapDownDetails _) {
    setState(() {
      _pressed = true;
    });
  }

  void _onTapEnd(TapUpDetails _) {
    setState(() {
      _pressed = false;
    });
  }

  void _onTapCancel() {
    setState(() {
      _pressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // For outlined buttons: prefer explicit outlinedTextColor, then fall back
    // to accentStrong in dark mode (always visible) or the passed color in light.
    final outlinedColor =
        widget.outlinedTextColor ??
        (isDark ? AppColors.accentStrong : (widget.color ?? AppColors.primary));

    final button = SizedBox(
      width: double.infinity,
      height: 52,
      child: widget.isOutlined
          ? OutlinedButton(
              onPressed: widget.onPressed,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: outlinedColor, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.transparent,
              ),
              child: Text(
                widget.label,
                style: AppTextStyles.button.copyWith(color: outlinedColor),
              ),
            )
          : ElevatedButton(
              onPressed: widget.onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.color ?? AppColors.primary,
                elevation: 6,
                shadowColor: (widget.color ?? AppColors.primary).withAlpha(89),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(widget.label, style: AppTextStyles.button),
            ),
    );

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapEnd,
      onTapCancel: _onTapCancel,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _pressed ? 0.98 : 1.0,
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: widget.isOutlined
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      (widget.color ?? AppColors.primary).withValues(
                        alpha: 0.95,
                      ),
                      (widget.color ?? AppColors.primary).withValues(
                        alpha: 0.85,
                      ),
                    ],
                  ),
            color: widget.isOutlined
                ? Colors.transparent
                : widget.color ?? AppColors.primary,
            boxShadow: widget.isOutlined
                ? [
                    BoxShadow(
                      color: AppColors.textDark.withAlpha(12),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: AppColors.textDark.withAlpha(18),
                      blurRadius: 18,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(-4, -4),
                    ),
                  ],
          ),
          child: button.animate().fadeIn(
            duration: 250.ms,
            curve: Curves.easeOut,
          ),
        ),
      ),
    );
  }
}
