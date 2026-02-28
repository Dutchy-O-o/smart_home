import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'amplifyconfiguration.dart';
import 'constants/app_colors.dart';
import 'screens/onboarding/onboarding_screen.dart'; // Yeni ekranı tanıttık

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureAmplify();
  runApp(const ProviderScope(child: AkilliEvApp()));
}

Future<void> _configureAmplify() async {
  try {
    final authPlugin = AmplifyAuthCognito();
    await Amplify.addPlugin(authPlugin);
    await Amplify.configure(amplifyconfig);
  } catch (e) {
    safePrint('An error occurred configuring Amplify: \$e');
  }
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