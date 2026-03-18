import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import '../../constants/app_colors.dart';
import '../../providers/home_provider.dart';
import '../../services/api_service.dart';
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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  
  // Dynamic States
  List<dynamic> _devices = [];
  Map<String, Map<String, dynamic>> _deviceStates = {};
  bool _isLoading = true;

  String _insideTemp = "--";
  String _insideHumidity = "--";

  // Timers
  Map<String, Timer?> _debounceTimers = {};
  Timer? _dataPollingTimer;

  // Animation Controller
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic);
    _fadeController.forward();

    _fetchDevices();
    _fetchLatestSensorData();
    _startPollingTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fadeController.dispose();
    _dataPollingTimer?.cancel();
    _debounceTimers.values.forEach((timer) => timer?.cancel());
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

  Future<void> _fetchDevices() async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = selectedHome?['homeid'];
    if (homeId == null) return;

    final devices = await ApiService.fetchDevices(homeId);
    if (devices != null && mounted) {
      setState(() {
        _devices = devices;
        _isLoading = false;
        
        // Initialize local states from fetched properties
        for (var device in _devices) {
          String id = device['deviceid'];
          _deviceStates[id] = {};
          
          List<dynamic> props = device['properties'] ?? [];
          for (var prop in props) {
            String pName = prop['property_name'];
            var val = prop['current_value'];
            // Parsing strings from DB
            if (val == "ON") val = true;
            else if (val == "OFF") val = false;
            else if (val is String && double.tryParse(val) != null && !pName.contains("color")) {
               val = double.parse(val);
            }
            _deviceStates[id]![pName] = val;
          }
        }
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchLatestSensorData() async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = selectedHome?['homeid'];
    if (homeId == null) return;

    final data = await ApiService.fetchSensors(homeId);
    if (data != null && data['sensors'] != null) {
      final sensors = data['sensors'] as Map<String, dynamic>;
      
      for (var deviceData in sensors.values) {
        if (deviceData is Map && deviceData.containsKey('temperature') && deviceData.containsKey('humidity')) {
          if (mounted) {
            setState(() {
              _insideTemp = deviceData['temperature'].toString();
              _insideHumidity = deviceData['humidity'].toString();
            });
          }
          break;
        }
      }
    }
  }

  Future<void> _sendDynamicCommand(String deviceId, String action, dynamic value) async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = selectedHome?['homeid'];
    if (homeId == null) return;

    final success = await ApiService.sendCommand(
      homeId: homeId,
      deviceId: deviceId,
      action: action,
      value: value,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to send command. Check connection."),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Dynamic Action Handler
  void _updateDeviceState(String deviceId, String action, dynamic value) {
    if (!mounted) return;
    setState(() {
      _deviceStates[deviceId] ??= {};
      _deviceStates[deviceId]![action] = value;
    });

    String dbValue = value is bool ? (value ? "ON" : "OFF") : value.toString();
    
    // Debounce mapping
    String key = '${deviceId}_$action';
    if (_debounceTimers[key]?.isActive ?? false) _debounceTimers[key]!.cancel();
    _debounceTimers[key] = Timer(const Duration(milliseconds: 500), () {
      _sendDynamicCommand(deviceId, action, dbValue);
    });
  }

  void _onBottomNavTapped(int index) {
    final routes = [
      () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const DashboardScreen()), (r) => false),
      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmotionHubScreen())),
      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MonitoringScreen())),
      () {}, // Self
      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen())),
      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
    ];
    routes.elementAt(index)();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Premium Background Gradient Effects
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryBlue.withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentGreen.withOpacity(0.1),
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
            child: Container(color: Colors.transparent),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue))
                : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
                    if (_devices.isEmpty)
                      const Center(child: Text("No devices found.", style: TextStyle(color: Colors.grey))),
                    ..._devices.map((device) {
                      Widget card;
                      String type = device['device_type'] ?? '';
                      if (type == 'climate' || type == 'ac') {
                        card = _buildClimateCard(device);
                      } else if (type == 'light' || type == 'led') {
                        card = _buildLightingCard(device);
                      } else if (type == 'blinds' || type == 'curtain') {
                        card = _buildSmartBlindsCard(device);
                      } else {
                        // generic fallback
                        card = _buildGenericCard(device);
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: card,
                      );
                    }).toList(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildPremiumBottomNav(),
    );
  }

  // ====================== UI COMPONENTS ====================== //

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(24)}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.cardDark.withOpacity(0.6),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardDark.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          ),
        ),
        Column(
          children: [
            const Text("Living Room", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accentGreen, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text("4 Devices Connected", style: TextStyle(color: AppColors.textGrey, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardDark.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: const Icon(Icons.more_vert, color: Colors.white, size: 20),
        ),
      ],
    );
  }

  Widget _buildClimateCard(Map<String, dynamic> device) {
    String deviceId = device['deviceid'];
    String deviceName = device['device_name'] ?? 'Climate Options';
    Map<String, dynamic> state = _deviceStates[deviceId] ?? {};
    
    int currentTemp = (state['temperature'] ?? 20).toInt();
    String currentMode = state['mode'] ?? "Cool";

    return _buildGlassCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text("$_insideTemp°C • $_insideHumidity%", style: const TextStyle(color: AppColors.primaryBlue, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.primaryBlue.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.air, color: AppColors.primaryBlue, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildModernIconButton(Icons.remove, () => _updateDeviceState(deviceId, 'temperature', currentTemp - 1)),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.background.withOpacity(0.5),
                  border: Border.all(color: AppColors.primaryBlue.withOpacity(0.5), width: 3),
                  boxShadow: [
                    BoxShadow(color: AppColors.primaryBlue.withOpacity(0.2), blurRadius: 20, spreadRadius: 5),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("$currentTemp°", style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w300)),
                      const Text("TARGET", style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              _buildModernIconButton(Icons.add, () => _updateDeviceState(deviceId, 'temperature', currentTemp + 1)),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildDynamicPillToggle("Cool", Icons.ac_unit, Colors.blue, currentMode, () => _updateDeviceState(deviceId, 'mode', 'Cool')),
              _buildDynamicPillToggle("Heat", Icons.local_fire_department, Colors.orange, currentMode, () => _updateDeviceState(deviceId, 'mode', 'Heat')),
              _buildDynamicPillToggle("Fan", Icons.cyclone, Colors.white, currentMode, () => _updateDeviceState(deviceId, 'mode', 'Fan')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLightingCard(Map<String, dynamic> device) {
    String deviceId = device['deviceid'];
    String deviceName = device['device_name'] ?? 'Ambient Light';
    Map<String, dynamic> state = _deviceStates[deviceId] ?? {};
    
    // Parse light states
    bool isLightOn = state['state'] == true || state['state'] == "ON";
    double currentBrightness = (state['brightness'] ?? 50.0).toDouble();
    String hexColor = state['color'] ?? "#448AFF";
    Color lightColor = const Color(0xFF448AFF);
    try { lightColor = Color(int.parse(hexColor.replaceFirst('#', '0xFF'))); } catch (e) {}

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isLightOn ? lightColor.withOpacity(0.2) : Colors.white10,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.lightbulb, color: isLightOn ? lightColor : Colors.grey, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(color: isLightOn ? lightColor : Colors.grey, fontSize: 13, fontWeight: FontWeight.w600),
                            child: Text(isLightOn ? "Turned On" : "Turned Off"),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: isLightOn,
                activeColor: lightColor,
                activeTrackColor: lightColor.withOpacity(0.4),
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.white10,
                onChanged: (val) => _updateDeviceState(deviceId, 'state', val),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text("Brightness", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          Row(
            children: [
              Icon(Icons.brightness_low, color: Colors.grey[400], size: 20),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: isLightOn ? lightColor : Colors.grey,
                    inactiveTrackColor: Colors.white10,
                    thumbColor: Colors.white,
                    overlayColor: lightColor.withOpacity(0.2),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10, elevation: 5),
                  ),
                  child: Slider(
                    value: currentBrightness,
                    min: 0,
                    max: 100,
                    onChanged: isLightOn ? (val) => _updateDeviceState(deviceId, 'brightness', val.toInt()) : null,
                  ),
                ),
              ),
              Icon(Icons.brightness_high, color: Colors.grey[400], size: 20),
            ],
          ),
          const SizedBox(height: 24),
          const Text("Colors", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDynamicColorSelector(const Color(0xFFFF5252), deviceId, lightColor),
              _buildDynamicColorSelector(const Color(0xFFFFB74D), deviceId, lightColor),
              _buildDynamicColorSelector(const Color(0xFF69F0AE), deviceId, lightColor),
              _buildDynamicColorSelector(const Color(0xFF448AFF), deviceId, lightColor),
              _buildDynamicColorSelector(const Color(0xFFE040FB), deviceId, lightColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmartBlindsCard(Map<String, dynamic> device) {
    String deviceId = device['deviceid'];
    String deviceName = device['device_name'] ?? 'Smart Blinds';
    Map<String, dynamic> state = _deviceStates[deviceId] ?? {};
    int currentPosition = (state['position'] ?? 60).toInt();

    return _buildGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.tealAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.blinds, color: Colors.tealAccent, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          Text("Position: $currentPosition%", style: const TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text("0%", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 12,
                    activeTrackColor: Colors.tealAccent.withOpacity(0.8),
                    inactiveTrackColor: Colors.white10,
                    thumbColor: Colors.white,
                    overlayColor: Colors.tealAccent.withOpacity(0.2),
                    trackShape: const RoundedRectSliderTrackShape(),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10, elevation: 5),
                  ),
                  child: Slider(
                    value: currentPosition.toDouble(),
                    min: 0,
                    max: 100,
                    onChanged: (val) => _updateDeviceState(deviceId, 'position', val.toInt()),
                  ),
                ),
              ),
              Text("100%", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGenericCard(Map<String, dynamic> device) {
    String deviceId = device['deviceid'];
    String deviceName = device['device_name'] ?? 'Device';
    Map<String, dynamic> state = _deviceStates[deviceId] ?? {};
    bool isEngineOn = state['state'] == true || state['state'] == "ON";

    return _buildGlassCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.purpleAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.device_hub, color: Colors.purpleAccent, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text(isEngineOn ? 'Power: ON' : 'Power: OFF', style: const TextStyle(color: Colors.purpleAccent, fontSize: 13)),
              ],
            ),
          ),
          Switch.adaptive(
            value: isEngineOn,
            activeColor: Colors.purpleAccent,
            onChanged: (val) => _updateDeviceState(deviceId, 'state', val),
          ),
        ],
      ),
    );
  }

  // --- Premium Mini Widgets --- //

  Widget _buildPremiumBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: const Border(top: BorderSide(color: Colors.white10)),
      ),
      child: BottomNavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: Colors.grey[600],
        type: BottomNavigationBarType.fixed,
        currentIndex: 3,
        onTap: _onBottomNavTapped,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Dash'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'AI Hub'),
          BottomNavigationBarItem(icon: Icon(Icons.videocam_outlined), label: 'CCTV'),
          BottomNavigationBarItem(icon: Icon(Icons.tune_rounded), label: 'Control'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_none_rounded), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildModernIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white10),
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildDynamicPillToggle(String text, IconData icon, Color activeColor, String currentMode, VoidCallback onTap) {
    bool isSelected = currentMode == text;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: isSelected ? activeColor.withOpacity(0.5) : Colors.white10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? activeColor : Colors.grey),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(color: isSelected ? activeColor : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicColorSelector(Color color, String deviceId, Color selectedColor) {
    bool isSelected = selectedColor.value == color.value;
    return GestureDetector(
      onTap: () {
        String hex = "#${color.value.toRadixString(16).substring(2).toUpperCase()}";
        _updateDeviceState(deviceId, 'color', hex);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 45, height: 45,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 3) : Border.all(color: Colors.transparent),
          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)] : [],
        ),
      ),
    );
  }

}