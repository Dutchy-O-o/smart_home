import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import 'app_spacing.dart';

/// Centralized theme for the app. Material 3 + a shared TextTheme so
/// individual widgets stop hard-coding fontSize/fontWeight everywhere.
///
/// Typography uses Plus Jakarta Sans (Google Fonts) — a modern geometric
/// sans that reads as premium SaaS rather than the platform default.
///
/// Naming intent:
///  - displayLarge       → screen hero numbers (e.g. dashboard greeting)
///  - headlineSmall      → screen titles ("Quick Access", "My Homes")
///  - titleMedium        → card titles
///  - bodyMedium         → default body
///  - bodySmall          → secondary/sub text
///  - labelSmall         → captions, ranges, helper text
class AppTheme {
  static TextTheme _buildTextTheme(Color text, Color sub) {
    final base = TextTheme(
      displayLarge: TextStyle(
        color: text,
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.05,
      ),
      headlineSmall: TextStyle(
        color: text,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        color: text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        color: text,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
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
    return GoogleFonts.plusJakartaSansTextTheme(base);
  }

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    primaryColor: AppColors.primaryBlue,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primaryBlue,
      secondary: AppColors.accentGreen,
      tertiary: AppColors.teal,
      error: AppColors.accentRed,
      surface: AppColors.cardDark,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    textTheme: _buildTextTheme(Colors.white, const Color(0xFFA9B0CC)),
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
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.cardDark,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    dividerColor: const Color(0xFF252B45),
    iconTheme: const IconThemeData(color: Colors.white),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.cardDark,
      contentTextStyle: GoogleFonts.plusJakartaSans(
        color: Colors.white,
        fontSize: 14,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
      behavior: SnackBarBehavior.floating,
    ),
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF6F7FB),
    primaryColor: AppColors.primaryBlue,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primaryBlue,
      secondary: AppColors.accentGreen,
      tertiary: AppColors.teal,
      error: AppColors.accentRed,
      surface: Colors.white,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: const Color(0xFF13172A),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: const Color(0xFF13172A),
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    textTheme: _buildTextTheme(
      const Color(0xFF13172A),
      const Color(0xFF6B7188),
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
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    dividerColor: const Color(0xFFE5E8F0),
    iconTheme: const IconThemeData(color: Color(0xFF13172A)),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Colors.white,
      contentTextStyle: GoogleFonts.plusJakartaSans(
        color: const Color(0xFF13172A),
        fontSize: 14,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
