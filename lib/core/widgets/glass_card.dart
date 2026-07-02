import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.border,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (color ?? AppColors.surface).withValues(alpha: 0.72),
            borderRadius: borderRadius,
            border:
                border ??
                Border.all(color: AppColors.surfaceLight.withAlpha(140)),
            boxShadow:
                boxShadow ??
                [
                  BoxShadow(
                    color: AppColors.textDark.withAlpha(10),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
          ),
          child: child,
        ),
      ),
    );
  }
}
