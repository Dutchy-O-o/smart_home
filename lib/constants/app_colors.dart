import 'package:flutter/material.dart';

class AppColors {
  // Accent colors (theme-independent)
  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color accentOrange = Color(0xFFFF9800);
  static const Color accentGreen = Color(0xFF00E676);
  static const Color accentRed = Color(0xFFEF5350);
  static const Color teal = Color(0xFF00BFA5);

  // Dark palette
  static const Color _darkBg = Color(0xFF141A32);
  static const Color _darkCard = Color(0xFF1E2746);
  static const Color _darkBorder = Color(0xFF2A3654);
  static const Color _darkText = Colors.white;
  static const Color _darkTextSub = Color(0xFFB0B8D4);
  static const Color _darkNavBar = Color(0xFF0F1528);

  // Light palette
  static const Color _lightBg = Color(0xFFF5F6FA);
  static const Color _lightCard = Colors.white;
  static const Color _lightBorder = Color(0xFFE1E4EC);
  static const Color _lightText = Color(0xFF1A1D2E);
  static const Color _lightTextSub = Color(0xFF6B7288);
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
}
