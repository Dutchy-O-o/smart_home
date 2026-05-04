import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

// --- FIREBASE LIBRARIES ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';

// PROJECT IMPORTS
import 'amplifyconfiguration.dart';
import 'constants/app_colors.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'providers/alert_provider.dart';
import 'screens/dashboard/home_selection_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';

// 1. GLOBAL NAVIGATOR KEY (used to show dialogs from anywhere)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 2. BACKGROUND MESSAGE HANDLER (must be a top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase needs to be initialized again in the background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Background notification received: ${message.notification?.title}");
}

Future<void> main() async {
  // Bind Flutter engine
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env
  await dotenv.load(fileName: ".env");

  // --- 3. INIT FIREBASE AND LISTEN FOR NOTIFICATIONS ---
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Register the background listener
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request notification permission. Required on Android 13+ (POST_NOTIFICATIONS)
    // and on iOS — without this the OS silently drops background notifications.
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // iOS: ensure the system tray banner shows even when the app is in foreground
    // (matches what users expect from a "background" notification).
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // CRITICAL: Force-pull title from Data when Notification is null
      String title = message.notification?.title ?? message.data['title'] ?? 'EMERGENCY ALERT';
      String body = message.notification?.body ?? message.data['body'] ?? 'An unexpected event was detected at home!';

      debugPrint("Foreground notification received: $title");

      // Get the current page context from the global key
      final currentContext = navigatorKey.currentContext;

      if (currentContext != null) {
        // FCM bildirimini alert listesine ekle
        final eventType = message.data['event'] ?? 'alert';
        // ignore: use_build_context_synchronously
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
          // ignore: use_build_context_synchronously
          context: currentContext,
          barrierDismissible: false, // user can't tap outside to close
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
                      title,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: Text(
                body,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text("OK", style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      } else {
        debugPrint("Error: Context not found, could not show alert dialog.");
      }
    });
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  // --- 4. INIT AWS AMPLIFY ---
  await _configureAmplify();

  // Wrap app in Riverpod
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
      title: 'Smart Home',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: getHomeWidget(),
    );
  }
}