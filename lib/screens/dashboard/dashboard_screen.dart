import 'dart:async';
import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
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
import '../../providers/mood_provider.dart';
import '../../providers/navigation_provider.dart';
import 'home_selection_screen.dart';
import '../../services/api_service.dart';
import 'widgets/my_homes_list.dart';
import 'widgets/quick_access_button.dart';
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
  Timer? _dashboardPollingTimer;

  // Cached actuator list used by the Quick Access scenes.
  List<dynamic> _devices = [];
  String? _runningScene; // 'all_off' | 'movie' | 'bright' | null

  // Speaker control state. Mirrors property values from _devices and is
  // updated optimistically on user interaction so the UI feels instant.
  final Map<String, Map<String, dynamic>> _speakerStates = {};
  Timer? _speakerVolumeDebounce;

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
        MaterialPageRoute(builder: (context) => const LoginScreen()),
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
    final ok = await ApiService.sendCommand(
      homeId: homeId,
      deviceId: deviceId,
      action: prop,
      value: value is num ? value.toInt().toString() : value,
    );
    if (!mounted) return;
    setState(() {
      _speakerStates[deviceId]?.remove('_dirty_$prop');
    });
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
      return;
    }

    setState(() => _runningScene = key);
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
                  "Each scene runs in parallel against the matching devices in this home.",
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
                  padding: const EdgeInsets.all(12),
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
    final playback = (state['playback'] ?? 'stop').toString();
    final vol = state['volume'] is num
        ? (state['volume'] as num).toInt()
        : int.tryParse(state['volume']?.toString() ?? '') ?? 50;

    return [
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(20),
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
                      Text(
                        isOn
                            ? '${_playbackLabel(playback)} · $vol%'
                            : 'Off',
                        style: TextStyle(
                          color: isOn ? Colors.pinkAccent : AppColors.textSub(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: isOn,
                  activeThumbColor: Colors.pinkAccent,
                  onChanged: (val) =>
                      _setSpeakerProp(id, 'power', val ? 'on' : 'off'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPlaybackBtn(id, Icons.play_arrow, 'play', playback == 'play'),
                _buildPlaybackBtn(id, Icons.pause, 'pause', playback == 'pause'),
                _buildPlaybackBtn(id, Icons.stop, 'stop', playback == 'stop'),
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
                onTap: () => ref.read(tabIndexProvider.notifier).setTab(4),
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

  String _playbackLabel(String s) {
    switch (s) {
      case 'play':
        return 'Playing';
      case 'pause':
        return 'Paused';
      default:
        return 'Stopped';
    }
  }

  Widget _buildPlaybackBtn(String id, IconData icon, String value, bool selected) {
    return GestureDetector(
      onTap: () => _setSpeakerProp(id, 'playback', value),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: selected
              ? Colors.pinkAccent.withValues(alpha: 0.18)
              : AppColors.card(context),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.pinkAccent : AppColors.borderCol(context),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Icon(icon, color: selected ? Colors.pinkAccent : AppColors.text(context), size: 22),
      ),
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
         _fetchDevicesForScenes(homeId);
       });

       _dashboardPollingTimer?.cancel();
       _dashboardPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
         if (!mounted) return;
         _fetchSensors(homeId);
         _fetchDevicesForScenes(homeId); // keep speaker card state fresh
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

              ..._buildSpeakerSection(),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text("Quick Access", style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold)),
                  GestureDetector(
                    onTap: _showScenesInfoSheet,
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 14, color: AppColors.textSub(context)),
                        const SizedBox(width: 4),
                        Text(
                          "How scenes work",
                          style: TextStyle(
                            color: AppColors.textSub(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "One tap controls multiple devices.",
                style: TextStyle(color: AppColors.textSub(context), fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  QuickAccessButton(
                    icon: Icons.power_settings_new,
                    label: 'All Off',
                    description: 'Turn everything off',
                    iconColor: Colors.white,
                    highlighted: true,
                    highlightColor: AppColors.accentRed,
                    loading: _runningScene == 'all_off',
                    enabled: _runningScene == null,
                    onTap: _confirmAllOff,
                  ),
                  QuickAccessButton(
                    icon: Icons.movie_creation,
                    label: 'Movie',
                    description: 'Dim warm · TV on',
                    iconColor: Colors.white,
                    highlighted: true,
                    highlightColor: Colors.deepPurpleAccent,
                    loading: _runningScene == 'movie',
                    enabled: _runningScene == null,
                    onTap: () => _runScene('movie', 'Movie'),
                  ),
                  QuickAccessButton(
                    icon: Icons.wb_sunny,
                    label: 'Bright',
                    description: 'Lights full white',
                    iconColor: Colors.white,
                    highlighted: true,
                    highlightColor: Colors.amber.shade700,
                    loading: _runningScene == 'bright',
                    enabled: _runningScene == null,
                    onTap: () => _runScene('bright', 'Bright'),
                  ),
                  QuickAccessButton(
                    icon: Icons.palette,
                    label: 'Mood',
                    description: 'AI emotion control',
                    iconColor: Colors.pinkAccent,
                    enabled: _runningScene == null,
                    onTap: () => ref.read(tabIndexProvider.notifier).setTab(1),
                  ),
                ],
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}