import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; 

import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../constants/app_colors.dart';
import '../../providers/home_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mood_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/aurora_background.dart';
import '../../widgets/main_shell.dart';
import '../auth/login_screen.dart';

class HomeSelectionScreen extends ConsumerStatefulWidget {
  const HomeSelectionScreen({super.key});

  @override
  ConsumerState<HomeSelectionScreen> createState() => _HomeSelectionScreenState();
}

class _HomeSelectionScreenState extends ConsumerState<HomeSelectionScreen> {
  List<dynamic> _homes = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchHomes();
    _updateFcmTokenSilently();
  }

  Future<void> _updateFcmTokenSilently() async {
    try {
      String? fcmToken = await FirebaseMessaging.instance.getToken();
      
      if (fcmToken != null) {
        final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
        final cognitoToken = session.userPoolTokensResult.value.idToken.raw;
        
        final url = Uri.parse("https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod/fcm-token");
        
        final response = await http.put(
          url,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $cognitoToken"
          },
          body: jsonEncode({"fcm_token": fcmToken}),
        );

        if (response.statusCode == 200) {
          debugPrint("✅ Success: FCM Token saved to AWS.");
        }
      }
    } catch (e) {
      debugPrint("⚠️ Error while updating FCM Token: $e");
    }
  }

  Future<void> _fetchHomes() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
      final token = session.userPoolTokensResult.value.idToken.raw;

      final String apiUrl = 'https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod/homes';

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _homes = data['homes'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = "Failed to load homes (${response.statusCode})";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Connection error: $e";
          _isLoading = false;
        });
      }
    }
  }

  void _selectHome(Map<String, dynamic> home) {
    ref.read(selectedHomeProvider.notifier).setHome(home);

    Navigator.pushReplacement(
      context,
      AppMotion.fadeSlideRoute(const MainShell()),
    );
  }

  /// Long-press handler on each home tile. Shows a bottom sheet with the
  /// home details + a destructive "Leave home" option that hits the
  /// /{homeID}/leave endpoint. We use a sheet rather than a context menu
  /// so the action looks deliberate and previews what will happen.
  Future<void> _showHomeMenu(Map<String, dynamic> home) async {
    final homeId = (home['home_id'] ?? home['id'] ?? home['homeid'])?.toString();
    if (homeId == null) return;
    final homeName = (home['home_name'] ?? 'Home').toString();
    final role = (home['role'] ?? '').toString().toLowerCase();
    final isAdmin = role == 'admin';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.bg(ctx),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(
              color: AppColors.borderCol(ctx).withValues(alpha: 0.6),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.textSub(ctx).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: AppColors.brandGradient,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child:
                      const Icon(Icons.home_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        homeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.text(ctx),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        role.toUpperCase(),
                        style: TextStyle(
                          color: isAdmin
                              ? AppColors.primaryBlue
                              : AppColors.accentAmber,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Material(
              color: AppColors.accentRed.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.pop(ctx, 'leave'),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.accentRed.withValues(alpha: 0.40),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.logout_rounded,
                          color: AppColors.accentRed),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAdmin ? 'Leave this home' : 'Leave this home',
                              style: TextStyle(
                                color: AppColors.accentRed,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              isAdmin
                                  ? 'Promote another admin first if you are the only one.'
                                  : 'You will lose access until invited again.',
                              style: TextStyle(
                                color: AppColors.textSub(ctx),
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSub(ctx),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ).then((choice) async {
      if (choice == 'leave') {
        await _confirmAndLeaveHome(homeId, homeName);
      }
    });
  }

  Future<void> _confirmAndLeaveHome(String homeId, String homeName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('Leave "$homeName"?',
            style: TextStyle(color: AppColors.text(ctx))),
        content: Text(
          'You will lose access immediately. You can rejoin only with a new invite QR.',
          style: TextStyle(color: AppColors.textSub(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSub(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave',
                style: TextStyle(
                    color: AppColors.accentRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    final result = await ApiService.leaveHome(homeId);
    if (!mounted) return;

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Left "$homeName"'),
        backgroundColor: AppColors.accentGreen,
      ));
      // If the user just left the currently-selected home, clear it so
      // we don't navigate into a home they no longer own.
      final selected = ref.read(selectedHomeProvider);
      final selectedId = (selected?['home_id'] ??
              selected?['id'] ??
              selected?['homeid'])
          ?.toString();
      if (selectedId == homeId) {
        ref.read(selectedHomeProvider.notifier).clear();
      }
      await _fetchHomes();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.errorMessage ?? 'Could not leave home.'),
        backgroundColor: AppColors.accentRed,
      ));
    }
  }

  Future<void> _handleLogout() async {
    ref.read(moodProvider.notifier).clear();
    await ref.read(authProvider.notifier).signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        AppMotion.fadeSlideRoute(const LoginScreen()),
        (route) => false,
      );
    }
  }

  // --- FUNCTION THAT OPENS THE CAMERA AND SENDS A REQUEST TO AWS (JOIN-HOME) ---
  Future<void> _openScanner() async {
    final scannedToken = await Navigator.push(
      context,
      AppMotion.fadeSlideRoute(const QRScannerScreen()),
    );

    if (scannedToken != null && scannedToken is String) {
      if (!mounted) return;
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: AppColors.accentGreen)));

      try {
        final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
        final token = session.userPoolTokensResult.value.idToken.raw;

        // The /join-home endpoint on AWS
        final url = Uri.parse("https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod/join-home");
        
        final response = await http.post(
          url,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({"secure_token": scannedToken}), 
        );

        if (!mounted) return;
        Navigator.pop(context); // Close the loading spinner

        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Great! You've successfully joined the home! 🥳"), backgroundColor: AppColors.accentGreen));
          _fetchHomes(); // Refresh the list
        } else {
          final errorData = jsonDecode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $errorData"), backgroundColor: AppColors.accentRed));
        }
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Connection error: $e"), backgroundColor: AppColors.accentRed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.text(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.accentRed),
            onPressed: _handleLogout,
            tooltip: "Logout",
          )
        ],
      ),
      floatingActionButton: _JoinHomeFab(onTap: _openScanner),
      body: Stack(
        children: [
          const Positioned.fill(child: AuroraBackground(intensity: 0.75)),
          SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primaryBlue, strokeWidth: 2.5),
                  )
                : _errorMessage.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text(_errorMessage,
                              style: const TextStyle(color: AppColors.accentRed),
                              textAlign: TextAlign.center),
                        ),
                      )
                    // LayoutBuilder + ConstrainedBox(minHeight) + IntrinsicHeight
                    // lets the Column expand to the full viewport height so
                    // MainAxisAlignment.center actually centers the content
                    // vertically on short lists, while still scrolling
                    // naturally once the home list grows beyond the screen.
                    : LayoutBuilder(
                        builder: (context, viewport) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: viewport.maxHeight - 132,
                              ),
                              child: IntrinsicHeight(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Center(
                                      child: Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: const LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: AppColors.brandGradient,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.primaryBlue
                                                  .withValues(alpha: 0.45),
                                              blurRadius: 26,
                                              offset: const Offset(0, 10),
                                            ),
                                            BoxShadow(
                                              color: AppColors.teal
                                                  .withValues(alpha: 0.30),
                                              blurRadius: 32,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                            Icons.holiday_village_rounded,
                                            color: Colors.white,
                                            size: 40),
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    Text(
                                      "Welcome back",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.textSub(context),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _homes.isEmpty
                                          ? "Let's connect your first home"
                                          : "Choose a home to enter",
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .displayLarge
                                          ?.copyWith(fontSize: 26, height: 1.15),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _homes.isEmpty
                                          ? "Tap the + button to scan an invite QR."
                                          : "Tap any home below — admin homes have full access, guest homes are read-only.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.textSub(context),
                                        fontSize: 13.5,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 32),
                                    if (_homes.isEmpty)
                                      _EmptyHomesHint()
                                    else
                                      Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 18,
                                        runSpacing: 18,
                                        children: [
                                          for (int i = 0; i < _homes.length; i++)
                                            _HomeTile(
                                              home: _homes[i],
                                              onTap: () => _selectHome(_homes[i]),
                                              onLongPress: () =>
                                                  _showHomeMenu(_homes[i]),
                                            )
                                                .animate(delay: (90 * i).ms)
                                                .fadeIn(duration: 420.ms)
                                                .slideY(begin: 0.1, end: 0),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Single home card. Admin homes use the brand gradient (live access);
/// guest homes use a warmer amber tint so the difference is obvious at
/// a glance before you tap in.
class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.home,
    required this.onTap,
    required this.onLongPress,
  });

  final Map<String, dynamic> home;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final role = (home['role'] ?? 'Unknown').toString();
    final isGuest = role.toLowerCase() == 'guest';
    final homeName = (home['home_name'] ?? 'Home').toString();

    final accent =
        isGuest ? AppColors.accentAmber : AppColors.primaryBlue;
    final accent2 =
        isGuest ? AppColors.accentOrange : AppColors.primaryViolet;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onLongPress();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 144,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.card(context),
                Color.alphaBlend(
                  accent.withValues(alpha: 0.18),
                  AppColors.card(context),
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.30),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent, accent2],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.55),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  isGuest ? Icons.vpn_key_rounded : Icons.home_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                homeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.40),
                  ),
                ),
                child: Text(
                  role.toUpperCase(),
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Visual cue + nudge shown when the user has no homes yet — keeps the
/// screen from feeling empty.
class _EmptyHomesHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderCol(context)),
      ),
      child: Column(
        children: [
          Icon(Icons.qr_code_scanner_rounded,
              color: AppColors.primaryBlue, size: 36),
          const SizedBox(height: 12),
          Text(
            "No homes yet",
            style: TextStyle(
              color: AppColors.text(context),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Ask the home admin to share an invite QR, then scan it with the + button below.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSub(context),
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand-gradient FAB with extra glow. Replaces the flat blue square so the
/// "join a home" action reads as the primary CTA — important for first-time
/// users who land here with an empty homes list.
class _JoinHomeFab extends StatelessWidget {
  const _JoinHomeFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.brandGradient,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: AppColors.teal.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            child: const Icon(Icons.qr_code_scanner_rounded,
                color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// --- CAMERA QR SCANNER PAGE ---
// ============================================================================
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Align the QR Code in the Frame", style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (BarcodeCapture capture) {
              if (_isProcessing) return; 

              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  setState(() => _isProcessing = true);
                  final String code = barcode.rawValue!;
                  
                  // Send the scanned encrypted text back to the previous page
                  Navigator.pop(context, code);
                  break; 
                }
              }
            },
          ),
          
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accentGreen, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: const Center(
              child: Text(
                "Scan the QR code on the admin's screen",
                style: TextStyle(color: Colors.white, fontSize: 16, backgroundColor: Colors.black54),
              ),
            ),
          )
        ],
      ),
    );
  }
}