import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:showcaseview/showcaseview.dart';

// --- FIREBASE LIBRARIES ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

// PROJECT IMPORTS
import 'amplifyconfiguration.dart';
import 'constants/app_colors.dart';
import 'providers/auth_provider.dart';
import 'providers/home_provider.dart';
import 'providers/theme_provider.dart';
import 'services/spotify_service.dart';
import 'services/user_scope.dart';
import 'theme/app_theme.dart';
import 'providers/alert_provider.dart';
import 'screens/dashboard/home_selection_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/alert_localizer.dart';

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

  // Edge-to-edge: let the body draw under both status and navigation bars
  // so the aurora background reaches the very bottom of the screen instead
  // of getting cut off by an opaque system nav strip on Android.
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // Secrets are injected via --dart-define at compile time (see
  // lib/config/env.dart). No .env bundle is shipped with release builds.

  // Restore the previously signed-in user id so per-user scoped data
  // (mood history, scene slots, theme) is keyed correctly before any
  // screen reads SharedPreferences.
  await UserScope.bootstrap();

  // Eagerly restore the Spotify OAuth token so the dashboard speaker
  // pause/play works on first open. Previously this only happened when
  // the user opened the Emotion Hub, so tapping pause from a cold
  // start showed "Speaker not found" instead of stopping the music.
  // Fire-and-forget — failure is harmless (user just sees the connect
  // prompt as before).
  SpotifyService.loadSavedToken();

  // --- 3. INIT FIREBASE AND LISTEN FOR NOTIFICATIONS ---
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Crashlytics — route uncaught Flutter framework errors and async
    // platform errors to the Crashlytics dashboard. Disabled in debug
    // so local stack traces still print to the console without being
    // double-reported.
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

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
        final eventType = (message.data['event'] ?? 'alert').toString();
        // Swap the server's English-only title/body for the bilingual
        // copy when the event_type is one we localize. Anything not in
        // the map keeps the original FCM strings.
        final localized = localizeAlert(eventType, body);
        if (localized != null) {
          title = localized.title;
          body = localized.body;
        }
        // ignore: use_build_context_synchronously
        final container = ProviderScope.containerOf(currentContext);
        final now = DateTime.now();
        final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        AlertType alertType;
        AlertLevel alertLevel;
        switch (eventType) {
          case 'gas_leak':
          case 'earthquake':
            // Life-safety events — critical security badges.
            alertType = AlertType.security;
            alertLevel = AlertLevel.critical;
            break;
          case 'rfid_unauthorized':
          case 'rfid_denied':
          case 'unauthorized_access':
            // Someone tried to enter with a card we don't recognize.
            // Not a fire-or-quake but still security-relevant — surface
            // it under the Security filter at warning level so the user
            // notices without being jolted into thinking the house is
            // burning down.
            alertType = AlertType.security;
            alertLevel = AlertLevel.warning;
            break;
          default:
            alertType = AlertType.device;
            alertLevel = AlertLevel.info;
        }

        // Persist to AWS too — without this, the alert lives only in
        // local memory and gets clobbered the next time the user opens
        // the Notifications screen (which hydrates from /alerts).
        final selectedHome = container.read(selectedHomeProvider);
        final fcmHomeId = (selectedHome?['home_id'] ??
                selectedHome?['id'] ??
                selectedHome?['homeid'])
            ?.toString() ??
            '';
        container.read(alertListProvider.notifier).addAlertSynced(
              AlertItem(
                id: now.millisecondsSinceEpoch.toString(),
                title: title,
                description: body,
                time: timeStr,
                type: alertType,
                level: alertLevel,
              ),
              homeId: fcmHomeId,
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
      builder: (context, child) {
        // Showcase needs to wrap below MaterialApp so OverlayState is
        // available; without this child! the auto-route is bypassed but
        // the tooltip overlay still renders correctly above all routes.
        return ShowCaseWidget(
          autoPlayDelay: const Duration(milliseconds: 800),
          builder: (ctx) => child!,
        );
      },
      home: getHomeWidget(),
    );
  }
}