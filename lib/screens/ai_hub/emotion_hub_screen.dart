import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/app_colors.dart';
import '../../constants/mood_palette.dart';
import '../../providers/mood_provider.dart';
import '../../providers/home_provider.dart';
import '../../services/emotion_api_service.dart';
import '../../services/spotify_service.dart';
import '../../services/api_service.dart';
import '../../services/mood_history_service.dart';
import '../../theme/app_spacing.dart';
import 'widgets/ambient_section.dart';
import 'widgets/mood_card.dart';
import 'widgets/mood_picker_sheet.dart';
import 'widgets/mood_tracks_list.dart';
import 'widgets/mood_weekly_heatmap.dart';
import 'widgets/scan_area.dart';

class EmotionHubScreen extends ConsumerStatefulWidget {
  const EmotionHubScreen({super.key});

  @override
  ConsumerState<EmotionHubScreen> createState() => _EmotionHubScreenState();
}

class _EmotionHubScreenState extends ConsumerState<EmotionHubScreen> {
  bool _isScanning = false;
  final ImagePicker _picker = ImagePicker();

  bool _spotifyLoading = false;
  List<Map<String, dynamic>>? _currentTracks;

  // Local 7-day mood heatmap data, refreshed after every set() and on
  // first build. Cached so we don't refetch from disk on each rebuild.
  Map<int, Map<int, String>> _weeklyMoodGrid = const {};

