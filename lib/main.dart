import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

// --- YENİ EKLENEN FIREBASE KÜTÜPHANELERİ ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart'; // FlutterFire CLI'ın oluşturduğu dosya

// PROJENİN DİĞER İÇE AKTARIMLARI
import 'amplifyconfiguration.dart';
import 'constants/app_colors.dart';
import 'providers/auth_provider.dart'; 
import 'screens/dashboard/home_selection_screen.dart'; 
import 'screens/onboarding/onboarding_screen.dart';

// 1. TÜM UYGULAMANIN EKRANINI TUTACAK GLOBAL ANAHTAR (EN TEPEYE EKLENDİ)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 2. UYGULAMA KAPALIYKEN ÇALIŞACAK FONKSİYON (Sınıfların dışında en üstte)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Arka planda çalışırken Firebase'i kendi içinde başlatması gerekir
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("Arka planda bildirim geldi: ${message.notification?.title}");
}

Future<void> main() async {
  // Flutter motorunu bağla (En önemli ilk adım)
  WidgetsFlutterBinding.ensureInitialized();

  // --- 3. FIREBASE'İ BAŞLAT VE BİLDİRİMLERİ DİNLE ---
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Arka plan dinleyicisini Firebase'e tanıt
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Uygulama açıkken (Foreground) gelen bildirimleri dinle
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // 1. KRİTİK DEĞİŞİKLİK: Notification null gelse bile Data'dan başlığı zorla çekiyoruz!
      String title = message.notification?.title ?? message.data['title'] ?? 'ACİL DURUM UYARISI';
      String body = message.notification?.body ?? message.data['body'] ?? 'Evde beklenmedik bir durum tespit edildi!';

      print("Uygulama açıkken bildirim geldi: $title");

      // Aktif olan sayfanın context'ini Global Anahtar'dan çekiyoruz
      final currentContext = navigatorKey.currentContext;

      if (currentContext != null) {
        showDialog(
          context: currentContext,
          barrierDismissible: false, // Kullanıcı dışarı tıklayarak kapatamasın
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: Colors.red.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Row(
                children: [
                  const Icon(Icons.warning_rounded, color: Colors.red, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title, // Artık doğrudan çektiğimiz title değişkenini kullanıyoruz
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: Text(
                body, // Artık doğrudan çektiğimiz body değişkenini kullanıyoruz
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text("ANLADIM", style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    Navigator.of(context).pop(); // Uyarıyı kapat
                  },
                ),
              ],
            );
          },
        );
      } else {
        print("Hata: Context bulunamadı, uyarı kutusu ekrana çizilemedi!");
      }
    });
  } catch (e) {
    print("Firebase başlatılırken hata oluştu: $e");
  }

  // --- 4. AWS AMPLIFY'I BAŞLAT ---
  await _configureAmplify();

  // Uygulamayı Riverpod ile sararak başlat
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

class AkilliEvApp extends ConsumerWidget {
  const AkilliEvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    Widget getHomeWidget() {
      switch (authState) {
        case AuthState.initial:
        case AuthState.loading:
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator(color: AppColors.primaryBlue)),
          );
        case AuthState.authenticated:
          return const HomeSelectionScreen();
        case AuthState.unauthenticated:
          return const OnboardingScreen();
      }
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // GLOBAL ANAHTARI BURAYA BAĞLADIK!
      title: 'Akıllı Ev',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primaryBlue,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primaryBlue,
          secondary: AppColors.accentGreen,
        ),
      ),
      home: getHomeWidget(),
    );
  }
}