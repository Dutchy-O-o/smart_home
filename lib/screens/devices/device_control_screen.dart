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
  
  // States
  bool _isLightOn = true;
  double _brightness = 58.0;
  Color _selectedLightColor = const Color(0xFF448AFF);

  int _curtainPosition = 60;
  
  int _targetTemp = 20;
  String _climateMode = "Cool";

  String _insideTemp = "--";
  String _insideHumidity = "--";

  // Timers
  Timer? _tempDebounceTimer;
  Timer? _curtainDebounceTimer;
  Timer? _brightnessDebounceTimer;
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

    _fetchLatestSensorData();
    _startPollingTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fadeController.dispose();
    _dataPollingTimer?.cancel();
    _tempDebounceTimer?.cancel();
    _curtainDebounceTimer?.cancel();
    _brightnessDebounceTimer?.cancel();
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

  // Action Handlers
  void _toggleLight(bool val) {
    setState(() => _isLightOn = val);
    _sendDynamicCommand("dev_led_01", "state", val ? "ON" : "OFF");
  }

  void _updateBrightness(double val) {
    setState(() => _brightness = val);
    if (_brightnessDebounceTimer?.isActive ?? false) _brightnessDebounceTimer!.cancel();
    _brightnessDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _sendDynamicCommand("dev_led_01", "brightness", val.toInt());
    });
  }

  void _updateColor(Color color) {
    setState(() => _selectedLightColor = color);
    String hex = "#${color.value.toRadixString(16).substring(2).toUpperCase()}";
    _sendDynamicCommand("dev_led_01", "color", hex);
  }

  void _updateTemperature(int delta) {
    setState(() => _targetTemp += delta);
    if (_tempDebounceTimer?.isActive ?? false) _tempDebounceTimer!.cancel();
    _tempDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      _sendDynamicCommand("dev_ac_01", "temperature", _targetTemp);
    });
  }

  void _setClimateMode(String mode) {
    setState(() => _climateMode = mode);
    _sendDynamicCommand("dev_ac_01", "mode", mode);
  }

  void _setCurtain(int position) {
    setState(() => _curtainPosition = position.clamp(0, 100));
    if (_curtainDebounceTimer?.isActive ?? false) _curtainDebounceTimer!.cancel();
    _curtainDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _sendDynamicCommand("dev_blinds_01", "position", _curtainPosition);
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
                color: _selectedLightColor.withOpacity(0.15),
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
                color: AppColors.primaryBlue.withOpacity(0.1),
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
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
                    _buildClimateCard(),
                    const SizedBox(height: 24),
                    _buildLightingCard(),
                    const SizedBox(height: 24),
                    _buildSmartBlindsCard(),
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

  Widget _buildClimateCard() {
    return _buildGlassCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Climate", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text("$_insideTemp°C • $_insideHumidity%", style: const TextStyle(color: AppColors.primaryBlue, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
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
              _buildModernIconButton(Icons.remove, () => _updateTemperature(-1)),
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
                      Text("$_targetTemp°", style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w300)),
                      const Text("TARGET", style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              _buildModernIconButton(Icons.add, () => _updateTemperature(1)),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPillToggle("Cool", Icons.ac_unit, Colors.blue),
              _buildPillToggle("Heat", Icons.local_fire_department, Colors.orange),
              _buildPillToggle("Fan", Icons.cyclone, Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLightingCard() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isLightOn ? _selectedLightColor.withOpacity(0.2) : Colors.white10,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.lightbulb, color: _isLightOn ? _selectedLightColor : Colors.grey, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Ambient Light", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(color: _isLightOn ? _selectedLightColor : Colors.grey, fontSize: 13, fontWeight: FontWeight.w600),
                        child: Text(_isLightOn ? "Turned On" : "Turned Off"),
                      ),
                    ],
                  ),
                ],
              ),
              Switch.adaptive(
                value: _isLightOn,
                activeColor: _selectedLightColor,
                activeTrackColor: _selectedLightColor.withOpacity(0.4),
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.white10,
                onChanged: _toggleLight,
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
                    activeTrackColor: _isLightOn ? _selectedLightColor : Colors.grey,
                    inactiveTrackColor: Colors.white10,
                    thumbColor: Colors.white,
                    overlayColor: _selectedLightColor.withOpacity(0.2),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10, elevation: 5),
                  ),
                  child: Slider(
                    value: _brightness,
                    min: 0,
                    max: 100,
                    onChanged: _isLightOn ? _updateBrightness : null,
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
              _buildColorSelector(const Color(0xFFFF5252)),
              _buildColorSelector(const Color(0xFFFFB74D)),
              _buildColorSelector(const Color(0xFF69F0AE)),
              _buildColorSelector(const Color(0xFF448AFF)),
              _buildColorSelector(const Color(0xFFE040FB)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmartBlindsCard() {
    return _buildGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.tealAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.blinds, color: Colors.tealAccent, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Smart Blinds", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text("Position: $_curtainPosition%", style: const TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
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
                    value: _curtainPosition.toDouble(),
                    min: 0,
                    max: 100,
                    onChanged: (val) => _setCurtain(val.toInt()),
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

  Widget _buildPillToggle(String text, IconData icon, Color activeColor) {
    bool isSelected = _climateMode == text;
    return GestureDetector(
      onTap: () => _setClimateMode(text),
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

  Widget _buildColorSelector(Color color) {
    bool isSelected = _selectedLightColor == color;
    return GestureDetector(
      onTap: () => _isLightOn ? _updateColor(color) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(_isLightOn ? 1.0 : 0.3),
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 3) : Border.all(color: Colors.transparent),
          boxShadow: isSelected && _isLightOn ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 15, spreadRadius: 2)] : [],
        ),
      ),
    );
  }
}