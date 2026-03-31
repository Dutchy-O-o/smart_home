import 'dart:async';
import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../widgets/sensor_card.dart';
import '../auth/login_screen.dart';
import '../ai_hub/emotion_hub_screen.dart'; 
import '../security/monitoring_screen.dart';
import '../devices/device_control_screen.dart';
import '../devices/device_control_screen.dart';
import '../notifications/notification_screen.dart';
import '../profile/profile_screen.dart';
import '../automations/automations_list_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../providers/home_provider.dart';
import '../../providers/auth_provider.dart';
import 'home_selection_screen.dart';
import '../../services/api_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool isDimmerOn = true;

  List<dynamic> _userHomes = [];
  bool _isLoadingHomes = true;
  String _errorMessage = '';

  String _temperature = "--";
  String _humidity = "--";
  String _gasStatus = "SAFE";
  String _vibrationStatus = "STABLE";
  String _lastHomeId = '';
  Timer? _dashboardPollingTimer;

  @override
  void dispose() {
    _dashboardPollingTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchUserHomes();
  }

  Future<void> _fetchUserHomes() async {
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
          _userHomes = data['homes'] ?? [];
          _isLoadingHomes = false;
        });
      } else {
        setState(() {
          _errorMessage = "Server error (${response.statusCode})";
          _isLoadingHomes = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoadingHomes = false;
      });
    }
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

  void _onBottomNavTapped(int index) {
    if (index == 0) return;
    final routes = [
      null, // Dash
      const EmotionHubScreen(), // Emotion
      const AutomationsListScreen(), // Automate
      const MonitoringScreen(), // Security
      const DeviceControlScreen(), // Devices
      const NotificationScreen(), // Alerts
      const ProfileScreen(), // Profile
    ];
    if (index < routes.length && routes[index] != null) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => routes[index]!));
    }
  }

  // --- SENSÖR VERİSİ ÇEKME ---
  Future<void> _fetchSensors(String homeId) async {
    final data = await ApiService.fetchSensors(homeId);
    if (data != null && data['sensors'] != null) {
      final sensors = data['sensors'] as Map<String, dynamic>;
      
      if (mounted) {
        setState(() {
          for (var deviceData in sensors.values) {
            if (deviceData is Map) {
              if (deviceData.containsKey('temperature')) _temperature = deviceData['temperature'].toString();
              if (deviceData.containsKey('humidity')) _humidity = deviceData['humidity'].toString();
              
              if (deviceData.containsKey('status') && deviceData.containsKey('gas_level')) {
                _gasStatus = deviceData['status'].toString().toUpperCase();
              }
              if (deviceData.containsKey('event') && deviceData.containsKey('vibration_intensity')) {
                String evt = deviceData['event'].toString().toLowerCase();
                _vibrationStatus = evt == 'earthquake_detected' ? 'DANGER' : 'STABLE';
              }
            }
          }
        });
      }
    }
  }

  // --- GERÇEK API'DEN ŞİFRELİ QR TOKEN'I ALAN FONKSİYON ---
  Future<void> _generateAndShowQr(String homeId, String homeName) async {
    print("🕵️‍♂️ 3. API İSTEK FONKSİYONU BAŞLADI. Hedef Ev: $homeId");
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue)));

    try {
      final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
      final token = session.userPoolTokensResult.value.idToken.raw;
      print("🕵️‍♂️ 4. COGNITO TOKEN ALINDI, AWS'YE GİDİLİYOR...");

      final url = Uri.parse("https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod/$homeId/generate-invite");
      print("🕵️‍♂️ 5. İSTEK ATILAN URL: $url");
      
      final response = await http.post(
        url,
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({}),
      );

      if (!mounted) return;
      Navigator.pop(context); // Yükleniyor dairesini kapat

      print("🕵️‍♂️ 6. AWS'DEN CEVAP GELDİ! Status Code: ${response.statusCode}");
      print("🕵️‍♂️ 7. AWS CEVAP İÇERİĞİ: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final secureToken = data['secure_token'];
        print("✅ 8. ŞİFRELİ TOKEN ALINDI, MODAL AÇILIYOR!");
        _showQrInviteModal(context, secureToken, homeName);
      } else {
        print("❌ HATA: AWS işlemi reddetti.");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("QR oluşturulamadı: ${response.body}"), backgroundColor: AppColors.accentRed));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      print("❌ SİSTEM HATASI (Catch): $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Bağlantı hatası: $e"), backgroundColor: AppColors.accentRed));
    }
  }

  // --- QR KOD MODALINI AÇAN FONKSİYON ---
  void _showQrInviteModal(BuildContext context, String secureToken, String homeName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: AppColors.cardDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.qr_code_scanner, color: AppColors.accentGreen, size: 40),
                const SizedBox(height: 16),
                Text(
                  "$homeName Daveti",
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Misafirin uygulamasından bu kodu okutmasını isteyin. (5 dk geçerlidir)",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textGrey, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child:QrImageView(
                    data: secureToken, // AWS'den gelen şifreli metin
                    version: QrVersions.auto,
                    size: 200.0,
                    backgroundColor: Colors.white, // Tarayıcının karanlık modda kafası karışmasın diye
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue.withOpacity(0.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("KAPAT", style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Üst menüdeki yuvarlak butonları hizalamak için yardımcı widget ---
  Widget _buildHeaderBtn(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedHome = ref.watch(selectedHomeProvider);
    final homeName = selectedHome?['home_name'] ?? 'Home';
    final homeRole = selectedHome?['role']?.toString().toUpperCase() ?? '';
    final homeId = (selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'])?.toString();

    if (homeId != null && homeId.isNotEmpty && homeId != _lastHomeId) {
       _lastHomeId = homeId;
       WidgetsBinding.instance.addPostFrameCallback((_) {
         _fetchSensors(homeId);
       });
       
       _dashboardPollingTimer?.cancel();
       _dashboardPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
         if (mounted) _fetchSensors(homeId);
       });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- ŞIK VE FERAH ÜST MENÜ ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
                          },
                          child: const CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.cardDark,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text("Welcome Back", style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                                  const SizedBox(width: 8),
                                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.accentGreen, shape: BoxShape.circle)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.wifi, color: AppColors.accentGreen, size: 12),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      homeName,
                                      style: const TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (homeRole.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: AppColors.primaryBlue.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                                      child: Text(homeRole, style: const TextStyle(color: AppColors.primaryBlue, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- SAĞ TARAF: Aksiyon Butonları ---
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (homeRole == 'ADMIN') ...[
                        _buildHeaderBtn(Icons.qr_code, AppColors.accentGreen, () {
                          
                          // İŞTE SİHİRLİ DOKUNUŞ: 'homeid' eklendi!
                          final currentHomeId = selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'];
                          
                          if (currentHomeId != null) {
                            _generateAndShowQr(currentHomeId.toString(), homeName);
                          } else {
                            print("❌ HATA: Ev ID'si hala bulunamadı!");
                          }
                        }),
                        const SizedBox(width: 8),
                      ],
                      _buildHeaderBtn(Icons.swap_horiz, AppColors.primaryBlue, () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const HomeSelectionScreen()),
                        );
                      }),
                      const SizedBox(width: 8),
                      _buildHeaderBtn(Icons.logout, AppColors.accentRed, _handleLogout),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 24),

              const Text("My Homes", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _isLoadingHomes 
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue))
                : _errorMessage.isNotEmpty
                  ? Text(_errorMessage, style: const TextStyle(color: AppColors.accentRed))
                  : _userHomes.isEmpty 
                    ? const Text("No homes found.", style: TextStyle(color: Colors.grey))
                    : SizedBox(
                        height: 100,
                        child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _userHomes.length,
                        itemBuilder: (context, index) {
                          final home = _userHomes[index];
                          final role = home['role'] ?? 'Unknown Role';
                          final isGuest = role.toString().toLowerCase() == 'guest';
                          
                          return Container(
                            width: 140,
                            margin: const EdgeInsets.only(right: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.cardDark,
                              border: Border.all(color: isGuest ? AppColors.accentOrange.withOpacity(0.5) : AppColors.primaryBlue.withOpacity(0.5)),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isGuest ? Icons.vpn_key_outlined : Icons.admin_panel_settings,
                                      color: isGuest ? AppColors.accentOrange : AppColors.primaryBlue,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        home['home_name'] ?? 'Home $index',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isGuest ? AppColors.accentOrange.withOpacity(0.2) : AppColors.primaryBlue.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    role.toString().toUpperCase(),
                                    style: TextStyle(
                                      color: isGuest ? AppColors.accentOrange : AppColors.primaryBlue,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold
                                    ),
                                  ),
                                )
                              ],
                            ),
                          );
                        },
                      ),
                    ),

              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF152238),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sentiment_satisfied_alt, color: AppColors.primaryBlue, size: 36),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text("System Online", style: TextStyle(color: AppColors.primaryBlue, fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text(
                            "The house feels cozy and secure. No anomalies detected in the last hour.",
                            style: TextStyle(color: AppColors.textGrey, fontSize: 12, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: SensorCard(
                      title: "Temperature",
                      value: _temperature,
                      unit: "°C",
                      icon: Icons.thermostat,
                      iconColor: AppColors.accentOrange,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SensorCard(
                      title: "Humidity",
                      value: _humidity,
                      unit: "%",
                      icon: Icons.water_drop,
                      iconColor: AppColors.primaryBlue,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              const Text("Security Status", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _onBottomNavTapped(2),
                      child: SensorCard(
                        title: "Gas Sensor",
                        value: _gasStatus,
                        icon: Icons.cloud,
                        iconColor: _gasStatus == 'DANGER' ? Colors.redAccent : AppColors.accentGreen,
                        status: _gasStatus == 'DANGER' ? "• LEAK" : "• NORMAL",
                        statusColor: _gasStatus == 'DANGER' ? Colors.redAccent : AppColors.accentGreen,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _onBottomNavTapped(2),
                      child: SensorCard(
                        title: "Vibration",
                        value: _vibrationStatus,
                        icon: Icons.vibration,
                        iconColor: _vibrationStatus == 'DANGER' ? Colors.redAccent : AppColors.accentGreen,
                        status: _vibrationStatus == 'DANGER' ? "• QUAKE" : "• NO RISK",
                        statusColor: _vibrationStatus == 'DANGER' ? Colors.redAccent : AppColors.accentGreen,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              const Text("Quick Access", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildQuickAccessBtn(Icons.lightbulb, "Lights", AppColors.primaryBlue),
                  _buildQuickAccessBtn(Icons.curtains, "Curtains", Colors.white24),
                  _buildQuickAccessBtn(Icons.ac_unit, "AC On", Colors.white24, iconColor: AppColors.primaryBlue),
                  _buildQuickAccessBtn(Icons.palette, "Mood", Colors.white24, iconColor: Colors.pinkAccent, onTap: () {
                    _onBottomNavTapped(1);
                  }),
                ],
              ),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.wb_sunny, color: Colors.amber, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text("Living Room Dimmer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Text("80% Brightness", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    Switch(
                      value: isDimmerOn,
                      activeColor: AppColors.primaryBlue,
                      onChanged: (val) {
                        setState(() {
                          isDimmerOn = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.cardDark,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        onTap: _onBottomNavTapped,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Dash'),
          BottomNavigationBarItem(icon: Icon(Icons.sentiment_satisfied_alt), label: 'Emotion'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'Automate'),
          BottomNavigationBarItem(icon: Icon(Icons.security), label: 'Security'),
          BottomNavigationBarItem(icon: Icon(Icons.devices), label: 'Devices'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildQuickAccessBtn(IconData icon, String label, Color bg, {Color iconColor = Colors.white, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: bg == AppColors.primaryBlue ? AppColors.primaryBlue : AppColors.cardDark,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
        ],
      ),
    );
  }
}