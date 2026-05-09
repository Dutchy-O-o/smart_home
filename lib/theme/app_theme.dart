import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'app_spacing.dart';

/// Centralized theme for the app. Material 3 + a shared TextTheme so
/// individual widgets stop hard-coding fontSize/fontWeight everywhere.
///
/// Naming intent:
///  - displayLarge       → screen hero numbers (e.g. dashboard greeting)
///  - headlineSmall      → screen titles ("Quick Access", "My Homes")
///  - titleMedium        → card titles
///  - bodyMedium         → default body
///  - bodySmall          → secondary/sub text
///  - labelSmall         → captions, ranges, helper text
class AppTheme {
  static const _fontFamily = null; // pick up platform default for now

  static TextTheme _buildTextTheme(Color text, Color sub) {
    return TextTheme(
      displayLarge: TextStyle(
        color: text,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.1,
      ),
      headlineSmall: TextStyle(
        color: text,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        color: text,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      titleMedium: TextStyle(
        color: text,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
      titleSmall: TextStyle(
        color: text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: text,
        fontSize: 15,
        height: 1.4,
      ),
      bodyMedium: TextStyle(
        color: text,
        fontSize: 14,
        height: 1.4,
      ),
      bodySmall: TextStyle(
        color: sub,
        fontSize: 12,
        height: 1.35,
      ),
      labelLarge: TextStyle(
        color: text,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        color: sub,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(
        color: sub,
        fontSize: 10,
        height: 1.25,
      ),
    );
  }

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: AppColors.background,
    primaryColor: AppColors.primaryBlue,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primaryBlue,
      secondary: AppColors.accentGreen,
      tertiary: AppColors.teal,
      error: AppColors.accentRed,
      surface: AppColors.cardDark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    textTheme: _buildTextTheme(Colors.white, const Color(0xFFB0B8D4)),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.cardDark,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    dividerColor: const Color(0xFF2A3654),
    iconTheme: const IconThemeData(color: Colors.white),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.cardDark,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
      behavior: SnackBarBehavior.floating,
    ),
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: const Color(0xFFF5F6FA),
    primaryColor: AppColors.primaryBlue,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primaryBlue,
      secondary: AppColors.accentGreen,
      tertiary: AppColors.teal,
      error: AppColors.accentRed,
      surface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Color(0xFF1A1D2E),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    textTheme: _buildTextTheme(
      const Color(0xFF1A1D2E),
      const Color(0xFF6B7288),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    dividerColor: const Color(0xFFE1E4EC),
    iconTheme: const IconThemeData(color: Color(0xFF1A1D2E)),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Colors.white,
      contentTextStyle: const TextStyle(color: Color(0xFF1A1D2E)),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
