import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../services/spotify_service.dart';

/// Spotify connection test and mood recommendation test screen.
/// This screen is only for development/testing purposes.
class SpotifyTestScreen extends StatefulWidget {
  const SpotifyTestScreen({super.key});

  @override
  State<SpotifyTestScreen> createState() => _SpotifyTestScreenState();
}

class _SpotifyTestScreenState extends State<SpotifyTestScreen> {
  bool _isConnected = false;
  bool _isLoading = false;
  String _statusMessage = 'Spotify connection not tested yet.';

  // Test results
  final List<_MoodTestResult> _testResults = [];
  bool _testRunning = false;

  // User info
  List<Map<String, dynamic>>? _recentTracks;

  @override
  void initState() {
    super.initState();
    _checkExistingConnection();
  }

  Future<void> _checkExistingConnection() async {
    final loaded = await SpotifyService.loadSavedToken();
    if (loaded) {
      setState(() {
        _isConnected = true;
        _statusMessage = 'Existing token loaded. Connection active.';
      });
    }
  }

  // User's favorite artists
  List<String> _topArtists = [];

  /// One-button Spotify login (automatic code capture)
  Future<void> _loginToSpotify() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Connecting to Spotify...';
    });

    try {
      final success = await SpotifyService.login();

      setState(() {
        _isLoading = false;
        _isConnected = success;
        _statusMessage = success
            ? 'Spotify connection successful!'
            : 'Connection failed. Please try again.';
      });

      if (success) {
        await _fetchUserData();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error: $e';
      });
    }
  }

  /// Fetch user data
  Future<void> _fetchUserData() async {
    setState(() => _statusMessage = 'Fetching user data...');

    final recent = await SpotifyService.getRecentlyPlayed(limit: 5);
    final topArtists = await SpotifyService.getTopArtists(limit: 5);

    setState(() {
      _recentTracks = recent;
      if (topArtists != null) {
        _topArtists = topArtists.map((a) => a['name'] as String).toList();
      }
      _statusMessage = 'Data received. '
          '${recent?.length ?? 0} tracks, ${_topArtists.length} favorite artists.';
    });
  }

  /// Test all moods
  Future<void> _runMoodTests() async {
    setState(() {
      _testRunning = true;
      _testResults.clear();
      _statusMessage = 'Running mood tests...';
    });

    final moods = ['happy', 'sad', 'melancholy', 'angry', 'calm', 'excited', 'neutral'];

    for (final mood in moods) {
      final stopwatch = Stopwatch()..start();
      final result = await SpotifyService.getMoodBasedRecommendations(
        mood: mood,
        confidence: 0.90,
        limit: 5,
      );
      stopwatch.stop();

      final tracks = result['recommendations'] as List?;
      final source = result['source'] as String? ?? 'unknown';

      setState(() {
        _testResults.add(_MoodTestResult(
          mood: mood,
          trackCount: tracks?.length ?? 0,
          tracks: tracks?.map((t) {
            if (t is Map) return '${t['name']} - ${t['artist']}';
            return t.toString();
          }).toList() ?? [],
          source: source,
          duration: stopwatch.elapsedMilliseconds,
          success: tracks != null && tracks.isNotEmpty,
        ));
      });
    }

    setState(() {
      _testRunning = false;
      _statusMessage = 'All tests completed! '
          '${_testResults.where((r) => r.success).length}/${_testResults.length} succeeded. '
          'Details: logs/spotify_dev.log';
    });
  }

  /// Disconnect
  Future<void> _disconnect() async {
    await SpotifyService.disconnect();
    setState(() {
      _isConnected = false;
      _recentTracks = null;
      _testResults.clear();
      _statusMessage = 'Spotify disconnected.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: const Text('Spotify Test'),
        backgroundColor: const Color(0xFF1DB954),
        foregroundColor: Colors.white,
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.link_off),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Status Card ---
            _buildStatusCard(),
            const SizedBox(height: 16),

            // --- If not connected: Login flow ---
            if (!_isConnected) ...[
              _buildLoginSection(),
            ],

            // --- If connected: Test controls ---
            if (_isConnected) ...[
              _buildConnectedSection(),
              const SizedBox(height: 16),
              _buildMoodTestSection(),
            ],

            // --- Test Results ---
            if (_testResults.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildTestResults(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isConnected ? const Color(0xFF1DB954).withValues(alpha: 0.1) : AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isConnected ? const Color(0xFF1DB954) : AppColors.borderCol(context),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isConnected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: _isConnected ? const Color(0xFF1DB954) : AppColors.textSub(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isConnected ? 'Spotify Connected' : 'Spotify Not Connected',
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusMessage,
                  style: TextStyle(color: AppColors.textSub(context), fontSize: 12),
                ),
              ],
            ),
          ),
          if (_isLoading)
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1DB954)),
            ),
        ],
      ),
    );
  }

  Widget _buildLoginSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _loginToSpotify,
            icon: _isLoading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.music_note),
            label: Text(_isLoading ? 'Connecting...' : 'Sign in with Spotify'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Tap the button → Sign in on Spotify → Grant permission → Auto-connects.',
          style: TextStyle(color: AppColors.textSub(context), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildConnectedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Recently played
        if (_recentTracks != null && _recentTracks!.isNotEmpty) ...[
          Text(
            'Recently Played Tracks',
            style: TextStyle(
              color: AppColors.text(context),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          ...(_recentTracks!.map((track) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.music_note, size: 16, color: Color(0xFF1DB954)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track['name'] ?? '',
                        style: TextStyle(color: AppColors.text(context), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        track['artist'] ?? '',
                        style: TextStyle(color: AppColors.textSub(context), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ))),
        ],

        // Top Artists
        if (_topArtists.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Your Favorite Artists',
            style: TextStyle(
              color: AppColors.text(context),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _topArtists.map((artist) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                artist,
                style: const TextStyle(color: Color(0xFF1DB954), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            )).toList(),
          ),
        ],

        if (_recentTracks == null && _isConnected) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _fetchUserData,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Fetch Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.card(context),
                foregroundColor: AppColors.text(context),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMoodTestSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mood Recommendation Test',
          style: TextStyle(
            color: AppColors.text(context),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Fetches and logs recommendations from Spotify for each mood.',
          style: TextStyle(color: AppColors.textSub(context), fontSize: 12),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _testRunning ? null : _runMoodTests,
            icon: _testRunning
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.science),
            label: Text(_testRunning ? 'Tests running...' : 'Test All Moods'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTestResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Test Results',
          style: TextStyle(
            color: AppColors.text(context),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        ..._testResults.map((result) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: result.success ? const Color(0xFF1DB954) : AppColors.accentRed,
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    result.success ? Icons.check_circle : Icons.error,
                    size: 16,
                    color: result.success ? const Color(0xFF1DB954) : AppColors.accentRed,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    result.mood.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.text(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: result.source == 'spotify_api'
                          ? const Color(0xFF1DB954).withValues(alpha: 0.2)
                          : Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      result.source == 'spotify_api' ? 'API' : 'MOCK',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: result.source == 'spotify_api' ? const Color(0xFF1DB954) : Colors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${result.duration}ms',
                    style: TextStyle(color: AppColors.textSub(context), fontSize: 10),
                  ),
                ],
              ),
              if (result.tracks.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...result.tracks.take(3).map((track) => Padding(
                  padding: const EdgeInsets.only(left: 24, bottom: 2),
                  child: Text(
                    track,
                    style: TextStyle(color: AppColors.textSub(context), fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                if (result.tracks.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Text(
                      '+${result.tracks.length - 3} more...',
                      style: TextStyle(color: AppColors.textSub(context), fontSize: 10),
                    ),
                  ),
              ],
            ],
          ),
        )),
      ],
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

class _MoodTestResult {
  final String mood;
  final int trackCount;
  final List<String> tracks;
  final String source;
  final int duration;
  final bool success;

  _MoodTestResult({
    required this.mood,
    required this.trackCount,
    required this.tracks,
    required this.source,
    required this.duration,
    required this.success,
  });
}
