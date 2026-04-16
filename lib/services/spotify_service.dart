import 'dart:math';
import 'package:flutter/foundation.dart';

import 'spotify/spotify_api_client.dart';
import 'spotify/spotify_auth.dart';
import 'spotify/spotify_logger.dart';
import 'spotify/spotify_mood_catalog.dart';

/// Thin facade that screens and providers consume. All real work lives in
/// the four modules under `services/spotify/`:
///   - SpotifyAuth:        OAuth + token lifecycle
///   - SpotifyApiClient:   raw Spotify Web API calls
///   - SpotifyMoodCatalog: mood-keyword matching against the user's catalog
///   - SpotifyLogger:      shared file logger
class SpotifyService {
  // ── Auth (proxied) ────────────────────────────────────────────────
  static bool get isAuthenticated => SpotifyAuth.isAuthenticated;
  static Future<bool> login() => SpotifyAuth.login();
  static Future<bool> loadSavedToken() => SpotifyAuth.loadSavedToken();
  static Future<bool> exchangeCodeForToken(String code) =>
      SpotifyAuth.exchangeCodeForToken(code);
  static Future<void> disconnect() => SpotifyAuth.disconnect();

  // ── API (proxied) ─────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>?> getTopArtists({
    int limit = 10,
    String timeRange = 'medium_term',
  }) =>
      SpotifyApiClient.getTopArtists(limit: limit, timeRange: timeRange);

  static Future<List<Map<String, dynamic>>?> getTopTracks({
    int limit = 20,
    String timeRange = 'medium_term',
  }) =>
      SpotifyApiClient.getTopTracks(limit: limit, timeRange: timeRange);

  static Future<List<Map<String, dynamic>>?> getRecentlyPlayed({
    int limit = 20,
  }) =>
      SpotifyApiClient.getRecentlyPlayed(limit: limit);

  // ── Mood recommendation pipeline ──────────────────────────────────

  /// Full pipeline: mood + confidence in, ranked recommendations out.
  /// Falls back to static mock data when not authenticated so the UI
  /// always has something to show in dev.
  static Future<Map<String, dynamic>> getMoodBasedRecommendations({
    required String mood,
    double confidence = 0.94,
    int limit = 10,
  }) async {
    final result = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'input_mood': mood,
      'confidence': confidence,
      'authenticated': isAuthenticated,
    };

    await SpotifyLogger.log('PIPELINE_START', {
      'mood': mood,
      'confidence': confidence,
      'authenticated': isAuthenticated,
    });

    if (!isAuthenticated) {
      result['error'] = 'Spotify not authenticated';
      result['recommendations'] = _mockRecommendations(mood);
      result['source'] = 'mock_data';
      await SpotifyLogger.log('PIPELINE_MOCK_MODE', result);
      return result;
    }

    // Top artists: diagnostics only (helps understand why a rec appeared)
    final topArtists =
        await SpotifyApiClient.getTopArtists(limit: 10, timeRange: 'medium_term');
    result['user_artists'] =
        topArtists?.map((a) => a['name'] as String? ?? '').toList() ?? [];

    final catalogResult =
        await SpotifyMoodCatalog.recommend(mood: mood, limit: limit);
    result['catalog_attempt'] = catalogResult;

    final recommendations = (catalogResult['tracks'] as List?)
        ?.cast<Map<String, dynamic>>();

    result['recommendations'] = recommendations;
    result['recommendations_count'] = recommendations?.length ?? 0;
    result['source'] = 'spotify_api';
    result['recommendations_strategy'] = 'user_catalog';

    await SpotifyLogger.log('PIPELINE_COMPLETE', result);
    return result;
  }

  // ── Dev helpers ───────────────────────────────────────────────────

  /// Clear the Spotify dev log file.
  static Future<void> clearLog() => SpotifyLogger.clear();

  /// Dev test runner — exercises the pipeline with placeholder moods.
  static Future<void> runDevTest() async {
    await SpotifyLogger.log('DEV_TEST_START', {
      'has_client_id': SpotifyAuth.hasClientId,
      'has_client_secret': SpotifyAuth.hasClientSecret,
    });

    final testMoods = ['happy', 'sad', 'melancholy', 'angry', 'calm', 'excited'];
    for (final mood in testMoods) {
      final confidence = 0.80 + Random().nextDouble() * 0.20;
      final result = await getMoodBasedRecommendations(
        mood: mood,
        confidence: double.parse(confidence.toStringAsFixed(2)),
      );
      debugPrint(
          '[SpotifyDev] Mood: $mood → ${result['recommendations_count'] ?? 'mock'} tracks (source: ${result['source']})');
    }

    await SpotifyLogger.log(
        'DEV_TEST_COMPLETE', {'moods_tested': testMoods});
  }

  // ── Mock data (used when not authenticated) ───────────────────────

  static List<Map<String, dynamic>> _mockRecommendations(String mood) {
    final mockData = <String, List<Map<String, dynamic>>>{
      'happy': [
        {'name': 'Happy', 'artist': 'Pharrell Williams', 'id': 'mock_1'},
        {'name': 'Walking on Sunshine', 'artist': 'Katrina & The Waves', 'id': 'mock_2'},
        {'name': 'Good as Hell', 'artist': 'Lizzo', 'id': 'mock_3'},
        {'name': 'Uptown Funk', 'artist': 'Bruno Mars', 'id': 'mock_4'},
        {'name': 'Levitating', 'artist': 'Dua Lipa', 'id': 'mock_5'},
      ],
      'sad': [
        {'name': 'Someone Like You', 'artist': 'Adele', 'id': 'mock_1'},
        {'name': 'Fix You', 'artist': 'Coldplay', 'id': 'mock_2'},
        {'name': 'Skinny Love', 'artist': 'Bon Iver', 'id': 'mock_3'},
        {'name': 'Hurt', 'artist': 'Johnny Cash', 'id': 'mock_4'},
        {'name': 'Mad World', 'artist': 'Gary Jules', 'id': 'mock_5'},
      ],
      'melancholy': [
        {'name': 'Creep', 'artist': 'Radiohead', 'id': 'mock_1'},
        {'name': 'Midnight City', 'artist': 'M83', 'id': 'mock_2'},
        {'name': 'Space Song', 'artist': 'Beach House', 'id': 'mock_3'},
        {'name': 'Breathe Me', 'artist': 'Sia', 'id': 'mock_4'},
        {'name': 'Re: Stacks', 'artist': 'Bon Iver', 'id': 'mock_5'},
      ],
      'angry': [
        {'name': 'Killing in the Name', 'artist': 'Rage Against the Machine', 'id': 'mock_1'},
        {'name': 'Break Stuff', 'artist': 'Limp Bizkit', 'id': 'mock_2'},
        {'name': 'Given Up', 'artist': 'Linkin Park', 'id': 'mock_3'},
        {'name': 'Du Hast', 'artist': 'Rammstein', 'id': 'mock_4'},
        {'name': 'Chop Suey!', 'artist': 'System of a Down', 'id': 'mock_5'},
      ],
      'calm': [
        {'name': 'Weightless', 'artist': 'Marconi Union', 'id': 'mock_1'},
        {'name': 'Clair de Lune', 'artist': 'Debussy', 'id': 'mock_2'},
        {'name': 'Sunset Lover', 'artist': 'Petit Biscuit', 'id': 'mock_3'},
        {'name': 'Gymnopédie No.1', 'artist': 'Erik Satie', 'id': 'mock_4'},
        {'name': 'Nuvole Bianche', 'artist': 'Ludovico Einaudi', 'id': 'mock_5'},
      ],
      'excited': [
        {'name': 'Titanium', 'artist': 'David Guetta ft. Sia', 'id': 'mock_1'},
        {'name': 'Levels', 'artist': 'Avicii', 'id': 'mock_2'},
        {'name': 'Bangarang', 'artist': 'Skrillex', 'id': 'mock_3'},
        {'name': 'Sandstorm', 'artist': 'Darude', 'id': 'mock_4'},
        {'name': "Don't Stop Me Now", 'artist': 'Queen', 'id': 'mock_5'},
      ],
    };

    return mockData[mood.toLowerCase()] ??
        mockData['neutral'] ??
        [
          {'name': 'Bohemian Rhapsody', 'artist': 'Queen', 'id': 'mock_default_1'},
          {'name': 'Hotel California', 'artist': 'Eagles', 'id': 'mock_default_2'},
          {'name': 'Stairway to Heaven', 'artist': 'Led Zeppelin', 'id': 'mock_default_3'},
        ];
  }
}
