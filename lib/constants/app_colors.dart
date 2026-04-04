import 'package:flutter/material.dart';

class AppColors {
  // --- FIXED ACCENT COLORS (same in both themes) ---
  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color accentOrange = Color(0xFFFF9800);
  static const Color accentGreen = Color(0xFF00E676);
  static const Color accentRed = Color(0xFFEF5350);
  static const Color purple = Color(0xFF9C27B0);
  static const Color teal = Color(0xFF26C6DA);

  // --- LEGACY CONSTANTS (dark theme only, kept for reference) ---
  static const Color background = Color(0xFF141A32);
  static const Color cardDark = Color(0xFF1E2746);
  static const Color textWhite = Colors.white;
  static const Color textGrey = Colors.grey;

  // --- THEME-AWARE COLORS ---
  static bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  static Color bg(BuildContext context) =>
      _isDark(context) ? const Color(0xFF141A32) : const Color(0xFFF0F2F7);

  static Color card(BuildContext context) =>
      _isDark(context) ? const Color(0xFF1E2746) : Colors.white;

  static Color text(BuildContext context) =>
      _isDark(context) ? Colors.white : const Color(0xFF1A1A2E);

  static Color textSub(BuildContext context) =>
      _isDark(context) ? Colors.grey : const Color(0xFF6B7280);

  static Color borderCol(BuildContext context) =>
      _isDark(context) ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.2);

  static Color navBar(BuildContext context) =>
      _isDark(context) ? const Color(0xFF1E2746) : Colors.white;

  static Color iconDefault(BuildContext context) =>
      _isDark(context) ? Colors.white : const Color(0xFF374151);

  // Context-based Methods (updated)
  static Color textPrimary(BuildContext context) => text(context);
  static Color surface(BuildContext context) => card(context);
  static Color border(BuildContext context) => borderCol(context);
}