  Future<void> _refreshMoodGrid() async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ??
            selectedHome?['id'] ??
            selectedHome?['homeid'])
        ?.toString();
    final grid = await MoodHistoryService.weeklyGrid(homeId: homeId);
    if (mounted) setState(() => _weeklyMoodGrid = grid);
  }

  @override
  void initState() {
    super.initState();
    _initSpotify();
    _fetchLastEmotion();
    _refreshMoodGrid();
  }

  Future<void> _fetchLastEmotion() async {
    // Biraz bekle provider render olsun
    await Future.delayed(Duration.zero);
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'])?.toString();
    if (homeId != null) {
      final lastEmotion = await ApiService.fetchLatestEmotion(homeId);
      if (lastEmotion != null && lastEmotion['emotion'] != null && mounted) {
        // There is already a listener that makes an API request on set. To prevent triggering it, we send source="init" and the listener will act accordingly.
        ref.read(moodProvider.notifier).set(lastEmotion['emotion'], lastEmotion['confidence']?.toDouble() ?? 1.0, source: 'init');
      } else if (mounted) {
        ref.read(moodProvider.notifier).clear();
      }
    }
  }

  Future<void> _initSpotify() async {
    await SpotifyService.loadSavedToken();
    if (mounted) setState(() {}); // refresh auth state
    // Don't auto-fetch on first open — wait for user to scan
  }

  Future<void> _connectSpotify() async {
    setState(() => _spotifyLoading = true);
    try {
      final success = await SpotifyService.login();
      if (mounted) {
        if (success) {
          await _fetchMoodTracks();
        } else {
          setState(() => _spotifyLoading = false);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _spotifyLoading = false);
    }
  }

  Future<void> _fetchMoodTracks({bool forceRefresh = false}) async {
    final mood = ref.read(moodProvider).mood;
    if (mood == null) return;
    setState(() => _spotifyLoading = true);

    final result = await SpotifyService.getMoodBasedRecommendations(
      mood: mood,
      confidence: ref.read(moodProvider).confidence,
      limit: 5,
      forceRefresh: forceRefresh,
    );

    if (mounted) {
      setState(() {
        _currentTracks = (result['recommendations'] as List?)
            ?.cast<Map<String, dynamic>>();
        _spotifyLoading = false;
      });
    }
  }

  Future<void> _disconnectSpotify() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        title: Text('Spotify Connection',
            style: TextStyle(color: AppColors.text(context))),
        content: Text('Disconnect your Spotify account?',
            style: TextStyle(color: AppColors.textSub(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SpotifyService.disconnect();
      if (mounted) setState(() => _currentTracks = null);
    }
  }

  Future<void> _scanEmotion() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);

    try {
      final XFile? shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (shot == null) {
        if (mounted) setState(() => _isScanning = false);
        return;
      }

      final bytes = await File(shot.path).readAsBytes();
      final result = await EmotionApiService.predictFromJpeg(bytes);

      if (!mounted) return;
      ref.read(moodProvider.notifier)
          .set(result.mood, result.confidence, source: 'scan');
      setState(() => _isScanning = false);

      // Explicit success feedback — without this, a stale cached mood
      // shown in the card can be mistaken for a "successful" scan that
      // actually silently failed. The new snackbar makes success
      // unambiguous and shows what the model detected.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            const Icon(Icons.face_retouching_natural,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Detected: ${result.mood} · ${(result.confidence * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.accentGreen,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);

      // Detect the most common cause — Pi unreachable because the phone
      // and Pi aren't on the same LAN (mDNS-only endpoint). Surface a
      // friendly explanation + an actionable fallback CTA instead of the
      // raw exception that nobody can decode.
      final msg = e.toString();
      final isNetwork = msg.contains('Failed host lookup') ||
          msg.contains('SocketException') ||
          msg.contains('TimeoutException') ||
          msg.contains('Connection refused');

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        // Soft amber rather than red: this isn't an error so much as a
        // privacy-design trade-off. The phrasing reinforces the on-device
        // story instead of looking like a bug.
        backgroundColor:
            isNetwork ? AppColors.accentAmber : AppColors.accentRed,
        duration: const Duration(seconds: 6),
        content: Row(
          children: [
            Icon(
              isNetwork ? Icons.shield_rounded : Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isNetwork
                        ? 'Face scan needs same WiFi as Pi'
                        : 'Scan failed',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    isNetwork
                        ? 'On-device privacy: photos never leave your LAN.'
                        : msg,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Pick manually',
          textColor: Colors.white,
          onPressed: _openMoodPicker,
        ),
      ));
    }
  }

  void _openMoodPicker() {
    showMoodPickerSheet(
      context: context,
      onPicked: (mood) => ref
          .read(moodProvider.notifier)
          .set(mood, 1.0, source: 'manual'),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Refresh Spotify recommendations and DB when mood changes (manual/scan/chatbot)
    ref.listen<MoodState>(moodProvider, (prev, next) {
      if (next.mood != null && next.updatedAt != prev?.updatedAt) {
        if (next.mood != prev?.mood) {
          _fetchMoodTracks();
        }
        // Mood was just appended to local history by the provider in
        // a fire-and-forget write. Wait a beat so the disk has time to
        // settle before we re-read it for the grid; without this the
        // heatmap would show stale data on the cell that just got the
        // new entry.
        if (next.source != 'init') {
          Future.delayed(const Duration(milliseconds: 350), _refreshMoodGrid);
        }

        if (next.source != 'init') {
          final selectedHome = ref.read(selectedHomeProvider);
          final homeId = (selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'])?.toString();
          if (homeId != null) {
            ApiService.evaluateEmotion(homeId, next.mood!, confidenceScore: next.confidence);
          }
        }
      }
    });

    final mood = ref.watch(moodProvider);
    final isConnected = SpotifyService.isAuthenticated;
    final moodColor = MoodPalette.colorFor(mood.mood);
    final moodEmoji = MoodPalette.emojiFor(mood.mood);

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              isConnected: isConnected,
              spotifyLoading: _spotifyLoading,
              onConnect: _connectSpotify,
              onDisconnect: _disconnectSpotify,
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // Privacy/architecture explainer. The face scan endpoint
                    // is intentionally LAN-only (Pi mDNS) so photos never
                    // leave the home network — not even for model training.
                    // Surface this as a feature pill so a connection error
                    // reads as a privacy guarantee rather than a bug.
                    const _PrivacyBadge(),
                    const SizedBox(height: 20),
                    ScanArea(
                      moodEmoji: moodEmoji,
                      moodColor: moodColor,
                      isScanning: _isScanning,
                      onTap: _scanEmotion,
                    ),
                    const SizedBox(height: 14),
                    _PickManuallyButton(
                      enabled: !_isScanning,
                      onTap: _openMoodPicker,
                    ),
                    const SizedBox(height: 14),
                    MoodCard(
                      mood: mood.mood,
                      confidence: mood.confidence,
                    ),
                    AppSpacing.vGapXxl,
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                      child: MoodWeeklyHeatmap(grid: _weeklyMoodGrid),
                    ),
                    const SizedBox(height: 28),
                    MoodTracksList(
                      isConnected: isConnected,
                      isLoading: _spotifyLoading,
                      hasMood: mood.mood != null,
                      tracks: _currentTracks,
                      moodColor: moodColor,
                      onConnect: _connectSpotify,
                      onRefresh: () => _fetchMoodTracks(forceRefresh: true),
                    ),
                    const SizedBox(height: 28),
                    AmbientSection(mood: mood.mood),
                    AppSpacing.vGapXxl,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isConnected,
    required this.spotifyLoading,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool isConnected;
  final bool spotifyLoading;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      child: Row(
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
            child: const Icon(Icons.sentiment_satisfied_alt_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Emotion Hub',
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.05,
                  ),
                ),
                Text(
                  'Scan · pick · soundtrack',
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _HeaderIcon(
            icon: isConnected ? Icons.link : Icons.link_off,
            color: isConnected
                ? const Color(0xFF1DB954)
                : AppColors.textSub(context),
            loading: spotifyLoading,
            onTap: isConnected ? onDisconnect : onConnect,
          ),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Spotify connection',
      child: GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: AppRadius.brSm,
          border: Border.all(color: AppColors.borderCol(context)),
        ),
        child: Center(
          child: loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: color),
                )
              : Icon(icon, color: color, size: 20),
        ),
      ),
      ),
    );
  }
}

