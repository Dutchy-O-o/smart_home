import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

// --- YENİ EKLENEN FIREBASE KÜTÜPHANELERİ ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';

// PROJENİN DİĞER İÇE AKTARIMLARI
import 'amplifyconfiguration.dart';
import 'constants/app_colors.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'providers/alert_provider.dart';
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
  // Flutter motorunu bağla
  WidgetsFlutterBinding.ensureInitialized();

  // .env dosyasını yükle
  await dotenv.load(fileName: ".env");

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
        // FCM bildirimini alert listesine ekle
        final eventType = message.data['event'] ?? 'alert';
        final container = ProviderScope.containerOf(currentContext);
        final now = DateTime.now();
        final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        AlertType alertType;
        AlertLevel alertLevel;
        if (eventType == 'gas_leak') {
          alertType = AlertType.security;
          alertLevel = AlertLevel.critical;
        } else if (eventType == 'earthquake') {
          alertType = AlertType.security;
          alertLevel = AlertLevel.critical;
        } else {
          alertType = AlertType.device;
          alertLevel = AlertLevel.info;
        }

        container.read(alertListProvider.notifier).addAlert(
          AlertItem(
            id: now.millisecondsSinceEpoch.toString(),
            title: title,
            description: body,
            time: timeStr,
            type: alertType,
            level: alertLevel,
          ),
        );

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
    final themeMode = ref.watch(themeProvider);

    Widget getHomeWidget() {
      switch (authState) {
        case AuthState.initial:
        case AuthState.loading:
          return Scaffold(
            backgroundColor: AppColors.bg(context),
            body: const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue)),
          );
        case AuthState.authenticated:
          return const HomeSelectionScreen();
        case AuthState.unauthenticated:
          return const OnboardingScreen();
      }
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      title: 'Akıllı Ev',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: getHomeWidget(),
    );
  }
}