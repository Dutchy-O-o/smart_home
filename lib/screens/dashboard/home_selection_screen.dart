import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; 

import '../../constants/app_colors.dart';
import '../../providers/home_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/navigation_provider.dart';
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
          print("✅ Başarılı: FCM Token AWS'ye kaydedildi.");
        }
      }
    } catch (e) {
      print("⚠️ FCM Token güncellenirken hata oluştu: $e");
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
    ref.read(tabIndexProvider.notifier).setTab(0);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MainShell()),
    );
  }

  Future<void> _handleLogout() async {
    await ref.read(authProvider.notifier).signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // --- KAMERAYI AÇAN VE AWS'YE (JOIN-HOME) İSTEK ATAN FONKSİYON ---
  Future<void> _openScanner() async {
    final scannedToken = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (scannedToken != null && scannedToken is String) {
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: AppColors.accentGreen)));

      try {
        final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
        final token = session.userPoolTokensResult.value.idToken.raw;

        // AWS'deki sadece /join-home olan uç nokta
        final url = Uri.parse("https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod/join-home");
        
        final response = await http.post(
          url,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({"secure_token": scannedToken}), 
        );

        if (!mounted) return;
        Navigator.pop(context); // Yükleniyor'u kapat

        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Harika! Eve başarıyla katıldınız! 🥳"), backgroundColor: AppColors.accentGreen));
          _fetchHomes(); // Listeyi yenile
        } else {
          final errorData = jsonDecode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $errorData"), backgroundColor: AppColors.accentRed));
        }
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Bağlantı hatası: $e"), backgroundColor: AppColors.accentRed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.accentRed),
            onPressed: _handleLogout,
            tooltip: "Logout",
          )
        ],
      ),
      // --- YENİ: KARE, YAZISIZ, MAVİ "KATIL" BUTONU ---
      floatingActionButton: FloatingActionButton(
        onPressed: _openScanner,
        backgroundColor: AppColors.primaryBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 4,
        child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
      body: SafeArea(
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator(color: AppColors.primaryBlue)
              : _errorMessage.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(_errorMessage, style: const TextStyle(color: AppColors.accentRed), textAlign: TextAlign.center),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          "Which home would you like to enter?",
                          style: TextStyle(color: AppColors.text(context), fontSize: 24, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        if (_homes.isEmpty)
                          Text(
                            "No registered homes found.\nTap the + button below to join one!",
                            style: TextStyle(color: AppColors.textSub(context), fontSize: 16),
                            textAlign: TextAlign.center,
                          )
                        else
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 24,
                            runSpacing: 24,
                            children: _homes.map((home) {
                              final isGuest = (home['role']?.toString().toLowerCase() == 'guest');
                              final homeName = home['home_name'] ?? 'Home';

                              return GestureDetector(
                                onTap: () => _selectHome(home),
                                child: Column(
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        color: isGuest ? AppColors.accentOrange.withOpacity(0.1) : AppColors.primaryBlue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isGuest ? AppColors.accentOrange.withOpacity(0.6) : AppColors.primaryBlue.withOpacity(0.6),
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        isGuest ? Icons.vpn_key_outlined : Icons.home_rounded,
                                        size: 48,
                                        color: isGuest ? AppColors.accentOrange : AppColors.primaryBlue,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      homeName,
                                      style: TextStyle(color: AppColors.text(context), fontSize: 16, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      (home['role'] ?? 'Unknown').toString().toUpperCase(),
                                      style: TextStyle(
                                        color: isGuest ? AppColors.accentOrange : AppColors.primaryBlue,
                                        fontSize: 12,
                                      ),
                                    )
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
        ),
      ),
    );
  }
}

// ============================================================================
// --- KAMERA İLE QR OKUMA SAYFASI ---
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
        title: const Text("QR Kodu Çerçeveye Alın", style: TextStyle(color: Colors.white)),
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
                  
                  // Okunan şifreli metni geldiğimiz sayfaya geri fırlatıyoruz
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
                "Adminin ekranındaki QR kodu okutun",
                style: TextStyle(color: Colors.white, fontSize: 16, backgroundColor: Colors.black54),
              ),
            ),
          )
        ],
      ),
    );
  }
}