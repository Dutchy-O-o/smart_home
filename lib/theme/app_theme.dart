import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static ThemeData darkTheme = ThemeData.dark().copyWith(
    scaffoldBackgroundColor: AppColors.background,
    primaryColor: AppColors.primaryBlue,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primaryBlue,
      secondary: AppColors.accentGreen,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primaryBlue,
      foregroundColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accentOrange,
        foregroundColor: Colors.white,
      ),
    ),
  );

  static ThemeData lightTheme = ThemeData.light().copyWith(
    scaffoldBackgroundColor: const Color(0xFFF5F6FA),
    primaryColor: AppColors.primaryBlue,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primaryBlue,
      secondary: AppColors.accentGreen,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primaryBlue,
      foregroundColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accentOrange,
        foregroundColor: Colors.white,
      ),
    ),
  );
}
