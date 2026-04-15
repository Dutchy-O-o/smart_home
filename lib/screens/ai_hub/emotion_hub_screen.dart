import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/app_colors.dart';
import '../../providers/mood_provider.dart';
import '../../services/emotion_api_service.dart';
import '../../services/spotify_service.dart';


class EmotionHubScreen extends ConsumerStatefulWidget {
  const EmotionHubScreen({super.key});

  @override
  ConsumerState<EmotionHubScreen> createState() => _EmotionHubScreenState();
}

class _EmotionHubScreenState extends ConsumerState<EmotionHubScreen> {
  String? get _currentMood => ref.read(moodProvider).mood;
  double get _confidence => ref.read(moodProvider).confidence;

  bool _isScanning = false;
  final ImagePicker _picker = ImagePicker();

  bool _spotifyLoading = false;
  List<Map<String, dynamic>>? _currentTracks;

  static const Map<String, String> _moodEmojis = {
    'happy': '😊',
    'sad': '😢',
    'melancholy': '🌧️',
    'angry': '😠',
    'calm': '😌',
    'excited': '🤩',
    'neutral': '😐',
    'fearful': '😨',
    'surprised': '😮',
    'disgusted': '🤢',
    'disgust': '🤢',
    'fear': '😨',
    'surprise': '😮',
  };

  static const Map<String, Color> _moodColors = {
    'happy': Color(0xFFFFB800),
    'sad': Color(0xFF4A7FBF),
    'melancholy': Color(0xFF6B7FAA),
    'angry': Color(0xFFE53935),
    'calm': Color(0xFF4DB6AC),
    'excited': Color(0xFFFF6B9D),
    'neutral': Color(0xFF9E9E9E),
    'fearful': Color(0xFF7E57C2),
    'fear': Color(0xFF7E57C2),
    'surprised': Color(0xFFFFCA28),
    'surprise': Color(0xFFFFCA28),
    'disgusted': Color(0xFF8BC34A),
    'disgust': Color(0xFF8BC34A),
  };

  Color get _moodColor => _moodColors[_currentMood?.toLowerCase()] ?? AppColors.primaryBlue;
  String get _moodEmoji => _moodEmojis[_currentMood?.toLowerCase()] ?? '✨';

  @override
  void initState() {
    super.initState();
    _initSpotify();
  }

  Future<void> _initSpotify() async {
    await SpotifyService.loadSavedToken();
    if (mounted) setState(() {}); // refresh auth state
    // Don't auto-fetch on first open — wait for user to scan
  }

