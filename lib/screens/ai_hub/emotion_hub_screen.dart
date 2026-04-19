import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/app_colors.dart';
import '../../constants/mood_palette.dart';
import '../../providers/mood_provider.dart';
import '../../services/emotion_api_service.dart';
import '../../services/spotify_service.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';
import 'widgets/ambient_section.dart';
import 'widgets/mood_card.dart';
import 'widgets/mood_picker_sheet.dart';
import 'widgets/mood_tracks_list.dart';
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

  @override
  void initState() {
    super.initState();
    _initSpotify();
    _fetchLastEmotion();
  }

  Future<void> _fetchLastEmotion() async {
    // Biraz bekle provider render olsun
    await Future.delayed(Duration.zero);
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'])?.toString();
    if (homeId != null) {
      final lastEmotion = await ApiService.fetchLatestEmotion(homeId);
      if (lastEmotion != null && lastEmotion['emotion'] != null && mounted) {
        // Zaten sette api istegi atan listen var, onu tetiklememek için source="init" yolluyoruz ve listen ona göre davranacak.
        ref.read(moodProvider.notifier).set(lastEmotion['emotion'], lastEmotion['confidence']?.toDouble() ?? 1.0, source: 'init');
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

  Future<void> _fetchMoodTracks() async {
    final mood = ref.read(moodProvider).mood;
    if (mood == null) return;
    setState(() => _spotifyLoading = true);

    final result = await SpotifyService.getMoodBasedRecommendations(
      mood: mood,
      confidence: ref.read(moodProvider).confidence,
      limit: 5,
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan error: $e'),
          backgroundColor: AppColors.accentRed,
          duration: const Duration(seconds: 3),
        ),
      );
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
      if (next.mood != null && next.mood != prev?.mood) {
        _fetchMoodTracks();
        
        if (next.source != 'init') {
          final selectedHome = ref.read(selectedHomeProvider);
          final homeId = (selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'])?.toString();
          if (homeId != null) {
            ApiService.saveEmotion(homeId, next.mood!, confidence: next.confidence);
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
                    const SizedBox(height: 32),
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
                    const SizedBox(height: 36),
                    MoodTracksList(
                      isConnected: isConnected,
                      isLoading: _spotifyLoading,
                      hasMood: mood.mood != null,
                      tracks: _currentTracks,
                      moodColor: moodColor,
                      onConnect: _connectSpotify,
                      onRefresh: _fetchMoodTracks,
                    ),
                    const SizedBox(height: 28),
                    AmbientSection(mood: mood.mood),
                    const SizedBox(height: 24),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Emotion Hub',
            style: TextStyle(
              color: AppColors.text(context),
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
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
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
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
