import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'amplifyconfiguration.dart';
import 'constants/app_colors.dart';

// Ekranları ve Provider'ı import ettiğinden emin ol
import 'providers/auth_provider.dart'; // authProvider'ın olduğu dosya
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';

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
    safePrint('An error occurred configuring Amplify: $e');
  }
}

// 1. ConsumerWidget yaptık ki authProvider'ı dinleyebilelim
class AkilliEvApp extends ConsumerWidget {
  const AkilliEvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 2. Auth state'i anlık olarak dinliyoruz
    final authState = ref.watch(authProvider);

    // 3. Duruma göre hangi sayfanın açılacağına karar veren sihirli fonksiyon
    Widget getHomeWidget() {
      switch (authState) {
        case AuthState.initial:
        case AuthState.loading:
          // Uygulama ilk açıldığında Amplify kontrol yaparken dönecek ekran
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator(color: AppColors.primaryBlue)),
          );
        case AuthState.authenticated:
          // Kasa dolu! Doğrudan eve gir.
          return const DashboardScreen();
        case AuthState.unauthenticated:
          // Kasa boş veya oturum bitmiş. Onboarding/Login'e gönder.
          return const OnboardingScreen();
      }
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Akıllı Ev',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primaryBlue,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primaryBlue,
          secondary: AppColors.accentGreen,
        ),
      ),
      // 4. Ana sayfayı dinamik olarak belirliyoruz
      home: getHomeWidget(),
    );
  }
}