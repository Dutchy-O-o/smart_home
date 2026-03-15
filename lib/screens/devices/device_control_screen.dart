import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/home_provider.dart';
import '../dashboard/dashboard_screen.dart';
import '../ai_hub/emotion_hub_screen.dart';
import '../security/monitoring_screen.dart';
import '../notifications/notification_screen.dart';
import '../profile/profile_screen.dart';

class DeviceControlScreen extends ConsumerStatefulWidget {
  const DeviceControlScreen({super.key});

  @override
  ConsumerState<DeviceControlScreen> createState() => _DeviceControlScreenState();
}

class _DeviceControlScreenState extends ConsumerState<DeviceControlScreen>
    with WidgetsBindingObserver {
  bool _isLightOn = true;
  double _brightness = 58.0;
  Color _selectedLightColor = const Color(0xFF448AFF);

  int _curtainPosition = 60;
  String _curtainStatus = "Position: 60%";

  int _targetTemp = 20;
  String _climateMode = "Cool";

  String _insideTemp = "--";
  String _insideHumidity = "--";

  Timer? _tempDebounceTimer;
  Timer? _curtainDebounceTimer;
  Timer? _dataPollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _fetchLatestSensorData();
    
    _startPollingTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dataPollingTimer?.cancel();
    _tempDebounceTimer?.cancel();
    _curtainDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_dataPollingTimer == null || !_dataPollingTimer!.isActive) {
        _startPollingTimer();
      }
    } else {
      _dataPollingTimer?.cancel();
    }
  }

  void _startPollingTimer() {
    _dataPollingTimer?.cancel();
    _dataPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchLatestSensorData();
    });
  }

 Future<void> _fetchLatestSensorData() async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = selectedHome?['homeid'] ?? '';
    
    // 1. GÜNCELLEME: URL yapısı yeni REST API mimarisine göre ayarlandı
    final url = Uri.parse("https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod/$homeId/sensor");
    
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      
      if (session is CognitoAuthSession) {
        final token = session.userPoolTokensResult.value.idToken.raw;
        
        final response = await http.get(
          url,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $token"
          },
        );
        
        print(response.body);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          // 2. GÜNCELLEME: Lambda'dan dönen "sensors" objesini alıyoruz
          final sensors = data['sensors'] as Map<String, dynamic>? ?? {};
          
          // Cihaz ID'leri dinamik (UUID) olduğu için, değerler içinde dönüp 
          // sıcaklık verisi basan sensörü (DHT11 vb.) buluyoruz.
          for (var deviceData in sensors.values) {
            if (deviceData is Map && deviceData.containsKey('temperature') && deviceData.containsKey('humidity')) {
              setState(() {
                _insideTemp = deviceData['temperature'].toString();
                _insideHumidity = deviceData['humidity'].toString();
              });
              break; // Sensörü bulduk, gereksiz yere diğerlerini aramamak için döngüden çık
            }
          }
        } else {
          print("Sensör verisi reddedildi. Hata: ${response.statusCode}");
          print(response.body);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Sensör verileri alınamadı! (Hata: ${response.statusCode})"), duration: const Duration(seconds: 2), backgroundColor: Colors.redAccent),
            );
          }
        }
      }
    } catch (e) {
      print("Sensör verisi çekilemedi: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sensörlere bağlanılamadı. İnternetinizi kontrol edin."), duration: Duration(seconds: 3), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _sendApiCommand(String deviceId, String action, dynamic value) async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = selectedHome?['homeid'] ?? '';
    
    final url = Uri.parse("https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod/command");
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Komut Gidiyor: $action -> $value"), duration: const Duration(milliseconds: 500)),
    );

    try {
      final session = await Amplify.Auth.fetchAuthSession();
      
      if (session is CognitoAuthSession) {
        final token = session.userPoolTokensResult.value.idToken.raw;
  
        final response = await http.post(
          url,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $token"
          },
          body: jsonEncode({
            "home_id": homeId,
            "device_id": deviceId,
            "action": action,
            "value": value,
          }),
        );
        
        if (response.statusCode == 200) {
          print("BAŞARILI: $action -> $value");
        } else {
          print("Komut reddedildi. Hata: ${response.statusCode}");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Komut reddedildi! (Hata: ${response.statusCode})"), duration: const Duration(seconds: 2), backgroundColor: Colors.redAccent),
            );
          }
        }
      }
    } catch (e) {
      print("BAĞLANTI HATASI: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ağ bağlantı hatası! Komut iletilemedi."), duration: Duration(seconds: 3), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _updateTemperature(int delta) {
    setState(() {
      _targetTemp += delta;
    });

    if (_tempDebounceTimer?.isActive ?? false) _tempDebounceTimer!.cancel();

    _tempDebounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _sendApiCommand("klima_01", "sicaklik_ayarla", _targetTemp);
    });
  }

  void _moveCurtain(int delta) {
    setState(() {
      _curtainPosition = (_curtainPosition + delta).clamp(0, 100);
      _curtainStatus = "Position: $_curtainPosition%";
    });

    if (_curtainDebounceTimer?.isActive ?? false) _curtainDebounceTimer!.cancel();

    _curtainDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      _sendApiCommand("perde_01", "perde_ayarla", _curtainPosition);
    });
  }

  void _setCurtain(int position) {
    setState(() {
      _curtainPosition = position.clamp(0, 100);
      _curtainStatus = "Position: $_curtainPosition%";
    });
    _sendApiCommand("perde_01", "perde_ayarla", _curtainPosition);
  }

  void _onBottomNavTapped(int index) {
    if (index == 0) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const DashboardScreen()), (route) => false);
    } else if (index == 1) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const EmotionHubScreen()));
    } else if (index == 2) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const MonitoringScreen()));
    } else if (index == 4) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationScreen()));
    } else if (index == 5) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 1. HEADER ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Column(
                    children: [
                      const Text("AI Emotion Hub",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: const [
                          Icon(Icons.circle, size: 8, color: AppColors.accentGreen),
                          SizedBox(width: 4),
                          Text("Living Room • Online", style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.settings, color: Colors.white), onPressed: () {}),
                ],
              ),
              const SizedBox(height: 24),

              // --- 2. AI MOOD SUGGESTION CARD ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF2C3E50), AppColors.cardDark.withOpacity(0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.purple.withOpacity(0.2), shape: BoxShape.circle),
                          child: const Icon(Icons.auto_awesome, color: Colors.purpleAccent),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("AI Mood Suggestion", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            Text("Based on evening routine", style: TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Relax profile applied."))),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text("Apply 'Relax'", style: TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- 3. MOOD ANALYSIS ---
              const Text("Mood Analysis", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                decoration: BoxDecoration(color: AppColors.cardDark, borderRadius: BorderRadius.circular(24)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("WEEKLY TRENDS", style: TextStyle(color: Colors.grey, fontSize: 10)),
                            Text("Emotion Timeline", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Icon(Icons.show_chart, color: Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      height: 160,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildChartBar("M", 40, const Color(0xFFCE93D8)),
                          _buildChartBar("T", 65, const Color(0xFF80CBC4)),
                          _buildChartBar("W", 30, const Color(0xFFCE93D8)),
                          _buildChartBar("T", 80, const Color(0xFFBA68C8), isSelected: true),
                          _buildChartBar("F", 50, const Color(0xFF80CBC4)),
                          _buildChartBar("S", 70, const Color(0xFFF48FB1)),
                          _buildChartBar("S", 45, const Color(0xFF80CBC4)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegend(const Color(0xFFCE93D8), "Relaxed"),
                        const SizedBox(width: 16),
                        _buildLegend(const Color(0xFF80CBC4), "Focused"),
                        const SizedBox(width: 16),
                        _buildLegend(const Color(0xFFF48FB1), "Excited"),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- 4. SMART LIGHTING CONTROL ---
              const Text("Smart Lighting", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppColors.cardDark, borderRadius: BorderRadius.circular(24)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb, color: _isLightOn ? _selectedLightColor : Colors.grey, size: 28),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text("Main Ceiling Light", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                Text("Philips Hue • MQTT", style: TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                        Switch(
                          value: _isLightOn,
                          activeColor: _selectedLightColor,
                          onChanged: (val) {
                            setState(() => _isLightOn = val);
                            _sendApiCommand("isik_01", "guc_ayarla", val ? "acik" : "kapali");
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildColorDot(const Color(0xFFFF5252)),
                        _buildColorDot(const Color(0xFFFFB74D)),
                        _buildColorDot(const Color(0xFF69F0AE)),
                        _buildColorDot(const Color(0xFF448AFF)),
                        _buildColorDot(const Color(0xFFE040FB)),
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[800]),
                          child: const Icon(Icons.add, color: Colors.white, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Icon(Icons.brightness_5, color: Colors.grey, size: 20),
                        Expanded(
                          child: Slider(
                            value: _brightness,
                            min: 0,
                            max: 100,
                            activeColor: _selectedLightColor,
                            inactiveColor: Colors.grey[800],
                            onChanged: (val) {
                              setState(() => _brightness = val);
                            },
                            onChangeEnd: (val) {
                              _sendApiCommand("isik_01", "parlaklik_ayarla", val.toInt());
                            },
                          ),
                        ),
                        Text("${_brightness.toInt()}%", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- 5. CURTAINS & BLINDS ---
              const Text("Curtains & Blinds", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppColors.cardDark, borderRadius: BorderRadius.circular(24)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.teal.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.curtains, color: Colors.teal),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Master Curtains", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            Text(_curtainStatus, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 100,
                            decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: (100 - _curtainPosition) <= 0 ? 1 : (100 - _curtainPosition),
                                  child: Container(color: Colors.blueGrey.withOpacity(0.3)),
                                ),
                                Container(width: 20, color: Colors.black),
                                Expanded(
                                  flex: _curtainPosition <= 0 ? 1 : _curtainPosition,
                                  child: Container(color: Colors.blueGrey.withOpacity(0.3)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          children: [
                            _buildControlBtn(Icons.keyboard_arrow_up, () => _moveCurtain(10)),
                            const SizedBox(height: 8),
                            _buildControlBtn(Icons.stop, isPrimary: true, () {
                              if (_curtainDebounceTimer?.isActive ?? false) _curtainDebounceTimer!.cancel();
                              setState(() => _curtainStatus = "Stopped at $_curtainPosition%");
                              _sendApiCommand("perde_01", "dur", "tamam");
                            }),
                            const SizedBox(height: 8),
                            _buildControlBtn(Icons.keyboard_arrow_down, () => _moveCurtain(-10)),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildPresetBtn("Open", () => _setCurtain(100)),
                        _buildPresetBtn("50%", () => _setCurtain(50)),
                        _buildPresetBtn("Close", () => _setCurtain(0)),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- 6. CLIMATE CONTROL ---
              const Text("Climate Control", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: AppColors.cardDark, borderRadius: BorderRadius.circular(30)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Inside Temp", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text("$_insideTemp°C", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text("Humidity", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text("$_insideHumidity%", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(40)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildTempBtn(Icons.remove, () => _updateTemperature(-1)),
                          Column(
                            children: [
                              const Text("SET TO", style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.5)),
                              Text("$_targetTemp°C", style: const TextStyle(color: AppColors.primaryBlue, fontSize: 24, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          _buildTempBtn(Icons.add, () => _updateTemperature(1)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Mode: $_climateMode", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildModeBtn("Cool", Icons.ac_unit, Colors.blue),
                        _buildModeBtn("Heat", Icons.local_fire_department, Colors.orange),
                        _buildModeBtn("Fan", Icons.air, Colors.grey),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.cardDark,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        currentIndex: 3,
        onTap: _onBottomNavTapped,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Dash'),
          BottomNavigationBarItem(icon: Icon(Icons.sentiment_satisfied_alt), label: 'Emotion'),
          BottomNavigationBarItem(icon: Icon(Icons.security), label: 'Security'),
          BottomNavigationBarItem(icon: Icon(Icons.devices), label: 'Devices'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  // --- YARDIMCI WIDGET'LAR ---
  Widget _buildChartBar(String day, double height, Color color, {bool isSelected = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 8, height: height,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(height: 12),
        Text(day, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
      ],
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }

  Widget _buildColorDot(Color color) {
    bool isSelected = _selectedLightColor == color;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedLightColor = color);
        _sendApiCommand("isik_01", "renk_ayarla", color.value.toRadixString(16));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: isSelected ? 40 : 32, height: isSelected ? 40 : 32,
        decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
      ),
    );
  }

  Widget _buildControlBtn(IconData icon, VoidCallback? onTap, {bool isPrimary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: isPrimary ? AppColors.primaryBlue : Colors.grey[800], shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  Widget _buildPresetBtn(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }

  Widget _buildTempBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  Widget _buildModeBtn(String text, IconData icon, Color color) {
    bool isSelected = _climateMode == text;
    return GestureDetector(
      onTap: () {
        setState(() => _climateMode = text);
        _sendApiCommand("klima_01", "mod_ayarla", text);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryBlue : Colors.transparent,
          border: Border.all(color: isSelected ? AppColors.primaryBlue : Colors.grey[800]!),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}