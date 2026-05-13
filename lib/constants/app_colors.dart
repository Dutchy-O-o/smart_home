import 'package:flutter/material.dart';

class AppColors {
  // Accent colors (theme-independent) — modern AI/SaaS palette.
  // primaryBlue is now an indigo-violet to read as smart/AI rather than
  // generic Material; emerald replaces the acid green for sophistication.
  static const Color primaryBlue = Color(0xFF5B6CFF);
  static const Color primaryViolet = Color(0xFF8B5CF6);
  static const Color accentOrange = Color(0xFFFF8A4C);
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentRed = Color(0xFFF43F5E);
  static const Color teal = Color(0xFF14B8A6);
  static const Color accentPink = Color(0xFFEC4899);
  static const Color accentAmber = Color(0xFFF59E0B);

  // Dark palette — deeper, more cinematic than the old #141A32
  static const Color _darkBg = Color(0xFF0B0F1F);
  static const Color _darkCard = Color(0xFF161B2E);
  static const Color _darkBorder = Color(0xFF252B45);
  static const Color _darkText = Colors.white;
  static const Color _darkTextSub = Color(0xFFA9B0CC);
  static const Color _darkNavBar = Color(0xFF0F1426);

  // Light palette — slightly cooler off-white for premium feel
  static const Color _lightBg = Color(0xFFF6F7FB);
  static const Color _lightCard = Colors.white;
  static const Color _lightBorder = Color(0xFFE5E8F0);
  static const Color _lightText = Color(0xFF13172A);
  static const Color _lightTextSub = Color(0xFF6B7188);
  static const Color _lightNavBar = Colors.white;

  // Legacy constants (kept for compatibility)
  static const Color background = _darkBg;
  static const Color cardDark = _darkCard;
  static const Color textWhite = Colors.white;
  static const Color textGrey = Colors.grey;

  static bool _isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color bg(BuildContext c) => _isDark(c) ? _darkBg : _lightBg;
  static Color card(BuildContext c) => _isDark(c) ? _darkCard : _lightCard;
  static Color borderCol(BuildContext c) =>
      _isDark(c) ? _darkBorder : _lightBorder;
  static Color border(BuildContext c) => borderCol(c);
  static Color surface(BuildContext c) => card(c);
  static Color text(BuildContext c) => _isDark(c) ? _darkText : _lightText;
  static Color textPrimary(BuildContext c) => text(c);
  static Color textSub(BuildContext c) =>
      _isDark(c) ? _darkTextSub : _lightTextSub;
  static Color navBar(BuildContext c) =>
      _isDark(c) ? _darkNavBar : _lightNavBar;
  static Color iconDefault(BuildContext c) => text(c);

  /// Brand gradient used in the hero header, primary CTAs, and the bottom-nav
  /// active pill. Kept as a single source of truth so brand polish stays
  /// consistent across the app.
  static const List<Color> brandGradient = [
    Color(0xFF5B6CFF), // indigo
    Color(0xFF8B5CF6), // violet
    Color(0xFF14B8A6), // teal
  ];
}
