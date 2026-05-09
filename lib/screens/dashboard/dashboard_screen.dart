import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../constants/app_colors.dart';
import '../../theme/app_breakpoints.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/onboarding_keys.dart';
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
import '../../providers/alert_provider.dart';
import '../../providers/mood_provider.dart';
import '../../providers/navigation_provider.dart';
import 'home_selection_screen.dart';
import '../../services/api_service.dart';
import '../../services/scene_presets.dart';
import '../../services/sensor_history_service.dart';
import '../../services/usage_stats_service.dart';
import '../../services/spotify/spotify_api_client.dart';
import '../ai_hub/widgets/mood_tracks_list.dart' show kSpeakerNamePrefix;
import '../notifications/notification_screen.dart';
import 'widgets/my_homes_list.dart';
import 'widgets/scene_card.dart';
import 'widgets/system_status_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<dynamic> _userHomes = [];
  bool _isLoadingHomes = true;
  String _errorMessage = '';

  String _temperature = "--";
  String _humidity = "--";
  String _lastHomeId = '';
  List<SensorReading> _sensorHistory = const [];
  Timer? _dashboardPollingTimer;

  // Cached actuator list used by the Quick Access scenes.
  List<dynamic> _devices = [];
  String? _runningScene; // 'all_off' | 'movie' | 'bright' | null
  List<ScenePreset> _slots = ScenePresets.all.take(4).toList();

  // Speaker control state. Mirrors property values from _devices and is
  // updated optimistically on user interaction so the UI feels instant.
  final Map<String, Map<String, dynamic>> _speakerStates = {};
  Timer? _speakerVolumeDebounce;

  /// Persistent highlight for the last playback action (play / pause). Local
  /// feedback only — real playback state lives in the user's Spotify session,
  /// not our DB, so we mirror what the user pressed and keep it shown until
  /// they press the opposite button.
  final Map<String, String> _playbackPulse = {}; // deviceId → 'play' | 'pause'

  /// Currently-playing track from Spotify (title/artist), refreshed on
  /// the dashboard poll so the speaker card can show "▶ Track — Artist".
  Map<String, dynamic>? _nowPlaying;

  @override
  void dispose() {
    _dashboardPollingTimer?.cancel();
    _speakerVolumeDebounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchUserHomes();
    _loadSlots();
    _maybeStartOnboarding();
  }

  static const _onboardingKey = 'onboarding_done_v1';

  Future<void> _maybeStartOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_onboardingKey) ?? false) return;
    // Wait one frame so the Showcase targets are mounted before the
    // tour starts; otherwise the first tooltip has nothing to anchor to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ShowCaseWidget.of(context).startShowCase([
        OnboardingKeys.hero,
        OnboardingKeys.scenes,
      ]);
      prefs.setBool(_onboardingKey, true);
    });
  }

  Future<void> _loadSlots() async {
    final slots = await ScenePresets.loadSlots();
    if (mounted) setState(() => _slots = slots);
  }

  Future<void> _replaceSlot(int index) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bg(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textSub(context).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text("Pick a scene for this slot",
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  "Long-press any slot on the dashboard to swap it out.",
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.5,
                    children: ScenePresets.all
                        .map((p) => InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.pop(ctx, p.key),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.card(ctx),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: p.accent.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: p.accent
                                            .withValues(alpha: 0.18),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Icon(p.icon,
                                          color: p.accent, size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        p.label,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.text(ctx),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) {
      await ScenePresets.saveSlot(index, picked);
      await _loadSlots();
    }
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

  // --- FETCH DEVICE LIST (Quick Access scenes + speaker control) ---
  Future<void> _fetchDevicesForScenes(String homeId) async {
    final devs = await ApiService.fetchDevices(homeId);
    if (devs == null || !mounted) return;
    setState(() {
      _devices = devs;
      // Hydrate speaker state from properties so the dashboard control card
      // reflects the actual current_value reported by the actuator.
      for (final d in devs) {
        if (d is! Map) continue;
        if (_classify(Map<String, dynamic>.from(d)) != 'speaker') continue;
        final id = d['deviceid']?.toString();
        if (id == null) continue;
        final existing = _speakerStates[id] ?? <String, dynamic>{};
        for (final p in (d['properties'] ?? []) as List) {
          final name = p['property_name']?.toString();
          var val = p['current_value'];
          if (name == null || val == null || val == '' || val == 'null') continue;
          // Don't clobber a value the user just set (and that hasn't been
          // confirmed by the server yet) on the next poll. The flag is set
          // briefly when the user interacts, then cleared by the response.
          if (existing['_dirty_$name'] == true) continue;
          if (val is String && (val.toUpperCase() == 'ON' || val.toUpperCase() == 'OFF')) {
            val = val.toLowerCase();
          }
          if (name == 'volume' && val is String) {
            val = num.tryParse(val) ?? val;
          }
          existing[name] = val;
        }
        _speakerStates[id] = existing;
      }
    });
  }

  List<Map<String, dynamic>> _speakers() {
    return _devices
        .whereType<Map>()
        .map((d) => Map<String, dynamic>.from(d))
        .where((d) => _classify(d) == 'speaker')
        .toList();
  }

  Future<void> _setSpeakerProp(String deviceId, String prop, dynamic value) async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'])?.toString();
    if (homeId == null) return;
    setState(() {
      _speakerStates[deviceId] ??= {};
      _speakerStates[deviceId]![prop] = value;
      _speakerStates[deviceId]!['_dirty_$prop'] = true;
    });
    // Clear the dirty flag after the Pi → echo → DB round trip window so
    // polling won't snap the slider/toggle back to the old DB value while
    // the echo is still in flight (~1-3s typical, give 4s headroom).
    Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _speakerStates[deviceId]?.remove('_dirty_$prop');
      });
    });
    final ok = await ApiService.sendCommand(
      homeId: homeId,
      deviceId: deviceId,
      action: prop,
      value: value is num ? value.toInt().toString() : value,
    );
    if (!mounted) return;
    // Note: the dirty flag is now cleared by the 4s timer above, NOT here —
    // sendCommand returns when AWS API GW publishes to MQTT, which is well
    // before the Pi has applied the change and echoed back. Clearing here
    // would re-open the polling-overwrite race.
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Speaker command failed. Check connection."),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // --- DEVICE CLASSIFICATION ---
  // Mirrors the heuristics already used in device_control_screen and
  // automation_create_screen so a "scene" knows which devices to act on.
  String _classify(Map<String, dynamic> dev) {
    final type = (dev['device_type'] ?? '').toString().toLowerCase();
    final name = (dev['device_name'] ?? '').toString().toLowerCase();
    if (type.contains('sensor') ||
        type.contains('temperature') ||
        type.contains('humidity') ||
        type.contains('vibration') ||
        type.contains('gas') ||
        name.contains('temp') ||
        name.contains('nem') ||
        name.contains('gas') ||
        name.contains('gaz') ||
        name.contains('deprem') ||
        name.contains('earthquake')) {
      return 'sensor';
    }
    if (type == 'rfid' || name.contains('rfid') || name.contains('door')) {
      return 'rfid';
    }
    if (type == 'tv' || name.contains('tv') || name.contains('television')) {
      return 'tv';
    }
    if (type == 'light' ||
        type == 'led' ||
        type == 'led_strip' ||
        type == 'smartbulb' ||
        name.contains('led') ||
        name.contains('light')) {
      return 'led';
    }
    if (type == 'speaker' || type == 'audio' || name.contains('speaker')) {
      return 'speaker';
    }
    if (type == 'climate' || type == 'ac') return 'ac';
    return 'generic';
  }

  // --- SCENE RUNNER ---
  // Each scene returns a list of (deviceId, property, value) tuples to send.
  // We dispatch them in parallel and surface a single snackbar at the end.
  Future<void> _runScene(String key, String label) async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'])?.toString();
    if (homeId == null || homeId.isEmpty) return;

    if (_devices.isEmpty) {
      // First use after dashboard load — fetch on demand so the scene works.
      await _fetchDevicesForScenes(homeId);
    }

    final List<List<dynamic>> commands = []; // [deviceId, property, value]
    final touched = <String>{};

    for (final dev in _devices) {
      final id = dev['deviceid']?.toString();
      if (id == null) continue;
      final kind = _classify(dev);
      if (kind == 'sensor' || kind == 'rfid') continue; // read-only

      switch (key) {
        case 'all_off':
          commands.add([id, 'power', 'off']);
          touched.add(id);
          break;
        case 'movie':
          if (kind == 'tv') {
            commands.add([id, 'power', 'on']);
            touched.add(id);
          } else if (kind == 'led') {
            commands.add([id, 'power', 'on']);
            commands.add([id, 'brightness', '25']);
            commands.add([id, 'color', '#FF8866']); // warm cinematic
            touched.add(id);
          } else if (kind == 'speaker') {
            commands.add([id, 'power', 'off']);
            touched.add(id);
          }
          // AC and generic devices: leave alone for movie mode
          break;
        case 'bright':
          if (kind == 'led') {
            commands.add([id, 'power', 'on']);
            commands.add([id, 'brightness', '100']);
            commands.add([id, 'color', '#FFFFFF']);
            touched.add(id);
          }
          break;
        case 'reading':
          if (kind == 'led') {
            commands.add([id, 'power', 'on']);
            commands.add([id, 'brightness', '60']);
            commands.add([id, 'color', '#FFD9A8']);
            touched.add(id);
          } else if (kind == 'tv') {
            commands.add([id, 'power', 'off']);
            touched.add(id);
          }
          break;
        case 'sleep':
          if (kind == 'led' || kind == 'tv' || kind == 'speaker') {
            commands.add([id, 'power', 'off']);
            touched.add(id);
          }
          break;
        case 'party':
          if (kind == 'led') {
            commands.add([id, 'power', 'on']);
            commands.add([id, 'brightness', '100']);
            commands.add([id, 'color', '#FF00FF']);
            touched.add(id);
          } else if (kind == 'speaker') {
            commands.add([id, 'power', 'on']);
            commands.add([id, 'volume', '70']);
            touched.add(id);
          }
          break;
        case 'romance':
          if (kind == 'led') {
            commands.add([id, 'power', 'on']);
            commands.add([id, 'brightness', '30']);
            commands.add([id, 'color', '#FF4080']);
            touched.add(id);
          }
          break;
      }
    }

    if (commands.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("No matching devices for \"$label\"."),
            backgroundColor: AppColors.cardDark,
          ),
        );
      }
      // Still log it — the user pressed a scene, expected something to
      // happen, and got silence. Surfacing this in notifications helps
      // them realize "I don't have a TV/LED yet" rather than thinking
      // the app is broken.
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      ref.read(alertListProvider.notifier).addAlertSynced(
            AlertItem(
              id: now.millisecondsSinceEpoch.toString(),
              title: 'Scene "$label" had no targets',
              description:
                  'No matching devices in this home — add a compatible '
                  'device first.',
              time: timeStr,
              type: AlertType.device,
              level: AlertLevel.warning,
              isRead: true,
            ),
            homeId: homeId,
          );
      return;
    }

    setState(() => _runningScene = key);
    UsageStatsService.recordSceneRun(key);
    final results = await Future.wait(commands.map((c) => ApiService.sendCommand(
          homeId: homeId,
          deviceId: c[0] as String,
          action: c[1] as String,
          value: c[2],
        )));
    if (!mounted) return;
    setState(() => _runningScene = null);

    final ok = results.where((r) => r).length;
    final fail = results.length - ok;
    final color = fail == 0 ? AppColors.accentGreen : AppColors.accentOrange;
    final msg = fail == 0
        ? '$label applied · ${touched.length} device${touched.length == 1 ? "" : "s"} updated'
        : '$label partial · $ok of ${results.length} commands sent';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)),
    );

    // Log the scene run as a notification so the alerts screen has
    // substance even on quiet days. Sensors/RFID are skipped so the
    // count reflects actual actuator activity. Synced to AWS so it
    // also shows up on the user's other devices.
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    ref.read(alertListProvider.notifier).addAlertSynced(
          AlertItem(
            id: now.millisecondsSinceEpoch.toString(),
            title: 'Scene "$label" ran',
            description: fail == 0
                ? '${touched.length} device${touched.length == 1 ? "" : "s"} updated.'
                : '$ok of ${results.length} commands succeeded.',
            time: timeStr,
            type: AlertType.device,
            level: fail == 0 ? AlertLevel.info : AlertLevel.warning,
            isRead: true, // Don't badge — scenes are user-initiated.
          ),
          homeId: homeId,
        );
  }

  void _showScenesInfoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        Widget row(IconData icon, Color color, String title, String body) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            color: AppColors.text(context),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          )),
                      const SizedBox(height: 4),
                      Text(body,
                          style: TextStyle(
                            color: AppColors.textSub(context),
                            fontSize: 13,
                            height: 1.4,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textSub(context).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text("Quick Access scenes",
                    style: TextStyle(
                      color: AppColors.text(context),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(height: 6),
                Text(
                  "Each scene runs in parallel against the matching devices. Long-press a card to swap it for one of 8 presets.",
                  style: TextStyle(color: AppColors.textSub(context), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                Divider(color: AppColors.borderCol(context), height: 1),
                row(Icons.power_settings_new, AppColors.accentRed, "All Off",
                    "Switches every controllable device (TVs, lights, AC, speakers, plugs) to OFF. Asks for confirmation first."),
                row(Icons.movie_creation, Colors.deepPurpleAccent, "Movie",
                    "TVs turn on, LED lights drop to 25% with a warm cinematic tone, speakers turn off so the TV audio leads. AC stays as you left it."),
                row(Icons.wb_sunny, Colors.amber.shade700, "Bright",
                    "All LED lights snap to full 100% white. Use it when you walk in or need the room cleaning-bright."),
                row(Icons.palette, Colors.pinkAccent, "Mood",
                    "Opens the AI Mood screen, where the camera-detected emotion drives matching automations you've defined."),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb, size: 16, color: AppColors.primaryBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Sensors and door readers are skipped — scenes only touch actuators.",
                          style: TextStyle(
                            color: AppColors.text(context),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmAllOff() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        title: Text('Turn everything off?', style: TextStyle(color: AppColors.text(context))),
        content: Text(
          'This switches every controllable device in this home to OFF.',
          style: TextStyle(color: AppColors.textSub(context)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn off all', style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      await _runScene('all_off', 'All Off');
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
            }
          }
        });

        // Persist this reading to the local 24h ring buffer so the
        // sparkline keeps building over time. Same-bucket dedup is
        // handled inside the service.
        final tempNum = double.tryParse(_temperature);
        final humNum = double.tryParse(_humidity);
        if (tempNum != null || humNum != null) {
          final updated = await SensorHistoryService.append(
            homeId,
            temperature: tempNum,
            humidity: humNum,
          );
          if (mounted) {
            setState(() => _sensorHistory = updated);
          }
        }
      }
    }
  }

  Future<void> _loadSensorHistory(String homeId) async {
    // Try the server-side history first so the sparkline pops up with
    // a full 12 h of real data; falls back to whatever we have locally
    // when the AWS route isn't deployed yet (returns the same list).
    final history = await SensorHistoryService.hydrateFromAws(homeId);
    if (mounted) setState(() => _sensorHistory = history);
  }

  Future<void> _fetchNowPlaying() async {
    final track = await SpotifyApiClient.getCurrentlyPlaying();
    if (!mounted) return;
    // Only update if something changed, to avoid pointless rebuilds.
    final newName = track?['track']?['name'];
    final oldName = _nowPlaying?['track']?['name'];
    if (newName != oldName ||
        track?['is_playing'] != _nowPlaying?['is_playing']) {
      setState(() => _nowPlaying = track);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
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
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
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

  // ─── Speaker control card (dashboard) ───────────────────────────────
  // Returns the section as a list so it can be conditionally empty.
  List<Widget> _buildSpeakerSection() {
    final speakers = _speakers();
    if (speakers.isEmpty) return const [];
    final primary = speakers.first;
    final id = primary['deviceid'].toString();
    final name = (primary['device_name'] ?? 'Speaker').toString();
    final state = _speakerStates[id] ?? const {};
    final isOn = state['power'] == 'on';
    final vol = state['volume'] is num
        ? (state['volume'] as num).toInt()
        : int.tryParse(state['volume']?.toString() ?? '') ?? 50;

    return [
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderCol(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.pinkAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.speaker_group,
                      color: isOn ? Colors.pinkAccent : Colors.grey, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                            color: AppColors.text(context),
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      _buildSpeakerSubtitle(isOn: isOn, volume: vol),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: isOn,
                  activeThumbColor: Colors.pinkAccent,
                  onChanged: (val) {
                    HapticFeedback.selectionClick();
                    _setSpeakerProp(id, 'power', val ? 'on' : 'off');
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Persistent highlight — last tapped button stays selected so
                // the user can see at a glance whether the speaker is in play
                // or pause mode (real Spotify state isn't read back).
                _buildPlaybackBtn(id, Icons.play_arrow, 'play',
                    _playbackPulse[id] == 'play'),
                _buildPlaybackBtn(id, Icons.pause, 'pause',
                    _playbackPulse[id] == 'pause'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.volume_down, color: AppColors.textSub(context), size: 18),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 5,
                      activeTrackColor: Colors.pinkAccent,
                      inactiveTrackColor: AppColors.borderCol(context),
                      thumbColor: Colors.pinkAccent,
                    ),
                    child: Slider(
                      value: vol.toDouble().clamp(0, 100),
                      min: 0,
                      max: 100,
                      onChanged: (val) {
                        setState(() {
                          _speakerStates[id] ??= {};
                          _speakerStates[id]!['volume'] = val.toInt();
                          _speakerStates[id]!['_dirty_volume'] = true;
                        });
                        _speakerVolumeDebounce?.cancel();
                        _speakerVolumeDebounce = Timer(
                          const Duration(milliseconds: 350),
                          () => _setSpeakerProp(id, 'volume', val.toInt()),
                        );
                      },
                    ),
                  ),
                ),
                Icon(Icons.volume_up, color: AppColors.textSub(context), size: 18),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text('$vol%',
                      style: TextStyle(
                        color: AppColors.text(context),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.right),
                ),
              ],
            ),
            if (speakers.length > 1) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => ref.read(tabIndexProvider.notifier).setTab(3),
                child: Row(
                  children: [
                    Text(
                      '+${speakers.length - 1} more · open Devices',
                      style: TextStyle(
                        color: AppColors.primaryBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward, color: AppColors.primaryBlue, size: 14),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  /// Playback control via Spotify Web API (NOT MQTT — Pi only handles
  /// power/volume; play/pause/stop are routed to the user's own Spotify
  /// session targeting the Pi as the active Connect device).
  Future<void> _setSpeakerPlayback(String deviceId, String value) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _speakerStates[deviceId] ??= {};
      _speakerStates[deviceId]!['playback'] = value;
      _playbackPulse[deviceId] = value;
    });

    // Resolve the Spotify device id, with cascading fallbacks so we
    // can still pause music that's already playing even when the
    // device list query is cold.
    String? spId;

    // 1) Fast path: look the speaker up in /me/player/devices by its
    //    AkilliEv-* name prefix.
    final byPrefix =
        await SpotifyApiClient.findDeviceByPrefix(kSpeakerNamePrefix);
    if (byPrefix != null) spId = byPrefix['id']?.toString();

    // 2) If that failed but something IS playing right now (the speaker
    //    card already has a "now playing" indicator), grab the device
    //    id straight off the active session — covers the case where
    //    raspotify is mid-stream but hasn't (re-)registered with the
    //    devices endpoint.
    if (spId == null) {
      final nowPlaying = _nowPlaying ??
          await SpotifyApiClient.getCurrentlyPlaying();
      final dev = nowPlaying?['device'];
      if (dev is Map && dev['id'] != null) spId = dev['id'].toString();
    }

    if (spId == null) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'Hoparlör Spotify ağında görünmüyor — açıkken bir şarkı '
            'çalıp tekrar deneyin.'),
        duration: Duration(seconds: 3),
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
        content: Text('Playback komutu başarısız (Premium hesap gerekir).'),
      ));
    }
  }

  /// Speaker card subtitle. Shows the currently playing track + artist
  /// when Spotify is reporting a track (whether actively playing or
  /// paused), otherwise falls back to "Volume X%" / "Off". Track name is
  /// truncated with ellipsis so long titles don't break the layout.
  Widget _buildSpeakerSubtitle({required bool isOn, required int volume}) {
    final track = _nowPlaying?['track'] as Map?;
    final trackName = (track?['name'] ?? '').toString();
    final artist = (track?['artist'] ?? '').toString();
    final isPlaying = _nowPlaying?['is_playing'] == true;
    final hasTrack = trackName.isNotEmpty;

    if (isOn && hasTrack) {
      return Row(
        children: [
          Icon(
            isPlaying ? Icons.graphic_eq : Icons.pause_circle_outline,
            size: 12,
            color: Colors.pinkAccent,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              artist.isEmpty ? trackName : '$trackName · $artist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.pinkAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return Text(
      isOn ? 'Volume $volume%' : 'Off',
      style: TextStyle(
        color: isOn ? Colors.pinkAccent : AppColors.textSub(context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildPlaybackBtn(String id, IconData icon, String value, bool selected) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _setSpeakerPlayback(id, value),
        splashColor: Colors.pinkAccent.withValues(alpha: 0.30),
        highlightColor: Colors.pinkAccent.withValues(alpha: 0.18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: selected
                ? Colors.pinkAccent.withValues(alpha: 0.18)
                : AppColors.card(context),
            shape: BoxShape.circle,
            border: Border.all(
              color:
                  selected ? Colors.pinkAccent : AppColors.borderCol(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Icon(icon,
              color: selected ? Colors.pinkAccent : AppColors.text(context),
              size: 22),
        ),
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
         _loadSensorHistory(homeId);
         _fetchSensors(homeId);
         _fetchDevicesForScenes(homeId);
         _fetchNowPlaying();
       });

       _dashboardPollingTimer?.cancel();
       _dashboardPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
         if (!mounted) return;
         _fetchSensors(homeId);
         _fetchDevicesForScenes(homeId); // keep speaker card state fresh
         _fetchNowPlaying();
       });
    }

    final unreadCount =
        ref.watch(alertListProvider).where((a) => !a.isRead).length;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: RefreshIndicator(
        color: AppColors.primaryBlue,
        backgroundColor: AppColors.card(context),
        onRefresh: () async {
          await Future.wait([
            _fetchUserHomes(),
            if (homeId != null && homeId.isNotEmpty) ...[
              _fetchSensors(homeId),
              _fetchDevicesForScenes(homeId),
            ],
          ]);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HERO HEADER (gradient) ---
            Showcase(
              key: OnboardingKeys.hero,
              title: 'Welcome to your home',
              description:
                  'This banner shows which home is active and your role. Tap the swap icon to switch homes.',
              tooltipBackgroundColor: AppColors.primaryBlue,
              textColor: Colors.white,
              titleTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              descTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
              child: _HeroHeader(
              homeName: homeName,
              homeRole: homeRole,
              unreadCount: unreadCount,
              onProfile: () =>
                  ref.read(tabIndexProvider.notifier).setTab(4),
              onSwap: () {
                Navigator.pushReplacement(
                  context,
                  AppMotion.fadeSlideRoute(const HomeSelectionScreen()),
                );
              },
              onQr: homeRole == 'ADMIN'
                  ? () {
                      final currentHomeId = selectedHome?['home_id'] ??
                          selectedHome?['id'] ??
                          selectedHome?['homeid'];
                      if (currentHomeId != null) {
                        _generateAndShowQr(
                            currentHomeId.toString(), homeName);
                      }
                    }
                  : null,
              onNotifications: () {
                Navigator.push(
                  context,
                  AppMotion.fadeSlideRoute(const NotificationScreen()),
                );
              },
              onLogout: _handleLogout,
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text("My Homes", style: Theme.of(context).textTheme.titleLarge),
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
                history: _sensorHistory,
              ),

              ..._buildSpeakerSection(),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text("Quick Access",
                      style: Theme.of(context).textTheme.titleLarge),
                  GestureDetector(
                    onTap: _showScenesInfoSheet,
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 14, color: AppColors.textSub(context)),
                        const SizedBox(width: 4),
                        Text("How scenes work",
                            style: Theme.of(context).textTheme.labelMedium),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "One tap controls multiple devices.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              Showcase(
                key: OnboardingKeys.scenes,
                title: 'Quick Access scenes',
                description:
                    'Tap a scene to run it. Long-press any tile to swap it for one of 8 presets like Sleep, Reading, or Party.',
                tooltipBackgroundColor: AppColors.primaryBlue,
                textColor: Colors.white,
                titleTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                descTextStyle:
                    const TextStyle(color: Colors.white, fontSize: 13),
                child: GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  // Phones get a 2-column grid; tablets/landscape get 4 so
                  // scene cards stop ballooning into oversized rectangles.
                  crossAxisCount:
                      AppBreakpoints.isTabletOrLarger(context) ? 4 : 2,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisExtent: 150,
                ),
                children: [
                  for (int i = 0; i < _slots.length; i++)
                    SceneCard(
                      icon: _slots[i].icon,
                      label: _slots[i].label,
                      description: _slots[i].description,
                      accent: _slots[i].accent,
                      loading: _runningScene == _slots[i].key,
                      enabled: _runningScene == null,
                      onLongPress: () => _replaceSlot(i),
                      onTap: () {
                        final key = _slots[i].key;
                        if (key == 'all_off') {
                          _confirmAllOff();
                        } else if (key == 'mood') {
                          ref.read(aiSubTabProvider.notifier).setTab(0);
                          ref.read(tabIndexProvider.notifier).setTab(1);
                        } else {
                          _runScene(key, _slots[i].label);
                        }
                      },
                    ),
                ],
                ),
              ),

              const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Hero header with gradient + glow + action buttons. Lives at the top
// of the dashboard — replaces the old crowded "Welcome Back" + 3-button
// row. Action buttons are exposed as callbacks so the parent owns the
// state (homeId, role, etc).
// ─────────────────────────────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.homeName,
    required this.homeRole,
    required this.unreadCount,
    required this.onProfile,
    required this.onSwap,
    required this.onNotifications,
    required this.onLogout,
    this.onQr,
  });

  final String homeName;
  final String homeRole;
  final int unreadCount;
  final VoidCallback onProfile;
  final VoidCallback onSwap;
  final VoidCallback onNotifications;
  final VoidCallback onLogout;
  final VoidCallback? onQr;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [Color(0xFF1B2654), Color(0xFF2196F3), Color(0xFF00BFA5)]
          : const [Color(0xFF2196F3), Color(0xFF00BFA5)],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 28),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onProfile,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.person, color: Colors.white),
                ),
              ),
              const Spacer(),
              if (onQr != null)
                _GlassIconBtn(
                    icon: Icons.qr_code_scanner, onTap: onQr!),
              if (onQr != null) const SizedBox(width: 8),
              _GlassIconBtn(icon: Icons.swap_horiz, onTap: onSwap),
              const SizedBox(width: 8),
              _GlassIconBtn(
                icon: Icons.notifications_outlined,
                onTap: onNotifications,
                badge: unreadCount,
              ),
              const SizedBox(width: 8),
              _GlassIconBtn(icon: Icons.logout, onTap: onLogout),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.accentGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Online · Welcome back',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  homeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.1,
                  ),
                ),
              ),
              if (homeRole.isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    homeRole,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GlassIconBtn extends StatelessWidget {
  const _GlassIconBtn({
    required this.icon,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
        if (badge > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColors.accentRed,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                badge > 9 ? '9+' : '$badge',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}