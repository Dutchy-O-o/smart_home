import 'dart:async';
import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../widgets/sensor_row_card.dart';
import '../../widgets/temp_humidity_card.dart';
import '../auth/login_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../providers/home_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/navigation_provider.dart';
import 'home_selection_screen.dart';
import '../../services/api_service.dart';
import 'widgets/dimmer_tile.dart';
import 'widgets/my_homes_list.dart';
import 'widgets/quick_access_button.dart';
import 'widgets/system_status_card.dart';

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

  // --- FETCH SENSOR DATA ---
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

  // --- FUNCTION THAT FETCHES THE ENCRYPTED QR TOKEN FROM THE REAL API ---
  Future<void> _generateAndShowQr(String homeId, String homeName) async {
    debugPrint("🕵️‍♂️ 3. API REQUEST FUNCTION STARTED. Target Home: $homeId");
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue)));

    try {
      final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
      final token = session.userPoolTokensResult.value.idToken.raw;
      debugPrint("🕵️‍♂️ 4. COGNITO TOKEN RECEIVED, CONNECTING TO AWS...");

      final url = Uri.parse("https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod/$homeId/generate-invite");
      debugPrint("🕵️‍♂️ 5. REQUESTED URL: $url");
      
      final response = await http.post(
        url,
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({}),
      );

      if (!mounted) return;
      Navigator.pop(context); // Close the loading spinner

      debugPrint("🕵️‍♂️ 6. RESPONSE RECEIVED FROM AWS! Status Code: ${response.statusCode}");
      debugPrint("🕵️‍♂️ 7. AWS RESPONSE BODY: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final secureToken = data['secure_token'];
        debugPrint("✅ 8. ENCRYPTED TOKEN RECEIVED, OPENING MODAL!");
        _showQrInviteModal(context, secureToken, homeName);
      } else {
        debugPrint("❌ ERROR: AWS rejected the request.");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not generate QR: ${response.body}"), backgroundColor: AppColors.accentRed));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      debugPrint("❌ SYSTEM ERROR (Catch): $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Connection error: $e"), backgroundColor: AppColors.accentRed));
    }
  }

  // --- FUNCTION THAT OPENS THE QR CODE MODAL ---
  void _showQrInviteModal(BuildContext context, String secureToken, String homeName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: AppColors.card(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.qr_code_scanner, color: AppColors.accentGreen, size: 40),
                const SizedBox(height: 16),
                Text(
                  "$homeName Invitation",
                  style: TextStyle(color: AppColors.text(context), fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Ask the guest to scan this code from their app. (Valid for 5 minutes)",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSub(context), fontSize: 14),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child:QrImageView(
                    data: secureToken, // Encrypted text received from AWS
                    version: QrVersions.auto,
                    size: 200.0,
                    backgroundColor: Colors.white, // So the scanner doesn't get confused in dark mode
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("CLOSE", style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Helper widget to align the round buttons in the top menu ---
  Widget _buildHeaderBtn(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
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
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- SLEEK AND SPACIOUS TOP MENU ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            ref.read(tabIndexProvider.notifier).setTab(6);
                          },
                          child: CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.card(context),
                            child: Icon(Icons.person, color: AppColors.iconDefault(context)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text("Welcome Back", style: TextStyle(color: AppColors.textSub(context), fontSize: 12)),
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
                                      style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (homeRole.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: AppColors.primaryBlue.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
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

                  // --- RIGHT SIDE: Action Buttons ---
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (homeRole == 'ADMIN') ...[
                        _buildHeaderBtn(Icons.qr_code, AppColors.accentGreen, () {
                          
                          // HERE'S THE MAGIC TOUCH: 'homeid' added!
                          final currentHomeId = selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'];

                          if (currentHomeId != null) {
                            _generateAndShowQr(currentHomeId.toString(), homeName);
                          } else {
                            debugPrint("❌ ERROR: Home ID still not found!");
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

              Text("My Homes", style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              MyHomesList(
                homes: _userHomes,
                isLoading: _isLoadingHomes,
                errorMessage: _errorMessage,
              ),

              const SizedBox(height: 24),
              const SystemStatusCard(),
              const SizedBox(height: 24),

              TempHumidityCard(
                temperature: _temperature,
                humidity: _humidity,
              ),

              const SizedBox(height: 24),

              Text("Security Status", style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => ref.read(tabIndexProvider.notifier).setTab(3),
                child: SensorRowCard(
                  title: "Vibration",
                  value: _vibrationStatus,
                  subtitle: "Seismic activity sensor",
                  icon: Icons.vibration,
                  iconColor: _vibrationStatus == 'DANGER' ? Colors.redAccent : AppColors.accentGreen,
                  status: _vibrationStatus == 'DANGER' ? "QUAKE" : "NO RISK",
                  statusColor: _vibrationStatus == 'DANGER' ? Colors.redAccent : AppColors.accentGreen,
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => ref.read(tabIndexProvider.notifier).setTab(3),
                child: SensorRowCard(
                  title: "Gas Sensor",
                  value: _gasStatus,
                  subtitle: "Air quality monitor",
                  icon: Icons.cloud,
                  iconColor: _gasStatus == 'DANGER' ? Colors.redAccent : AppColors.accentGreen,
                  status: _gasStatus == 'DANGER' ? "LEAK" : "NORMAL",
                  statusColor: _gasStatus == 'DANGER' ? Colors.redAccent : AppColors.accentGreen,
                ),
              ),

              const SizedBox(height: 24),

              Text("Quick Access", style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const QuickAccessButton(
                    icon: Icons.lightbulb,
                    label: 'Lights',
                    highlighted: true,
                  ),
                  const QuickAccessButton(
                    icon: Icons.tv,
                    label: 'TV',
                    iconColor: AppColors.primaryBlue,
                  ),
                  const QuickAccessButton(
                    icon: Icons.ac_unit,
                    label: 'AC On',
                    iconColor: AppColors.primaryBlue,
                  ),
                  QuickAccessButton(
                    icon: Icons.palette,
                    label: 'Mood',
                    iconColor: Colors.pinkAccent,
                    onTap: () => ref.read(tabIndexProvider.notifier).setTab(1),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              DimmerTile(
                value: isDimmerOn,
                onChanged: (val) => setState(() => isDimmerOn = val),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}