import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/home_provider.dart';
import '../../services/api_service.dart';

class DeviceControlScreen extends ConsumerStatefulWidget {
  const DeviceControlScreen({super.key});

  @override
  ConsumerState<DeviceControlScreen> createState() => _DeviceControlScreenState();
}

class _DeviceControlScreenState extends ConsumerState<DeviceControlScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  
  // Dynamic States
  List<dynamic> _devices = [];
  final Map<String, Map<String, dynamic>> _deviceStates = {};
  bool _isLoading = true;

  // Timers
  final Map<String, Timer?> _debounceTimers = {};
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
    for (final timer in _debounceTimers.values) {
      timer?.cancel();
    }
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
      _fetchDevices(); // Also fetch actuators from the table every 5 seconds
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
        
        // Initialize local states from fetched properties, but PRESERVE sensor data if already fetched
        for (var device in _devices) {
          String id = device['deviceid'];
          if (_deviceStates[id] == null) {
            _deviceStates[id] = {};
          }
          
          List<dynamic> props = device['properties'] ?? [];
          for (var prop in props) {
            String pName = prop['property_name'];
            var val = prop['current_value'];

            // Advanced default value assignment (if value came null from DB)
            if (val == null || val == "null" || val == "") {
              if (pName == 'power') {
                val = 'off';
              } else if (pName == 'brightness' || pName == 'volume') {
                val = 50;
              } else if (pName == 'color') {
                val = '#FFFFFF';
              } else if (pName == 'playback') {
                val = 'stop'; // Speaker default off
              } else if (pName == 'channel') {
                val = 1;
              }
            } else {
              // If a value came through, normalize by lowercasing (ON -> on)
              if (val is String && (val.toUpperCase() == "ON" || val.toUpperCase() == "OFF")) {
                val = val.toLowerCase();
              } else if (val is String && double.tryParse(val) != null && !pName.contains("color")) {
                val = double.parse(val);
              }
            }

            // Only save if value is not null, or we assigned a default (named properties)
            // This way fresh data from another source (sensor) isn't OVERWRITTEN by null.
            if (val != null && val != "null" && val != "") {
              _deviceStates[id]![pName] = val;
            }
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
      
      if (mounted) {
        setState(() {
          // Save each incoming sensor data into state by its device ID
          for (var entry in sensors.entries) {
            String devId = entry.key;
            var deviceData = entry.value;

            if (deviceData is Map) {
              if (_deviceStates[devId] == null) {
                _deviceStates[devId] = {};
              }
              
              if (deviceData.containsKey('temperature')) {
                _deviceStates[devId]!['temperature'] = deviceData['temperature'];
              }
              if (deviceData.containsKey('humidity')) {
                _deviceStates[devId]!['humidity'] = deviceData['humidity'];
              }
            }
          }
        });
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
  void _updateDeviceState(String deviceId, String property, dynamic value) {
    setState(() {
      if (_deviceStates[deviceId] == null) _deviceStates[deviceId] = {};
      _deviceStates[deviceId]![property] = value;
    });

    // Key the debounce by device+property so changing brightness then color
    // on the same LED does not cancel the pending brightness send.
    final key = '$deviceId:$property';
    if (_debounceTimers[key]?.isActive ?? false) _debounceTimers[key]!.cancel();
    _debounceTimers[key] = Timer(const Duration(milliseconds: 500), () {
      _sendDynamicCommand(deviceId, property, value);
    });
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: Stack(
        children: [
          // Premium gradient blobs — only in dark mode for the frosted look.
          // The light theme uses a clean flat background to match the rest of
          // the app.
          if (isDark) ...[
            Positioned(
              top: -100,
              left: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryBlue.withValues(alpha: 0.15),
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
                  color: AppColors.accentGreen.withValues(alpha: 0.1),
                ),
              ),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(color: Colors.transparent),
            ),
          ],

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
                      Center(child: Text("No devices found.", style: TextStyle(color: AppColors.textSub(context)))),
                    ..._devices.where((device) {
                      // Hide gas and vibration sensors entirely — their alerts
                      // arrive via push notifications instead of a live tile.
                      final t = (device['device_type'] ?? '').toString().toLowerCase();
                      final n = (device['device_name'] ?? '').toString().toLowerCase();
                      final isGas = n.contains('gas') || n.contains('gaz') || t.contains('gas');
                      final isQuake = n.contains('deprem') || n.contains('earthquake') || t.contains('vibration');
                      return !isGas && !isQuake;
                    }).map((device) {
                      Widget card;
                      String type = (device['device_type'] ?? '').toString().toLowerCase();
                      String name = (device['device_name'] ?? '').toString().toLowerCase();

                      if (type == 'climate' || type == 'ac') {
                        card = _buildClimateCard(device);
                      } else if (type == 'tv' || name.contains('tv') || name.contains('television')) {
                        card = _buildTvCard(device);
                      } else if (type == 'light' || type == 'led' || type == 'led_strip') {
                        card = _buildLightingCard(device);
                      } else if (type == 'speaker' || name.contains('speaker')) {
                        card = _buildSpeakerCard(device);
                      } else if (type == 'rfid' || name.contains('rfid') || name.contains('door')) {
                        card = _buildRfidCard(device);
                      } else if (name.contains('temp') || name.contains('nem') || type.contains('temp')) {
                        card = _buildTempHumidityCard(device);
                      } else {
                        card = _buildGenericCard(device);
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: card,
                      );
                    }),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ====================== UI COMPONENTS ====================== //

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(24)}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // In dark mode keep the frosted-glass look; in light mode use a clean
    // solid card with a soft shadow that matches the rest of the app.
    if (isDark) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: AppColors.card(context).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.borderCol(context), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        ),
      );
    }
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderCol(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
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
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderCol(context)),
            ),
            child: Icon(Icons.arrow_back_ios_new, color: AppColors.text(context), size: 20),
          ),
        ),
        Column(
          children: [
            Text("Living Room", style: TextStyle(color: AppColors.text(context), fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accentGreen, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text("4 Devices Connected", style: TextStyle(color: AppColors.textSub(context), fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card(context).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderCol(context)),
          ),
          child: Icon(Icons.more_vert, color: AppColors.text(context), size: 20),
        ),
      ],
    );
  }
  Widget _buildClimateCard(Map<String, dynamic> device) {
    String deviceId = device['deviceid'];
    String deviceName = device['device_name'] ?? 'Air Conditioner';
    Map<String, dynamic> state = _deviceStates[deviceId] ?? {};
    
    // Actuator power: on | off
    bool isEngineOn = state['power'] == 'on';
    
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(color: AppColors.text(context), fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(isEngineOn ? "Airflow Active" : "Standby Mode", style: const TextStyle(color: AppColors.primaryBlue, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: isEngineOn ? AppColors.primaryBlue.withValues(alpha: 0.3) : AppColors.borderCol(context), shape: BoxShape.circle),
                child: Icon(Icons.air, color: isEngineOn ? AppColors.primaryBlue : Colors.grey, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildModernIconButton(Icons.power_settings_new, () {
                _updateDeviceState(deviceId, 'power', isEngineOn ? 'off' : 'on');
              }),
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildLightingCard(Map<String, dynamic> device) {
    String deviceId = device['deviceid'];
    String deviceName = device['device_name'] ?? 'LED Strip';
    Map<String, dynamic> state = _deviceStates[deviceId] ?? {};
    
    // Actuator power: on | off
    // brightness: 0-100
    // color: #HEXCODE
    bool isLightOn = state['power'] == 'on';
    int brightness = state['brightness'] != null ? (state['brightness'] is num ? state['brightness'].toInt() : int.tryParse(state['brightness'].toString()) ?? 50) : 50;
    String hexColor = state['color'] ?? '#FFFFFF';
    Color lightColor = _parseHex(hexColor);

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
                        color: isLightOn ? lightColor.withValues(alpha: 0.2) : AppColors.borderCol(context),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.lightbulb, color: isLightOn ? lightColor : Colors.grey, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
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
                onChanged: (val) => _updateDeviceState(deviceId, 'power', val ? 'on' : 'off'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildHueSpectrum(deviceId, hexColor),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.brightness_low, color: AppColors.textSub(context), size: 20),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: lightColor,
                    inactiveTrackColor: AppColors.borderCol(context),
                    thumbColor: lightColor,
                  ),
                  child: Slider(
                    value: brightness.toDouble(),
                    min: 0,
                    max: 100,
                    onChanged: (val) => _updateDeviceState(deviceId, 'brightness', val.toInt().toString()),
                  ),
                ),
              ),
              Icon(Icons.brightness_high, color: AppColors.textSub(context), size: 20),
              const SizedBox(width: 8),
              SizedBox(width: 36, child: Text('$brightness%', style: TextStyle(color: AppColors.text(context), fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerCard(Map<String, dynamic> device) {
    String deviceId = device['deviceid'];
    String deviceName = device['device_name'] ?? 'Smart Speaker';
    Map<String, dynamic> state = _deviceStates[deviceId] ?? {};
    
    bool isEngineOn = state['power'] == 'on';
    int volume = state['volume'] != null ? (state['volume'] is num ? state['volume'].toInt() : int.tryParse(state['volume'].toString()) ?? 50) : 50;

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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.pinkAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
                      child: Icon(Icons.speaker_group, color: isEngineOn ? Colors.pinkAccent : Colors.grey, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(isEngineOn ? "Volume: $volume%" : "Offline", style: TextStyle(color: isEngineOn ? Colors.pinkAccent : Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isEngineOn,
                activeColor: Colors.pinkAccent,
                onChanged: (val) => _updateDeviceState(deviceId, 'power', val ? 'on' : 'off'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildModernIconButton(Icons.play_arrow, () => _updateDeviceState(deviceId, 'playback', 'play')),
              _buildModernIconButton(Icons.pause, () => _updateDeviceState(deviceId, 'playback', 'pause')),
              _buildModernIconButton(Icons.stop, () => _updateDeviceState(deviceId, 'playback', 'stop')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.volume_down, color: AppColors.textSub(context), size: 20),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: Colors.pinkAccent,
                    inactiveTrackColor: AppColors.borderCol(context),
                    thumbColor: Colors.pinkAccent,
                  ),
                  child: Slider(
                    value: volume.toDouble(),
                    min: 0,
                    max: 100,
                    onChanged: (val) => _updateDeviceState(deviceId, 'volume', val.toInt().toString()),
                  ),
                ),
              ),
              Icon(Icons.volume_up, color: AppColors.textSub(context), size: 20),
              const SizedBox(width: 8),
              SizedBox(width: 36, child: Text('$volume%', style: TextStyle(color: AppColors.text(context), fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTvCard(Map<String, dynamic> device) {
    String deviceId = device['deviceid'];
    String deviceName = device['device_name'] ?? 'Smart TV';
    Map<String, dynamic> state = _deviceStates[deviceId] ?? {};

    bool isOn = state['power'] == 'on';
    int volume = state['volume'] != null
        ? (state['volume'] is num
            ? state['volume'].toInt()
            : int.tryParse(state['volume'].toString()) ?? 30)
        : 30;
    int channel = state['channel'] != null
        ? (state['channel'] is num
            ? state['channel'].toInt()
            : int.tryParse(state['channel'].toString()) ?? 1)
        : 1;

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
                        color: isOn
                            ? AppColors.primaryBlue.withValues(alpha: 0.2)
                            : AppColors.borderCol(context),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.tv,
                          color: isOn ? AppColors.primaryBlue : Colors.grey,
                          size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(deviceName,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                  color: AppColors.text(context),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                                color: isOn
                                    ? AppColors.primaryBlue
                                    : Colors.grey,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                            child: Text(isOn
                                ? "Ch $channel · Vol $volume%"
                                : "Standby"),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isOn,
                activeThumbColor: AppColors.primaryBlue,
                onChanged: (val) =>
                    _updateDeviceState(deviceId, 'power', val ? 'on' : 'off'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildModernIconButton(Icons.keyboard_arrow_down, () {
                int next = (channel - 1).clamp(1, 999);
                _updateDeviceState(deviceId, 'channel', next.toString());
              }),
              Column(
                children: [
                  Text("Channel",
                      style: TextStyle(
                          color: AppColors.textSub(context), fontSize: 11)),
                  const SizedBox(height: 4),
                  Text("$channel",
                      style: TextStyle(
                          color: AppColors.text(context),
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              _buildModernIconButton(Icons.keyboard_arrow_up, () {
                int next = (channel + 1).clamp(1, 999);
                _updateDeviceState(deviceId, 'channel', next.toString());
              }),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.volume_down,
                  color: AppColors.textSub(context), size: 20),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: AppColors.primaryBlue,
                    inactiveTrackColor: AppColors.borderCol(context),
                    thumbColor: AppColors.primaryBlue,
                  ),
                  child: Slider(
                    value: volume.toDouble(),
                    min: 0,
                    max: 100,
                    onChanged: (val) => _updateDeviceState(
                        deviceId, 'volume', val.toInt().toString()),
                  ),
                ),
              ),
              Icon(Icons.volume_up,
                  color: AppColors.textSub(context), size: 20),
              const SizedBox(width: 8),
              SizedBox(width: 36, child: Text('$volume%', style: TextStyle(color: AppColors.text(context), fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRfidCard(Map<String, dynamic> device) {
    String deviceId = device['deviceid'];
    String deviceName = device['device_name'] ?? 'RFID Reader';
    Map<String, dynamic> state = _deviceStates[deviceId] ?? {};
    
    String status = (state['status'] ?? 'idle').toString().toLowerCase();
    String lastScan = (state['last_scan'] ?? 'N/A').toString();
    
    Color statusColor = status == 'active' ? AppColors.accentGreen : Colors.grey;
    String statusText = status == 'active' ? "Active" : "Idle";

    return _buildGlassCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(Icons.nfc, color: statusColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text("Status: $statusText", style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("Last Scan:", style: TextStyle(color: AppColors.textSub(context), fontSize: 12)),
              Text(lastScan, style: TextStyle(color: AppColors.text(context), fontSize: 14, fontWeight: FontWeight.w500)),
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
    
    bool isEngineOn = state['power'] == 'on';
    
    IconData iconData = Icons.device_hub;
    Color iconColor = Colors.purpleAccent;
    String nameLr = deviceName.toLowerCase();

    if (nameLr.contains('door')) {
      iconData = Icons.door_front_door;
    } else if (nameLr.contains('window')) {
      iconData = Icons.window;
    } else if (nameLr.contains('fan')) {
      iconData = Icons.mode_fan_off;
      iconColor = Colors.blueAccent;
    } else if (nameLr.contains('plug')) {
      iconData = Icons.power;
    } else if (nameLr.contains('stove')) {
      iconData = Icons.soup_kitchen;
      iconColor = Colors.deepOrangeAccent;
    }

    return _buildGlassCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
            child: Icon(iconData, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
                Text(isEngineOn ? 'Power: ON' : 'Power: OFF', style: TextStyle(color: iconColor, fontSize: 13)),
              ],
            ),
          ),
          Switch.adaptive(
            value: isEngineOn,
            activeColor: iconColor,
            onChanged: (val) => _updateDeviceState(deviceId, 'power', val ? 'on' : 'off'),
          ),
        ],
      ),
    );
  }

  Widget _buildTempHumidityCard(Map<String, dynamic> device) {
    String deviceName = device['device_name'] ?? 'Temperature & Humidity';
    Map<String, dynamic> state = _deviceStates[device['deviceid']] ?? {};
    
    String temp = state['temperature']?.toString() ?? "--";
    String hum = state['humidity']?.toString() ?? "--";

    return _buildGlassCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.thermostat, color: Colors.orangeAccent, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accentGreen, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text("Status: Working", style: TextStyle(color: AppColors.textSub(context), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("$temp°C", style: const TextStyle(color: Colors.orangeAccent, fontSize: 24, fontWeight: FontWeight.bold)),
              Text("$hum%", style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  // --- Color helpers --- //

  Color _parseHex(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return Colors.white;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return Colors.white;
    return Color(0xFF000000 | v);
  }

  String _hexFromColor(Color c) {
    final argb = c.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    String two(int n) => n.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${two(r)}${two(g)}${two(b)}';
  }

  /// Returns hue 0..360 for a hex like "#FF8800". For grayscale (R==G==B)
  /// returns -1 — caller should treat that as "white selected, no hue".
  double _hueFromHex(String hex) {
    final c = _parseHex(hex);
    final argb = c.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    if (r == g && g == b) return -1;
    return HSVColor.fromColor(Color.fromARGB(255, r, g, b)).hue;
  }

  void _onHuePicked(String deviceId, double dx, double width) {
    final t = (dx / width).clamp(0.0, 1.0);
    final hue = t * 360.0;
    final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
    _updateDeviceState(deviceId, 'color', _hexFromColor(color));
  }

  Widget _buildHueSpectrum(String deviceId, String currentHex) {
    final isWhite = _hueFromHex(currentHex) < 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Reserve space for the white pill on the right.
        const whitePillWidth = 44.0;
        const gap = 12.0;
        final barWidth = constraints.maxWidth - whitePillWidth - gap;
        final hue = _hueFromHex(currentHex);
        final indicatorX = hue < 0 ? -1.0 : (hue / 360.0) * barWidth;

        return Row(
          children: [
            SizedBox(
              width: barWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) =>
                    _onHuePicked(deviceId, d.localPosition.dx, barWidth),
                onPanDown: (d) =>
                    _onHuePicked(deviceId, d.localPosition.dx, barWidth),
                onPanUpdate: (d) =>
                    _onHuePicked(deviceId, d.localPosition.dx, barWidth),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 28,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFF0000),
                            Color(0xFFFFFF00),
                            Color(0xFF00FF00),
                            Color(0xFF00FFFF),
                            Color(0xFF0000FF),
                            Color(0xFFFF00FF),
                            Color(0xFFFF0000),
                          ],
                        ),
                        border: Border.all(
                            color: AppColors.borderCol(context), width: 1),
                      ),
                    ),
                    if (indicatorX >= 0)
                      Positioned(
                        left: (indicatorX - 8).clamp(0.0, barWidth - 16),
                        child: Container(
                          width: 16,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            border: Border.all(
                                color: AppColors.text(context), width: 3),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: gap),
            GestureDetector(
              onTap: () =>
                  _updateDeviceState(deviceId, 'color', '#FFFFFF'),
              child: Container(
                width: whitePillWidth,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isWhite
                        ? AppColors.primaryBlue
                        : AppColors.borderCol(context),
                    width: isWhite ? 2.5 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'W',
                  style: TextStyle(
                    color: isWhite
                        ? AppColors.primaryBlue
                        : Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- Premium Mini Widgets --- //

  Widget _buildModernIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          color: AppColors.card(context),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.borderCol(context)),
        ),
        child: Icon(icon, color: AppColors.text(context), size: 28),
      ),
    );
  }

}