import 'package:flutter/material.dart';

/// Chal Chal Gadi — logo-derived colour system
///
/// Logo palette:
///   Charcoal bg  : #2E3440
///   Red dot      : #E53935
///   Yellow dot   : #FDD835
///   Green dot    : #43A047
///   White text   : #FFFFFF
class AppColors {
  // ── Brand primaries ───────────────────────────────────────────────────────
  static const Color primary = Color(0xFF2E3440); // logo charcoal
  static const Color secondary = Color(0xFF43A047); // logo green
  static const Color accentYellow = Color(0xFFFDD835); // logo yellow
  static const Color accentRed = Color(0xFFE53935); // logo red
  static const Color driverRed = accentRed;

  // ── CTA green (slightly brighter than secondary for buttons) ─────────────
  static const Color accentStrong = Color(0xFF4CAF50);
  static const Color accent = secondary;
  static const Color neonAccent = Color(0xFF69F0AE);

  // ── Light theme ───────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF4F6F8); // cool light grey
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFECEFF1); // blue-grey tint
  static const Color surfaceLight = Color(0xFFF8FAFB);
  static const Color cardBg = Color(0xFFE8F5E9); // subtle green tint
  static const Color border = Color(0xFFDDE1E7); // cool grey border

  // ── Dark theme ────────────────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF1A1D23); // deeper than logo
  static const Color darkSurface = Color(0xFF2E3440); // logo charcoal
  static const Color darkSurfaceSoft = Color(0xFF3B4252); // one step lighter
  static const Color darkSurfaceVariant = Color(0xFF434C5E); // two steps
  static const Color darkBorder = Color(0xFF4C566A); // nord4
  static const Color darkOnSurface = Color(0xFFECEFF4); // near-white
  static const Color darkPrimary = Color(0xFF81C784); // light green

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textDark = Color(0xFF1A1D23); // near-black
  static const Color textGrey = Color(0xFF6B7280); // neutral grey
  static const Color textLight = Color(0xFFECEFF4);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF43A047);
  static const Color warning = Color(0xFFFDD835);
  static const Color error = Color(0xFFE53935);

  // ── Legacy ────────────────────────────────────────────────────────────────
  static const Color driverCard = cardBg;
}
