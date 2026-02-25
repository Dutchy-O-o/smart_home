import 'package:flutter/material.dart';
import 'constants/app_colors.dart';
import 'screens/auth/login_screen.dart';
import 'screens/onboarding/onboarding_screen.dart'; // Yeni ekranı tanıttık

void main() {
  runApp(const AkilliEvApp());
}

class AkilliEvApp extends StatelessWidget {
  const AkilliEvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Akıllı Ev',
      // Tema Ayarları (Burası aynı kaldı)
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primaryBlue,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primaryBlue,
          secondary: AppColors.accentGreen,
        ),
      ),
      // ÖNEMLİ DEĞİŞİKLİK BURADA:
      // Artık LoginScreen değil, OnboardingScreen ile başlıyoruz.
      home: const OnboardingScreen(),
    );
  }
}

/// aaa