class _PickManuallyButton extends StatelessWidget {
  const _PickManuallyButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: enabled ? onTap : null,
        icon:
            Icon(Icons.touch_app, color: AppColors.textSub(context), size: 16),
        label: Text(
          'Pick manually',
          style: TextStyle(
            color: AppColors.textSub(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// "Edge AI · On-device privacy" explainer pill. Sits above the scan area
/// so users (and demo viewers) see the privacy promise BEFORE they tap
/// scan. Tapping it expands an info sheet that breaks down exactly what
/// the system does and doesn't do with face photos.
///
/// This is also why the face scan endpoint stays LAN-only: routing JPEGs
/// through AWS would invalidate the "photos never leave your home"
/// guarantee that the rest of the product is built around.
class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge();

  void _showInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.bg(ctx),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(
              color: AppColors.borderCol(ctx).withValues(alpha: 0.6),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.textSub(ctx).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
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
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Edge AI · On-device privacy',
                          style: TextStyle(
                            color: AppColors.text(ctx),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          )),
                      Text(
                        'Face scan never leaves your home network',
                        style: TextStyle(
                          color: AppColors.textSub(ctx),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _PrivacyRow(
              icon: Icons.memory_rounded,
              title: 'Inference on Raspberry Pi',
              body:
                  'TensorFlow model runs locally on the Pi. Cloud GPUs are never involved.',
            ),
            _PrivacyRow(
              icon: Icons.wifi_lock_rounded,
              title: 'Photos stay on your LAN',
              body:
                  'The phone sends the photo directly to the Pi over your WiFi. No AWS, no third-party hop.',
            ),
            _PrivacyRow(
              icon: Icons.delete_sweep_rounded,
              title: 'Single-use, never stored',
              body:
                  'After the mood is predicted the JPEG is dropped from memory. Not saved, not logged, not used for training.',
            ),
            _PrivacyRow(
              icon: Icons.cloud_off_rounded,
              title: 'LAN required (by design)',
              body:
                  "If the phone and Pi aren't on the same WiFi, face scan won't work — that's the trade-off for the privacy guarantee. Use the manual mood picker as fallback.",
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Got it',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showInfo(context),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.primaryBlue.withValues(alpha: 0.18),
                  AppColors.primaryViolet.withValues(alpha: 0.14),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_rounded,
                    color: AppColors.primaryBlue, size: 14),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Edge AI · Photos never leave your network',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.primaryBlue,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.info_outline_rounded,
                    color: AppColors.primaryBlue.withValues(alpha: 0.7),
                    size: 13),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in the privacy info sheet. Icon + bold title + descriptive body.
class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.30),
              ),
            ),
            child: Icon(icon, color: AppColors.primaryBlue, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
