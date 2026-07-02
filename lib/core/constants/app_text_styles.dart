import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  static final TextStyle display = GoogleFonts.inter(
    fontSize: 34,
    fontWeight: FontWeight.w700,
  );

  static final TextStyle heading = GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w700,
  );

  static final TextStyle subtitle = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static final TextStyle body = GoogleFonts.inter(fontSize: 15, height: 1.6);

  static final TextStyle button = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.surface,
  );

  static final TextStyle cardTitle = GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w700,
  );
}
