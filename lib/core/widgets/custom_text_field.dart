import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

class CustomTextField extends StatelessWidget {
  final String hint;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType keyboardType;
  final bool readOnly;
  final VoidCallback? onTap;
  final Widget? prefixWidget;
  final bool obscureText;

  const CustomTextField({
    super.key,
    required this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.controller,
    this.focusNode,
    this.keyboardType = TextInputType.text,
    this.readOnly = false,
    this.onTap,
    this.prefixWidget,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark
        ? AppColors.darkSurfaceVariant
        : AppColors.surfaceSoft;
    final textColor = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final hintColor = isDark
        ? AppColors.darkOnSurface.withValues(alpha: 0.72)
        : AppColors.textGrey.withValues(alpha: 0.8);
    final iconColor = isDark ? AppColors.accentYellow : AppColors.accentStrong;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;
    final focusBorderColor = isDark
        ? AppColors.accentYellow
        : AppColors.accentStrong;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      obscureText: obscureText,
      cursorColor: focusBorderColor,
      style: AppTextStyles.body.copyWith(color: textColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.body.copyWith(color: hintColor),
        prefixIcon: prefixWidget ?? (prefixIcon != null
            ? Icon(prefixIcon, color: iconColor, size: 20)
            : null),
        suffixIcon: suffixIcon != null
            ? IconButton(
                icon: Icon(suffixIcon, color: iconColor, size: 20),
                onPressed: onSuffixTap,
              )
            : null,
        filled: true,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: focusBorderColor, width: 2),
        ),
      ),
    );
  }
}