  Future<void> _connectSpotify() async {
    setState(() {
      _spotifyLoading = true;
    });

    try {
      final success = await SpotifyService.login();
      if (mounted) {
        if (success) {
          await _fetchMoodTracks();
        } else {
          setState(() {
  
            _spotifyLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {

          _spotifyLoading = false;
        });
      }
    }
  }

  Future<void> _fetchMoodTracks() async {
    // Skip fetch if no mood scanned yet
    if (_currentMood == null) return;
    setState(() => _spotifyLoading = true);

    final result = await SpotifyService.getMoodBasedRecommendations(
      mood: _currentMood!,
      confidence: _confidence,
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
        title: Text('Spotify Connection', style: TextStyle(color: AppColors.text(context))),
        content: Text('Disconnect your Spotify account?',
            style: TextStyle(color: AppColors.textSub(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SpotifyService.disconnect();
      if (mounted) {
        setState(() {
          _currentTracks = null;
        });
      }
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

  @override
  Widget build(BuildContext context) {
    // Refresh Spotify recommendations when mood changes (manual/scan/chatbot)
    ref.listen<MoodState>(moodProvider, (prev, next) {
      if (next.mood != null && next.mood != prev?.mood) {
        _fetchMoodTracks();
      }
    });

    ref.watch(moodProvider); // rebuild trigger
    final isConnected = SpotifyService.isAuthenticated;
    final hasMood = _currentMood != null;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isConnected),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    _buildScanArea(),
                    const SizedBox(height: 14),
                    Center(
                      child: TextButton.icon(
                        onPressed: _isScanning ? null : _showMoodPicker,
                        icon: Icon(Icons.touch_app,
                            color: AppColors.textSub(context), size: 16),
                        label: Text(
                          'Pick manually',
                          style: TextStyle(
                            color: AppColors.textSub(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildMoodCard(hasMood),
                    const SizedBox(height: 36),
                    _buildSpotifySection(isConnected),
                    const SizedBox(height: 28),
                    _buildAmbientSection(),
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

  Widget _buildAmbientSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.textSub(context), size: 20),
              const SizedBox(width: 8),
              Text(
                'Ambient',
                style: TextStyle(
                  color: AppColors.text(context),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.textSub(context).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'SOON',
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Lights and curtains will adjust to your mood.',
            style: TextStyle(color: AppColors.textSub(context), fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildAmbientTile(
                  icon: Icons.lightbulb_outline,
                  title: 'Light',
                  status: _currentMood == null
                      ? 'Pending'
                      : 'Tone: ${_moodColor.value.toRadixString(16).substring(2).toUpperCase()}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAmbientTile(
                  icon: Icons.curtains_outlined,
                  title: 'Curtain',
                  status: _currentMood == null
                      ? 'Pending'
                      : _suggestCurtainState(_currentMood!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientTile({
    required IconData icon,
    required String title,
    required String status,
  }) {
    final muted = AppColors.textSub(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context).withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderCol(context).withOpacity(0.5),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: muted, size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: muted.withOpacity(0.8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _suggestCurtainState(String mood) {
    switch (mood.toLowerCase()) {
      case 'happy':
      case 'excited':
        return 'Fully open';
      case 'sad':
      case 'melancholy':
      case 'fearful':
      case 'fear':
        return 'Half close';
      case 'calm':
        return 'Slightly open';
      case 'angry':
        return 'Close';
      default:
        return 'Auto';
    }
  }

  Widget _buildHeader(bool isConnected) {
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
          _buildHeaderIcon(
            icon: isConnected ? Icons.link : Icons.link_off,
            color: isConnected
                ? const Color(0xFF1DB954)
                : AppColors.textSub(context),
            onTap: isConnected ? _disconnectSpotify : _connectSpotify,
            loading: _spotifyLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool loading = false,
  }) {
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
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              : Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  static const List<String> _pickableMoods = [
    'happy',
    'sad',
    'melancholy',
    'angry',
    'calm',
    'excited',
    'neutral',
    'fearful',
    'surprised',
    'disgusted',
  ];

  void _showMoodPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final moods = _pickableMoods
            .map((m) => MapEntry(m, _moodEmojis[m] ?? '✨'))
            .toList();
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textSub(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Pick your mood',
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set mood directly without scanning',
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: moods.map((entry) {
                    final mood = entry.key;
                    final emoji = entry.value;
                    final color = _moodColors[mood] ?? AppColors.primaryBlue;
                    final label = mood[0].toUpperCase() + mood.substring(1);
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        ref.read(moodProvider.notifier)
                            .set(mood, 1.0, source: 'manual');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: color.withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(emoji, style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 8),
                            Text(
                              label,
                              style: TextStyle(
                                color: AppColors.text(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScanArea() {
    return Center(
      child: GestureDetector(
        onTap: _isScanning ? null : _scanEmotion,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                _moodColor.withOpacity(0.35),
                _moodColor.withOpacity(0.05),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: _moodColor.withOpacity(_isScanning ? 0.5 : 0.25),
                blurRadius: _isScanning ? 50 : 30,
                spreadRadius: _isScanning ? 6 : 2,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card(context),
                  border: Border.all(color: _moodColor.withOpacity(0.6), width: 2),
                ),
                child: ClipOval(child: _scanPlaceholder()),
              ),
              if (_isScanning)
                Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.5),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(color: _moodColor),
                  ),
                ),
              if (!_isScanning)
                Positioned(
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _moodColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.camera_alt, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Scan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scanPlaceholder() {
    return Container(
      color: AppColors.card(context),
      child: Center(
        child: Text(
          _moodEmoji,
          style: const TextStyle(fontSize: 80),
        ),
      ),
    );
  }

  Widget _buildMoodCard(bool hasMood) {
    if (!hasMood) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          'Scan your face to read your mood',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSub(context),
            fontSize: 14,
          ),
        ),
      );
    }

    final moodLabel = _currentMood![0].toUpperCase() + _currentMood!.substring(1);
    final confPct = (_confidence * 100).toInt();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _moodColor.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Text(_moodEmoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  moodLabel,
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Confidence',
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _moodColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '%$confPct',
              style: TextStyle(
                color: _moodColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpotifySection(bool isConnected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, color: Color(0xFF1DB954), size: 20),
              const SizedBox(width: 8),
              Text(
                'Mood Tracks',
                style: TextStyle(
                  color: AppColors.text(context),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (isConnected && _currentTracks != null)
                GestureDetector(
                  onTap: _spotifyLoading ? null : _fetchMoodTracks,
                  child: Icon(Icons.refresh,
                      color: AppColors.textSub(context), size: 20),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (!isConnected)
            _spotifyConnectPrompt()
          else if (_currentMood == null)
            _spotifyEmptyState('Scan first to see recommendations.')
          else if (_spotifyLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 28, height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            )
          else if (_currentTracks == null || _currentTracks!.isEmpty)
            _spotifyEmptyState('No recommendations found.')
          else
            ..._currentTracks!.map(_buildTrackRow),
        ],
      ),
    );
  }

  Widget _spotifyConnectPrompt() {
    return GestureDetector(
      onTap: _spotifyLoading ? null : _connectSpotify,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1DB954), Color(0xFF117A37)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.music_note, color: Colors.white),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Connect Spotify — for mood-based tracks',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _spotifyLoading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _spotifyEmptyState(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: AppColors.textSub(context), fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildTrackRow(Map<String, dynamic> t) {
    final name = (t['name'] ?? '-').toString();
    final artist = (t['artist'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderCol(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _moodColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.music_note, color: _moodColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.speaker, color: AppColors.textSub(context), size: 18),
        ],
      ),
    );
  }
}
