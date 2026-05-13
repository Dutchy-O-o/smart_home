import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/device_state_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/speaker_provider.dart';
import '../../services/api_service.dart';
import '../../services/sensor_history_service.dart';
import '../../services/spotify/spotify_api_client.dart';
import '../../widgets/led_color_picker.dart';
import '../../widgets/temp_humidity_card.dart';
import '../ai_hub/widgets/mood_tracks_list.dart' show kSpeakerNamePrefix;
import '../../theme/app_spacing.dart';

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
  // Shared sensor history (same key as the dashboard) so the climate
  // sparkline matches across screens. Loaded lazily on first sensor fetch.
  List<SensorReading> _sensorHistory = const [];
  bool _isLoading = true;

  // Timers
  final Map<String, Timer?> _debounceTimers = {};

  /// Properties the user has changed locally; polling won't overwrite until
  /// the entry expires. Stops the slider/toggle from snapping back while we
  /// wait for the Pi → state echo → DB → poll round trip (~1-3s).
  final Map<String, DateTime> _localOverrideUntil = {};
  static const _localOverrideHold = Duration(seconds: 4);

  // Playback pulse + now-playing now live in the shared speakerSyncProvider
  // so the Dashboard mini-card and this screen always agree on state.
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
      _refreshNowPlaying();
    });
    // Kick one off immediately so the speaker card has a track on first paint.
    _refreshNowPlaying();
  }

  Future<void> _refreshNowPlaying() async {
    final track = await SpotifyApiClient.getCurrentlyPlaying();
    if (!mounted) return;
    ref.read(speakerSyncProvider.notifier).setNowPlaying(track);
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
              // Skip if user just changed this locally — let the optimistic
              // value win until the lock expires (Pi echo round trip).
              final lockKey = '$id:$pName';
              final until = _localOverrideUntil[lockKey];
              if (until != null && until.isAfter(DateTime.now())) continue;
              _localOverrideUntil.remove(lockKey);
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

    // Lazy load shared history so the climate sparkline can render even
    // before the first poll completes after a tab change.
    if (_sensorHistory.isEmpty) {
      final loaded = await SensorHistoryService.load(homeId);
      if (mounted) setState(() => _sensorHistory = loaded);
    }

    final data = await ApiService.fetchSensors(homeId);

    if (data != null && data['sensors'] != null) {
      final sensors = data['sensors'] as Map<String, dynamic>;

      double? aggTemp;
      double? aggHum;

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
                aggTemp ??= double.tryParse(deviceData['temperature'].toString());
              }
              if (deviceData.containsKey('humidity')) {
                _deviceStates[devId]!['humidity'] = deviceData['humidity'];
                aggHum ??= double.tryParse(deviceData['humidity'].toString());
              }
            }
          }
        });

        // Push the latest reading into the shared ring buffer so this
        // tab also contributes to the sparkline timeline.
        if (aggTemp != null || aggHum != null) {
          final updated = await SensorHistoryService.append(
            homeId,
            temperature: aggTemp,
            humidity: aggHum,
          );
          if (mounted) {
            setState(() => _sensorHistory = updated);
          }
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
  void _updateDeviceState(String deviceId, String property, dynamic value) {
    final key = '$deviceId:$property';
    setState(() {
      if (_deviceStates[deviceId] == null) _deviceStates[deviceId] = {};
      _deviceStates[deviceId]![property] = value;
      // Lock this property against polling overwrites for a few seconds
      // so the slider/toggle doesn't snap back while we wait for the echo.
      _localOverrideUntil[key] = DateTime.now().add(_localOverrideHold);
    });
    // Mirror the change into the shared optimistic overlay so the AI chat
    // and any other screen that watches deviceOverridesProvider stay in sync
    // for properties the Pi never echoes back.
    ref.read(deviceOverridesProvider.notifier).set(deviceId, property, value);

    // Key the debounce by device+property so changing brightness then color
    // on the same LED does not cancel the pending brightness send.
    if (_debounceTimers[key]?.isActive ?? false) _debounceTimers[key]!.cancel();
    _debounceTimers[key] = Timer(const Duration(milliseconds: 500), () {
      _sendDynamicCommand(deviceId, property, value);
    });
  }

  /// Speaker playback (play/pause/stop) — direct Spotify Web API, no MQTT.
  /// Pi only handles power + volume; transport control runs from the user's
  /// own Spotify session, targeting the Pi as the active Connect device.
  Future<void> _spotifyPlayback(String deviceId, String value) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _deviceStates[deviceId] ??= {};
      _deviceStates[deviceId]!['playback'] = value;
    });
    // Push to the shared provider so the Dashboard mini speaker matches.
    ref.read(speakerSyncProvider.notifier).setPlayback(deviceId, value);

    String? spId;
    final byPrefix =
        await SpotifyApiClient.findDeviceByPrefix(kSpeakerNamePrefix);
    if (byPrefix != null) spId = byPrefix['id']?.toString();

    // Fallback: if device list is cold but something IS playing, pull the
    // device id off the active session so pause still works.
    if (spId == null) {
      final nowPlaying = ref.read(speakerSyncProvider).nowPlaying ??
          await SpotifyApiClient.getCurrentlyPlaying();
      final dev = nowPlaying?['device'];
      if (dev is Map && dev['id'] != null) spId = dev['id'].toString();
    }

    if (spId == null) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text("Speaker not found on the Spotify network — is the Pi on?"),
      ));
      return;
    }

    bool ok = false;
    switch (value) {
      case 'play':
        ok = await SpotifyApiClient.resumePlayback(spId);
        break;
      case 'pause':
      case 'stop':
        ok = await SpotifyApiClient.pausePlayback(spId);
        break;
    }
    if (!ok && mounted) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Playback command failed (Spotify Premium required).'),
      ));
    }
    // Refresh now-playing into the shared provider so the UI reacts.
    final track = await SpotifyApiClient.getCurrentlyPlaying();
    if (mounted) {
      ref.read(speakerSyncProvider.notifier).setNowPlaying(track);
    }
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Pull the shared optimistic overlay (assistant tool calls + manual
    // updates from any screen) and apply on top of polled DB state. Pi
    // firmware doesn't echo AC/oven/LED detail properties yet, so without
    // this merge `_fetchDevices` wipes them on every 5-second poll.
    final overrides = ref.watch(deviceOverridesProvider);
    if (overrides.isNotEmpty) {
      for (final entry in overrides.entries) {
        final devId = entry.key;
        _deviceStates[devId] ??= {};
        for (final prop in entry.value.entries) {
          _deviceStates[devId]![prop.key] = prop.value;
        }
      }
    }

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
                : RefreshIndicator(
                    color: AppColors.primaryBlue,
                    backgroundColor: AppColors.card(context),
                    onRefresh: () async {
                      await Future.wait([
                        _fetchDevices(),
                        _fetchLatestSensorData(),
                      ]);
                    },
                    child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
                    if (_devices.isEmpty)
                      Center(child: Text("No devices found.", style: TextStyle(color: AppColors.textSub(context)))),
                    ..._devices.where((device) {
                      // Hide categories that don't belong on the live tiles:
                      // gas/vibration → push notifications instead;
                      // camera → removed product feature;
                      // rfid → access control runs headless via authorized_cards.
                      final t = (device['device_type'] ?? '').toString().toLowerCase();
                      final n = (device['device_name'] ?? '').toString().toLowerCase();
                      final isGas = n.contains('gas') || n.contains('gaz') || t.contains('gas');
                      final isQuake = n.contains('deprem') || n.contains('earthquake') || t.contains('vibration');
                      final isCamera = t.contains('camera') || n.contains('camera') || n.contains('kamera');
                      final isRfid = t.contains('rfid') || n.contains('rfid');
                      return !isGas && !isQuake && !isCamera && !isRfid;
                    }).map((device) {
                      Widget card;
                      String type = (device['device_type'] ?? '').toString().toLowerCase();
                      String name = (device['device_name'] ?? '').toString().toLowerCase();

                      if (type == 'climate' || type == 'ac' || name.contains('klima')) {
                        card = _buildClimateCard(device);
                      } else if (type == 'oven' || name.contains('oven') || name.contains('fırın') || name.contains('firin')) {
                        card = _buildOvenCard(device);
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
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: card,
                      );
                    }),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  // ====================== UI COMPONENTS ====================== //

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(AppSpacing.xl)}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // In dark mode keep the frosted-glass look; in light mode use a clean
    // solid card with a soft shadow that matches the rest of the app.
    if (isDark) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: AppColors.card(context).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.borderCol(context)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
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
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.borderCol(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildHeader() {
    final connectedCount = _devices.length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.40),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(Icons.devices_rounded,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Devices",
                style: TextStyle(
                  color: AppColors.text(context),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.05,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.accentGreen, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "$connectedCount connected",
                    style: TextStyle(
                      color: AppColors.textSub(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
  Widget _buildClimateCard(Map<String, dynamic> device) {
    String deviceId = device['deviceid'];
    String deviceName = device['device_name'] ?? 'Air Conditioner';
    Map<String, dynamic> state = _deviceStates[deviceId] ?? {};

    bool isEngineOn = state['power'] == 'on';
    int targetTemp = _readInt(state, 'target_temp', fallback: 22).clamp(16, 30);
    String mode = (state['mode'] ?? 'cool').toString().toLowerCase();
    String fanSpeed = (state['fan_speed'] ?? 'auto').toString().toLowerCase();

    const Map<String, IconData> modes = {
      'cool': Icons.ac_unit,
      'heat': Icons.local_fire_department,
      'auto': Icons.autorenew,
      'fan': Icons.cyclone,
      'dry': Icons.water_drop,
    };
    const fanSpeeds = ['low', 'mid', 'high', 'auto'];

    String cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isEngineOn ? AppColors.primaryBlue.withValues(alpha: 0.2) : AppColors.borderCol(context),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.ac_unit, color: isEngineOn ? AppColors.primaryBlue : Colors.grey, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      isEngineOn ? '${cap(mode)} · $targetTemp°C' : 'Standby',
                      style: TextStyle(color: isEngineOn ? AppColors.primaryBlue : Colors.grey, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isEngineOn,
                activeThumbColor: AppColors.primaryBlue,
                onChanged: (val) => _updateDeviceState(deviceId, 'power', val ? 'on' : 'off'),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: !isEngineOn
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Icon(Icons.thermostat, color: AppColors.textSub(context), size: 16),
                          const SizedBox(width: 4),
                          Text('Target', style: TextStyle(color: AppColors.textSub(context), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                          const Spacer(),
                          Text('$targetTemp°C', style: TextStyle(color: AppColors.text(context), fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: AppColors.primaryBlue,
                          inactiveTrackColor: AppColors.borderCol(context),
                          thumbColor: AppColors.primaryBlue,
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: targetTemp.toDouble(),
                          min: 16,
                          max: 30,
                          divisions: 14,
                          onChanged: (val) => _updateDeviceState(deviceId, 'target_temp', val.toInt().toString()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Mode', style: TextStyle(color: AppColors.textSub(context), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: modes.entries.map((e) => _buildOptionChip(
                              label: cap(e.key),
                              icon: e.value,
                              selected: mode == e.key,
                              accent: AppColors.primaryBlue,
                              onTap: () => _updateDeviceState(deviceId, 'mode', e.key),
                            )).toList(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Fan', style: TextStyle(color: AppColors.textSub(context), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: fanSpeeds.map((f) => _buildOptionChip(
                              label: cap(f),
                              selected: fanSpeed == f,
                              accent: AppColors.primaryBlue,
                              onTap: () => _updateDeviceState(deviceId, 'fan_speed', f),
                            )).toList(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOvenCard(Map<String, dynamic> device) {
    String deviceId = device['deviceid'];
    String deviceName = device['device_name'] ?? 'Oven';
    Map<String, dynamic> state = _deviceStates[deviceId] ?? {};

    bool isOn = state['power'] == 'on';
    int targetTemp = _readInt(state, 'target_temp', fallback: 180).clamp(50, 250);
    int timer = _readInt(state, 'timer', fallback: 0).clamp(0, 180);
    String mode = (state['mode'] ?? 'bake').toString().toLowerCase();

    const Map<String, IconData> modes = {
      'bake': Icons.cake,
      'broil': Icons.local_fire_department,
      'fan': Icons.cyclone,
      'defrost': Icons.ac_unit,
    };
    final accent = Colors.deepOrangeAccent;

    String cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isOn ? accent.withValues(alpha: 0.2) : AppColors.borderCol(context),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.microwave, color: isOn ? accent : Colors.grey, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      isOn ? '${cap(mode)} · $targetTemp°C${timer > 0 ? ' · ${timer}m' : ''}' : 'Off',
                      style: TextStyle(color: isOn ? accent : Colors.grey, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isOn,
                activeThumbColor: accent,
                onChanged: (val) => _updateDeviceState(deviceId, 'power', val ? 'on' : 'off'),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: !isOn
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Icon(Icons.thermostat, color: AppColors.textSub(context), size: 16),
                          const SizedBox(width: 4),
                          Text('Target', style: TextStyle(color: AppColors.textSub(context), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                          const Spacer(),
                          Text('$targetTemp°C', style: TextStyle(color: AppColors.text(context), fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: accent,
                          inactiveTrackColor: AppColors.borderCol(context),
                          thumbColor: accent,
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: targetTemp.toDouble(),
                          min: 50,
                          max: 250,
                          divisions: 20,
                          onChanged: (val) {
                            final stepped = (val / 10).round() * 10;
                            _updateDeviceState(deviceId, 'target_temp', stepped.toString());
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Mode', style: TextStyle(color: AppColors.textSub(context), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: modes.entries.map((e) => _buildOptionChip(
                              label: cap(e.key),
                              icon: e.value,
                              selected: mode == e.key,
                              accent: accent,
                              onTap: () => _updateDeviceState(deviceId, 'mode', e.key),
                            )).toList(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined, color: AppColors.textSub(context), size: 16),
                          const SizedBox(width: 4),
                          Text('Timer', style: TextStyle(color: AppColors.textSub(context), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                          const Spacer(),
                          Text(
                            _formatTimer(timer),
                            style: TextStyle(color: AppColors.text(context), fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      // 1-minute granularity slider — replaces the previous
                      // ±5 stepper so the user can dial in exact bake
                      // durations like 1 h 45 m without seven taps.
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: accent,
                          inactiveTrackColor: AppColors.borderCol(context),
                          thumbColor: accent,
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: timer.toDouble(),
                          min: 0,
                          max: 180,
                          divisions: 180,
                          onChanged: (val) {
                            _updateDeviceState(
                                deviceId, 'timer', val.toInt().toString());
                          },
                        ),
                      ),
                      // Quick presets for common bake durations — one tap
                      // jumps the slider straight to the chosen value.
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [0, 15, 30, 45, 60, 90, 120]
                            .map((m) => _buildOptionChip(
                                  label: _formatTimer(m),
                                  selected: timer == m,
                                  accent: accent,
                                  onTap: () => _updateDeviceState(
                                      deviceId, 'timer', m.toString()),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionChip({
    required String label,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: accent.withValues(alpha: 0.25),
        highlightColor: accent.withValues(alpha: 0.12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(horizontal: icon == null ? 12 : 10, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.18) : AppColors.card(context),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? accent : AppColors.borderCol(context),
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: selected ? accent : AppColors.textSub(context)),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? accent : AppColors.text(context),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact "1h 30m" / "45m" / "Off" formatting for the oven timer
  /// display. Used on both the slider header and the quick-preset chips.
  String _formatTimer(int minutes) {
    if (minutes <= 0) return 'Off';
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final rem = minutes % 60;
    return rem == 0 ? '${h}h' : '${h}h ${rem}m';
  }

  int _readInt(Map<String, dynamic> state, String key, {required int fallback}) {
    final v = state[key];
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
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
    // When the LED is set to white (or near-white), the raw color is invisible
    // against the light theme card. Substitute a warm "daylight" amber for the
    // icon + label only — the actual color still gets pushed to the strip.
    final isWhite = _isNearWhite(lightColor);
    final Color iconTint = isWhite ? AppColors.accentAmber : lightColor;

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
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: isLightOn ? iconTint.withValues(alpha: 0.2) : AppColors.borderCol(context),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(
                        isWhite && isLightOn ? Icons.wb_sunny_rounded : Icons.lightbulb,
                        color: isLightOn ? iconTint : Colors.grey,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(deviceName, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(color: isLightOn ? iconTint : Colors.grey, fontSize: 13, fontWeight: FontWeight.w600),
                            child: Text(isLightOn ? (isWhite ? "Daylight" : "Turned On") : "Turned Off"),
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
                activeThumbColor: lightColor,
                onChanged: (val) => _updateDeviceState(deviceId, 'power', val ? 'on' : 'off'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          LedColorPicker(
            currentHex: hexColor,
            onChanged: (hex) =>
                _updateDeviceState(deviceId, 'color', hex),
          ),
          const SizedBox(height: AppSpacing.md),
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
    int volume = state['volume'] != null
        ? (state['volume'] is num
            ? state['volume'].toInt()
            : int.tryParse(state['volume'].toString()) ?? 50)
        : 50;

    // Pull live playback + currently-playing track from the shared provider
    // so this card matches the Dashboard mini speaker, even between polls.
    final sync = ref.watch(speakerSyncProvider);
    final pulse = sync.playbackPulse[deviceId];
    final track = sync.nowPlaying?['track'] as Map?;
    final trackName = (track?['name'] ?? '').toString();
    final artist = (track?['artist'] ?? '').toString();
    final isPlaying = sync.nowPlaying?['is_playing'] == true;
    final hasTrack = trackName.isNotEmpty;

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
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        gradient: isEngineOn
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.accentPink,
                                  Color.alphaBlend(
                                    Colors.white.withValues(alpha: 0.25),
                                    AppColors.accentPink,
                                  ),
                                ],
                              )
                            : null,
                        color: isEngineOn ? null : AppColors.borderCol(context),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        boxShadow: isEngineOn
                            ? [
                                BoxShadow(
                                  color: AppColors.accentPink
                                      .withValues(alpha: 0.30),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(Icons.speaker_group,
                          color: isEngineOn ? Colors.white : Colors.grey,
                          size: 20),
                    ),
                    const SizedBox(width: AppSpacing.md),
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
                          if (isEngineOn && hasTrack)
                            Row(
                              children: [
                                Icon(
                                  isPlaying
                                      ? Icons.graphic_eq
                                      : Icons.pause_circle_outline,
                                  size: 12,
                                  color: AppColors.accentPink,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    artist.isEmpty
                                        ? trackName
                                        : '$trackName · $artist',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.accentPink,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              isEngineOn ? "Volume $volume%" : "Offline",
                              style: TextStyle(
                                  color: isEngineOn
                                      ? AppColors.accentPink
                                      : Colors.grey,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isEngineOn,
                activeThumbColor: AppColors.accentPink,
                onChanged: (val) =>
                    _updateDeviceState(deviceId, 'power', val ? 'on' : 'off'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPlaybackBtn(
                  Icons.play_arrow, () => _spotifyPlayback(deviceId, 'play'),
                  selected: pulse == 'play'),
              _buildPlaybackBtn(
                  Icons.pause, () => _spotifyPlayback(deviceId, 'pause'),
                  selected: pulse == 'pause'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.volume_down,
                  color: AppColors.textSub(context), size: 20),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: AppColors.accentPink,
                    inactiveTrackColor: AppColors.borderCol(context),
                    thumbColor: AppColors.accentPink,
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
              SizedBox(
                  width: 36,
                  child: Text('$volume%',
                      style: TextStyle(
                          color: AppColors.text(context),
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right)),
            ],
          ),
        ],
      ),
    );
  }

  /// Pink-themed play/pause button used by the speaker card. Highlights with
  /// a gradient + glow when [selected] is true so the user can see at a
  /// glance whether the speaker is in play or pause mode.
  Widget _buildPlaybackBtn(IconData icon, VoidCallback onTap,
      {bool selected = false}) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.accentPink.withValues(alpha: 0.30),
        highlightColor: AppColors.accentPink.withValues(alpha: 0.18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.accentPink,
                      Color.alphaBlend(
                        Colors.white.withValues(alpha: 0.25),
                        AppColors.accentPink,
                      ),
                    ],
                  )
                : null,
            color: selected ? null : AppColors.card(context),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? AppColors.accentPink
                  : AppColors.borderCol(context),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.accentPink.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Icon(icon,
              color: selected ? Colors.white : AppColors.text(context),
              size: 20),
        ),
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
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: isOn
                            ? AppColors.primaryBlue.withValues(alpha: 0.2)
                            : AppColors.borderCol(context),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(Icons.tv,
                          color: isOn ? AppColors.primaryBlue : Colors.grey,
                          size: 20),
                    ),
                    const SizedBox(width: AppSpacing.md),
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
          const SizedBox(height: AppSpacing.md),
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
                  const SizedBox(height: 2),
                  Text("$channel",
                      style: TextStyle(
                          color: AppColors.text(context),
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              _buildModernIconButton(Icons.keyboard_arrow_up, () {
                int next = (channel + 1).clamp(1, 999);
                _updateDeviceState(deviceId, 'channel', next.toString());
              }),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
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
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(Icons.nfc, color: statusColor, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
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
    
    IconData iconData = Icons.electrical_services;
    Color iconColor = Colors.purpleAccent;
    String nameLr = deviceName.toLowerCase();

    if (nameLr.contains('door') || nameLr.contains('kapı') || nameLr.contains('kapi')) {
      iconData = Icons.door_front_door;
      iconColor = Colors.brown.shade400;
    } else if (nameLr.contains('window') || nameLr.contains('pencere')) {
      iconData = Icons.window;
      iconColor = Colors.lightBlueAccent;
    } else if (nameLr.contains('curtain') || nameLr.contains('perde') || nameLr.contains('jaluzi') || nameLr.contains('blind')) {
      iconData = Icons.curtains;
      iconColor = Colors.teal;
    } else if (nameLr.contains('lock') || nameLr.contains('kilit')) {
      iconData = Icons.lock;
      iconColor = Colors.amber.shade700;
    } else if (nameLr.contains('fan') || nameLr.contains('vantilatör') || nameLr.contains('vantilator') || nameLr.contains('pervane')) {
      iconData = Icons.cyclone;
      iconColor = Colors.blueAccent;
    } else if (nameLr.contains('oven') || nameLr.contains('fırın') || nameLr.contains('firin')) {
      iconData = Icons.microwave;
      iconColor = Colors.deepOrangeAccent;
    } else if (nameLr.contains('stove') || nameLr.contains('ocak') || nameLr.contains('cooktop')) {
      iconData = Icons.local_fire_department;
      iconColor = Colors.deepOrangeAccent;
    } else if (nameLr.contains('kettle') || nameLr.contains('çaydanlık') || nameLr.contains('caydanlik') || nameLr.contains('teapot')) {
      iconData = Icons.local_cafe;
      iconColor = Colors.brown.shade300;
    } else if (nameLr.contains('coffee') || nameLr.contains('kahve')) {
      iconData = Icons.coffee_maker;
      iconColor = Colors.brown.shade300;
    } else if (nameLr.contains('kombi') || nameLr.contains('boiler') || nameLr.contains('heater') || nameLr.contains('ısıtıcı') || nameLr.contains('isitici') || nameLr.contains('radyatör') || nameLr.contains('radyator')) {
      iconData = Icons.thermostat;
      iconColor = Colors.orangeAccent;
    } else if (nameLr.contains('vacuum') || nameLr.contains('vakum') || nameLr.contains('süpürge') || nameLr.contains('supurge')) {
      iconData = Icons.cleaning_services;
      iconColor = Colors.cyan;
    } else if (nameLr.contains('charger') || nameLr.contains('şarj') || nameLr.contains('sarj') || nameLr.contains('battery') || nameLr.contains('pil')) {
      iconData = Icons.battery_charging_full;
      iconColor = Colors.greenAccent;
    } else if (nameLr.contains('plug') || nameLr.contains('priz') || nameLr.contains('soket') || nameLr.contains('socket') || nameLr.contains('outlet')) {
      iconData = Icons.power;
      iconColor = Colors.amberAccent;
    } else if (nameLr.contains('washer') || nameLr.contains('çamaşır') || nameLr.contains('camasir') || nameLr.contains('laundry')) {
      iconData = Icons.local_laundry_service;
      iconColor = Colors.lightBlue;
    } else if (nameLr.contains('dishwasher') || nameLr.contains('bulaşık') || nameLr.contains('bulasik')) {
      iconData = Icons.local_dining;
      iconColor = Colors.tealAccent;
    } else if (nameLr.contains('fridge') || nameLr.contains('buzdolabı') || nameLr.contains('buzdolabi') || nameLr.contains('refrigerator')) {
      iconData = Icons.kitchen;
      iconColor = Colors.lightBlueAccent;
    }

    return _buildGlassCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(iconData, color: iconColor, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
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
            activeThumbColor: iconColor,
            onChanged: (val) => _updateDeviceState(deviceId, 'power', val ? 'on' : 'off'),
          ),
        ],
      ),
    );
  }

  /// Climate card on the Devices screen — uses the same TempHumidityCard
  /// widget as the dashboard (icon chips + progress + 12h sparkline) and
  /// adds a small device-name + status header on top so users still know
  /// which physical sensor is reporting.
  Widget _buildTempHumidityCard(Map<String, dynamic> device) {
    final deviceName = device['device_name'] ?? 'Temperature & Humidity';
    final state = _deviceStates[device['deviceid']] ?? const {};
    final temp = state['temperature']?.toString() ?? '--';
    final hum = state['humidity']?.toString() ?? '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Row(
            children: [
              Icon(Icons.sensors,
                  color: AppColors.textSub(context), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  deviceName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.accentGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Online',
                style: TextStyle(
                  color: AppColors.accentGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        TempHumidityCard(
          temperature: temp,
          humidity: hum,
          history: _sensorHistory,
        ),
      ],
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

  /// Returns true when [c] is white-or-near-white, i.e. high luminance with
  /// near-equal channels. We use this to swap the LED card's bulb tint for a
  /// readable amber so the icon doesn't vanish on the light theme.
  bool _isNearWhite(Color c) {
    final argb = c.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final minCh = r < g ? (r < b ? r : b) : (g < b ? g : b);
    final maxCh = r > g ? (r > b ? r : b) : (g > b ? g : b);
    return minCh >= 220 && (maxCh - minCh) <= 12;
  }

  // --- Premium Mini Widgets --- //

  Widget _buildModernIconButton(IconData icon, VoidCallback onTap,
      {bool selected = false}) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.primaryBlue.withValues(alpha: 0.30),
        highlightColor: AppColors.primaryBlue.withValues(alpha: 0.18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlue.withValues(alpha: 0.18)
                : AppColors.card(context),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue
                  : AppColors.borderCol(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Icon(icon,
              color: selected ? AppColors.primaryBlue : AppColors.text(context),
              size: 22),
        ),
      ),
    );
  }

}

