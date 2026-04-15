import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SpotifyService {
  static const String _authUrl = 'https://accounts.spotify.com/authorize';
  static const String _tokenUrl = 'https://accounts.spotify.com/api/token';
  static const String _apiBase = 'https://api.spotify.com/v1';

  // .env'den okunacak
  static String get _clientId => dotenv.env['SPOTIFY_CLIENT_ID'] ?? '';
  static String get _clientSecret => dotenv.env['SPOTIFY_CLIENT_SECRET'] ?? '';
  static const String _redirectUri = 'akilliev://callback';

  // Token management
  static String? _accessToken;
  static String? _refreshToken;
  static DateTime? _tokenExpiry;

  /// Log file path
  static File? _cachedLogFile;

  static Future<File> _getLogFile() async {
    if (_cachedLogFile != null) return _cachedLogFile!;
    final appDir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${appDir.path}/logs');
    if (!logDir.existsSync()) logDir.createSync(recursive: true);
    _cachedLogFile = File('${logDir.path}/spotify_dev.log');
    debugPrint('[SpotifyService] Log path: ${_cachedLogFile!.path}');
    return _cachedLogFile!;
  }

  // ──────────────────────────────────────────────
  //  LOGGING
  // ──────────────────────────────────────────────

  static Future<void> _log(String category, dynamic data) async {
    final timestamp = DateTime.now().toIso8601String();
    final entry = '''
╔══════════════════════════════════════════════════════════════
║ [$timestamp] $category
╠══════════════════════════════════════════════════════════════
║ ${const JsonEncoder.withIndent('  ').convert(data)}
╚══════════════════════════════════════════════════════════════

''';

    try {
      final logFile = await _getLogFile();
      await logFile.writeAsString(entry, mode: FileMode.append);
      debugPrint('[SpotifyService] $category logged to ${logFile.path}');
    } catch (e) {
      debugPrint('[SpotifyService] Log write error: $e');
    }
  }

  // ──────────────────────────────────────────────
  //  AUTH - OAuth 2.0 PKCE Flow
  // ──────────────────────────────────────────────

  /// Build the OAuth authorization URL (redirect the user to it)
  static String getAuthUrl() {
    debugPrint('[SpotifyService] Client ID: "${_clientId}" (length: ${_clientId.length})');

    final scopes = [
      'user-read-recently-played',
      'user-top-read',
      'user-read-playback-state',
      'user-modify-playback-state',
      'user-read-currently-playing',
      'playlist-read-private',
    ].join(' ');

    final url = '$_authUrl?'
        'client_id=$_clientId'
        '&response_type=code'
        '&redirect_uri=${Uri.encodeComponent(_redirectUri)}'
        '&scope=${Uri.encodeComponent(scopes)}'
        '&show_dialog=true';

    _log('AUTH_URL_GENERATED', {'url': url, 'scopes': scopes});
    return url;
  }

  /// One-shot login: open browser → user grants → capture code → exchange for token
  static Future<bool> login() async {
    try {
      final url = getAuthUrl();

      // In-app browser opens, user signs in, redirect is captured automatically
      final result = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: 'akilliev',
      );

      // Extract code from callback URL
      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) {
        await _log('LOGIN_FAILED', {'error': 'No code in callback', 'result': result});
        return false;
      }

      // Code → token exchange
      return await exchangeCodeForToken(code);
    } catch (e) {
      await _log('LOGIN_ERROR', {'error': e.toString()});
      return false;
    }
  }

  /// Authorization code → access token exchange
  static Future<bool> exchangeCodeForToken(String code) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Basic ${base64Encode(utf8.encode('$_clientId:$_clientSecret'))}',
        },
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': _redirectUri,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _refreshToken = data['refresh_token'];
        _tokenExpiry = DateTime.now().add(Duration(seconds: data['expires_in']));

        // Persist tokens
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('spotify_access_token', _accessToken!);
        await prefs.setString('spotify_refresh_token', _refreshToken!);
        await prefs.setString('spotify_token_expiry', _tokenExpiry!.toIso8601String());

        await _log('TOKEN_EXCHANGE_SUCCESS', {
          'expires_in': data['expires_in'],
          'scope': data['scope'],
          'token_type': data['token_type'],
        });
        return true;
      }

      await _log('TOKEN_EXCHANGE_FAILED', {
        'status': response.statusCode,
        'body': response.body,
      });
      return false;
    } catch (e) {
      await _log('TOKEN_EXCHANGE_ERROR', {'error': e.toString()});
      return false;
    }
  }

  /// Refresh the access token
  static Future<bool> _refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Basic ${base64Encode(utf8.encode('$_clientId:$_clientSecret'))}',
        },
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken!,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _tokenExpiry = DateTime.now().add(Duration(seconds: data['expires_in']));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('spotify_access_token', _accessToken!);
        await prefs.setString('spotify_token_expiry', _tokenExpiry!.toIso8601String());

        await _log('TOKEN_REFRESH_SUCCESS', {'expires_in': data['expires_in']});
        return true;
      }
      return false;
    } catch (e) {
      await _log('TOKEN_REFRESH_ERROR', {'error': e.toString()});
      return false;
    }
  }

  /// Load saved token from disk
  static Future<bool> loadSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('spotify_access_token');
    _refreshToken = prefs.getString('spotify_refresh_token');
    final expiryStr = prefs.getString('spotify_token_expiry');
    if (expiryStr != null) _tokenExpiry = DateTime.parse(expiryStr);

    if (_accessToken != null && _tokenExpiry != null) {
      if (_tokenExpiry!.isBefore(DateTime.now())) {
        return await _refreshAccessToken();
      }
      return true;
    }
    return false;
  }

  /// Auth header
  static Future<Map<String, String>?> _getHeaders() async {
    if (_accessToken == null) return null;

    // Refresh if expired
    if (_tokenExpiry != null && _tokenExpiry!.isBefore(DateTime.now())) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) return null;
    }

    return {
      'Authorization': 'Bearer $_accessToken',
      'Content-Type': 'application/json',
    };
  }

  static bool get isAuthenticated => _accessToken != null;

  // ──────────────────────────────────────────────
  //  SPOTIFY API CALLS
  // ──────────────────────────────────────────────

  /// Get the user's recently played tracks
  static Future<List<Map<String, dynamic>>?> getRecentlyPlayed({int limit = 20}) async {
    final headers = await _getHeaders();
    if (headers == null) {
      await _log('RECENTLY_PLAYED', {'error': 'Not authenticated'});
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$_apiBase/me/player/recently-played?limit=$limit'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = (data['items'] as List).map((item) {
          final track = item['track'];
          final artists = track['artists'] as List;
          return {
            'id': track['id'],
            'name': track['name'],
            'artist': artists.map((a) => a['name']).join(', '),
            'artist_id': artists.first['id'],
            'album': track['album']['name'],
            'played_at': item['played_at'],
            'uri': track['uri'],
          };
        }).toList();

        await _log('RECENTLY_PLAYED_SUCCESS', {
          'count': items.length,
          'tracks': items,
        });
        return List<Map<String, dynamic>>.from(items);
      }

      await _log('RECENTLY_PLAYED_FAILED', {
        'status': response.statusCode,
        'body': response.body,
      });
      return null;
    } catch (e) {
      await _log('RECENTLY_PLAYED_ERROR', {'error': e.toString()});
      return null;
    }
  }

  /// Get the user's top artists
  static Future<List<Map<String, dynamic>>?> getTopArtists({
    int limit = 10,
    String timeRange = 'medium_term',
  }) async {
    final headers = await _getHeaders();
    if (headers == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_apiBase/me/top/artists?limit=$limit&time_range=$timeRange'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = (data['items'] as List).map((artist) => {
          'id': artist['id'],
          'name': artist['name'],
          'genres': (artist['genres'] as List?)?.cast<String>() ?? <String>[],
          'popularity': artist['popularity'],
        }).toList();

        await _log('TOP_ARTISTS_SUCCESS', {
          'count': items.length,
          'time_range': timeRange,
          'artists': items,
        });
        return List<Map<String, dynamic>>.from(items);
      }

      await _log('TOP_ARTISTS_FAILED', {
        'status': response.statusCode,
        'body': response.body,
      });
      debugPrint('[SpotifyService] TOP_ARTISTS FAILED: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      await _log('TOP_ARTISTS_ERROR', {'error': e.toString()});
      debugPrint('[SpotifyService] TOP_ARTISTS ERROR: $e');
      return null;
    }
  }

  /// Get the user's top tracks
  static Future<List<Map<String, dynamic>>?> getTopTracks({
    int limit = 20,
    String timeRange = 'medium_term', // short_term, medium_term, long_term
  }) async {
    final headers = await _getHeaders();
    if (headers == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_apiBase/me/top/tracks?limit=$limit&time_range=$timeRange'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = (data['items'] as List).map((track) => {
          'id': track['id'],
          'name': track['name'],
          'artist': (track['artists'] as List).map((a) => a['name']).join(', '),
          'album': track['album']['name'],
          'popularity': track['popularity'],
          'uri': track['uri'],
        }).toList();

        await _log('TOP_TRACKS_SUCCESS', {
          'count': items.length,
          'time_range': timeRange,
          'tracks': items,
        });
        return List<Map<String, dynamic>>.from(items);
      }

      await _log('TOP_TRACKS_FAILED', {'status': response.statusCode});
      return null;
    } catch (e) {
      await _log('TOP_TRACKS_ERROR', {'error': e.toString()});
      return null;
    }
  }

  /// Get audio features for tracks (used for mood analysis)
  static Future<List<Map<String, dynamic>>?> getAudioFeatures(List<String> trackIds) async {
    final headers = await _getHeaders();
    if (headers == null) return null;

    try {
      final ids = trackIds.join(',');
      final response = await http.get(
        Uri.parse('$_apiBase/audio-features?ids=$ids'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final features = (data['audio_features'] as List)
            .where((f) => f != null)
            .map((f) => {
          'id': f['id'],
          'valence': f['valence'],
          'energy': f['energy'],
          'danceability': f['danceability'],
          'tempo': f['tempo'],
          'acousticness': f['acousticness'],
          'instrumentalness': f['instrumentalness'],
        }).toList();

        await _log('AUDIO_FEATURES_SUCCESS', {
          'count': features.length,
          'features': features,
        });
        return List<Map<String, dynamic>>.from(features);
      }

      await _log('AUDIO_FEATURES_FAILED', {'status': response.statusCode});
      return null;
    } catch (e) {
      await _log('AUDIO_FEATURES_ERROR', {'error': e.toString()});
      return null;
    }
  }

  /// Score and sort tracks from the user's own catalog by mood keywords.
  /// No external playlists or genres — 100% personal.
  static Future<Map<String, dynamic>> getFromUserCatalog({
    required String mood,
    int limit = 10,
  }) async {
    final moodKeywords = <String, List<String>>{
      'happy': [
        // EN
        'happy', 'joy', 'joyful', 'smile', 'smiling', 'laugh', 'laughter', 'sunshine',
        'sunny', 'summer', 'bright', 'shine', 'shiny', 'good', 'best', 'alright',
        'love', 'lovely', 'sweet', 'party', 'dance', 'dancing', 'celebrate', 'celebration',
        'fun', 'high', 'heaven', 'paradise', 'magic', 'free', 'freedom', 'alive',
        'fly', 'flying', 'wonderful', 'beautiful', 'lucky', 'yes', 'feel good',
        // TR
        'mutlu', 'mutluluk', 'neşe', 'neşeli', 'gülüm', 'gülme', 'gülüş',
        'aşk', 'sevgi', 'sevgili', 'sevdiğim', 'tatlı', 'güneş', 'yaz',
        'dans', 'parti', 'kutlama', 'özgür', 'özgürlük', 'hayat', 'iyi', 'güzel',
        'harika', 'şans', 'yıldız', 'uçmak',
      ],
      'sad': [
        // EN
        'sad', 'sadness', 'cry', 'crying', 'tear', 'tears', 'alone', 'lonely',
        'lonesome', 'broken', 'break', 'breaking', 'hurt', 'hurts', 'pain', 'painful',
        'miss', 'missing', 'lost', 'lose', 'gone', 'goodbye', 'bye', 'leave', 'leaving',
        'apart', 'apartment', 'without', 'empty', 'numb', 'cold', 'cry', 'blue',
        'sorry', 'regret', 'mistake', 'fall', 'falling', 'down', 'die', 'dying', 'death',
        'heart', 'heartbreak', 'silence', 'silent', 'fade',
        // TR
        'hüzün', 'hüzünlü', 'üzgün', 'üzüntü', 'üzül', 'yalnız', 'yalnızlık',
        'kırık', 'kırıl', 'ağla', 'ağlıyor', 'ağlat', 'gözyaşı', 'gözya',
        'veda', 'gitti', 'gitme', 'bırak', 'bıraktı', 'özle', 'özledim', 'özlem',
        'kayıp', 'kayb', 'acı', 'acılı', 'dert', 'keder', 'boş', 'soğuk',
        'ölmek', 'ölüm', 'gönül', 'kalp', 'yıkıl', 'unutul', 'pişman',
      ],
      'melancholy': [
        // EN
        'melancholy', 'melancholic', 'nostalgia', 'nostalgic', 'remember', 'memory',
        'memories', 'dream', 'dreaming', 'rain', 'rainy', 'autumn', 'fall', 'shadow',
        'fade', 'faded', 'slow', 'empty', 'alone', 'gone', 'yesterday', 'forever',
        'nowhere', 'quiet', 'still', 'calm', 'midnight', 'night', 'moon', 'stars',
        // TR
        'melankoli', 'melankolik', 'hüzün', 'hüzünlü', 'nostalji', 'hatır', 'anı',
        'rüya', 'rüyalar', 'yağmur', 'yağmurlu', 'sonbahar', 'gölge',
        'solgun', 'unut', 'yavaş', 'boş', 'yalnız', 'sessiz', 'gece', 'ay', 'yıldız',
      ],
      'angry': [
        // EN
        'angry', 'anger', 'rage', 'fury', 'furious', 'mad', 'hate', 'fight',
        'fighting', 'war', 'battle', 'break', 'breaking', 'fire', 'burn', 'burning',
        'kill', 'killer', 'blood', 'bloody', 'scream', 'screaming', 'rebel',
        'revenge', 'riot', 'noise', 'loud', 'hard', 'heavy', 'metal', 'rock',
        // TR
        'öfke', 'öfkeli', 'kızgın', 'nefret', 'kavga', 'savaş', 'kırıl',
        'yak', 'yan', 'ateş', 'kan', 'çığlık', 'isyan', 'intikam', 'gürültü',
        'sert', 'ağır', 'kara',
      ],
      'calm': [
        // EN
        'calm', 'peace', 'peaceful', 'quiet', 'silent', 'silence', 'still',
        'slow', 'soft', 'softly', 'sleep', 'sleeping', 'sleepy', 'dream', 'rest',
        'breathe', 'breathing', 'breath', 'lullaby', 'whisper', 'gentle', 'easy',
        'light', 'ocean', 'sea', 'water', 'river', 'sky', 'cloud', 'wind',
        'meditation', 'zen', 'relax', 'relaxing', 'chill',
        // TR
        'sakin', 'sakinlik', 'huzur', 'huzurlu', 'sessiz', 'sessizlik',
        'yavaş', 'yumuşak', 'uyku', 'uyu', 'rüya', 'dinlen', 'nefes',
        'ninni', 'fısıl', 'hafif', 'deniz', 'su', 'gökyüzü', 'bulut', 'rüzgar',
      ],
      'excited': [
        // EN
        'party', 'dance', 'dancing', 'hype', 'energy', 'energetic', 'fire',
        'wild', 'crazy', 'alive', 'night', 'nightlife', 'club', 'bass',
        'loud', 'pump', 'jump', 'move', 'moving', 'shake', 'boom', 'bang',
        'rush', 'fast', 'speed', 'high', 'rocket', 'fly', 'flying', 'electric',
        // TR
        'parti', 'dans', 'enerji', 'enerjik', 'ateş', 'çılgın', 'hayat',
        'gece', 'kulüp', 'zıpla', 'zıplat', 'hızlı', 'uç', 'elektrik',
      ],
      'neutral': [],
      'fearful': [
        // EN
        'fear', 'afraid', 'scared', 'scary', 'dark', 'darkness', 'shadow',
        'nightmare', 'haunt', 'haunted', 'ghost', 'devil', 'evil', 'monster',
        'alone', 'hide', 'run', 'running', 'chase', 'panic', 'horror',
        // TR
        'korku', 'korkmak', 'korkunç', 'karanlık', 'gölge', 'kabus',
        'hayalet', 'şeytan', 'canavar', 'saklan', 'kaç', 'panik',
      ],
      'surprised': [
        'wonder', 'wonderful', 'amazing', 'new', 'discover', 'surprise',
        'magic', 'magical', 'unexpected', 'suddenly', 'wow',
        'şaşır', 'harika', 'sihir', 'sihirli', 'ansızın', 'birden',
      ],
      'disgusted': [
        'hate', 'sick', 'ugly', 'dirty', 'rotten', 'disgust', 'nasty',
        'filth', 'garbage', 'trash', 'raw',
        'nefret', 'iğren', 'pis', 'kirli', 'çürük',
      ],
    };

    final diag = <String, dynamic>{'mood': mood};
    final keywords = moodKeywords[mood.toLowerCase()] ?? const <String>[];

    // 1. User's top tracks (multiple time ranges for variety)
    final pool = <Map<String, dynamic>>[];
    final seen = <String>{};

    Future<void> addTracks(List<Map<String, dynamic>>? tracks) async {
      if (tracks == null) return;
      for (final t in tracks) {
        final id = t['id']?.toString();
        if (id != null && seen.add(id)) pool.add(t);
      }
    }

    await addTracks(await getTopTracks(limit: 50, timeRange: 'short_term'));
    await addTracks(await getTopTracks(limit: 50, timeRange: 'medium_term'));
    await addTracks(await getTopTracks(limit: 50, timeRange: 'long_term'));
    diag['top_tracks_pool'] = pool.length;

    // Note: /v1/artists/{id}/top-tracks now returns 403 for new apps.
    // The user's 100+ top tracks are already a sufficient pool.

    // 3. Mood score: word-boundary regex (prevents "break" matching "breakfast")
    final patterns = keywords
        .map((kw) => RegExp(r'\b' + RegExp.escape(kw) + r'\b',
            caseSensitive: false, unicode: true))
        .toList();

    int score(Map<String, dynamic> t) {
      if (patterns.isEmpty) return 0;
      final name = (t['name'] ?? '').toString();
      final album = (t['album'] ?? '').toString();
      final artist = (t['artist'] ?? '').toString();
      var s = 0;
      for (final p in patterns) {
        if (p.hasMatch(name)) s += 10;
        if (p.hasMatch(album)) s += 3;
        if (p.hasMatch(artist)) s += 5;
      }
      return s;
    }

    final scored = pool.map((t) => {...t, '_score': score(t)}).toList()
      ..sort((a, b) => (b['_score'] as int).compareTo(a['_score'] as int));

    final matched = scored.where((t) => (t['_score'] as int) > 0).toList();
    diag['matched_count'] = matched.length;

    // 4. Compose result: mood-matched first, then fill from pool (personal but mood-less)
    final out = <Map<String, dynamic>>[];
    for (final t in matched) {
      if (out.length >= limit) break;
      out.add({
        'id': t['id'],
        'name': t['name'],
        'artist': t['artist'],
        'album': t['album'],
        'preview_url': t['preview_url'],
        'uri': t['uri'],
        'external_url': t['external_url'],
        'source': 'catalog_mood_matched',
        'score': t['_score'],
      });
    }
    // Fill remaining slots from the pool when matched results aren't enough
    for (final t in scored) {
      if (out.length >= limit) break;
      if ((t['_score'] as int) > 0) continue; // zaten eklendi
      out.add({
        'id': t['id'],
        'name': t['name'],
        'artist': t['artist'],
        'album': t['album'],
        'preview_url': t['preview_url'],
        'uri': t['uri'],
        'external_url': t['external_url'],
        'source': 'catalog_fill',
        'score': 0,
      });
    }

    await _log('USER_CATALOG', {
      ...diag,
      'final_count': out.length,
    });

    return {
      'success': out.isNotEmpty,
      'tracks': out,
      'diagnostics': diag,
    };
  }

  /// Get an artist's top tracks
  static Future<List<Map<String, dynamic>>?> getArtistTopTracks(String artistId) async {
    final headers = await _getHeaders();
    if (headers == null) return null;

    try {
      final url = '$_apiBase/artists/$artistId/top-tracks?market=TR';
      debugPrint('[SpotifyService] Fetching artist top tracks: $url');
      final response = await http.get(Uri.parse(url), headers: headers);

      debugPrint('[SpotifyService] Artist top tracks response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tracks = (data['tracks'] as List)
            .map((track) => _parseTrack(track, 'personalized'))
            .toList();
        debugPrint('[SpotifyService] Got ${tracks.length} tracks for artist $artistId');
        return tracks;
      }
      debugPrint('[SpotifyService] Artist top tracks FAILED: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      debugPrint('[SpotifyService] Artist top tracks ERROR: $e');
      return null;
    }
  }

  static Map<String, dynamic> _parseTrack(dynamic track, String source) {
    return {
      'id': track['id'],
      'name': track['name'],
      'artist': (track['artists'] as List).map((a) => a['name']).join(', '),
      'album': track['album']['name'],
      'preview_url': track['preview_url'],
      'uri': track['uri'],
      'external_url': track['external_urls']?['spotify'],
      'source': source,
    };
  }

  // ──────────────────────────────────────────────
  //  MAIN PIPELINE: Mood → Recommendations
  // ──────────────────────────────────────────────

  /// Full pipeline: take mood → fetch user catalog → score → log
  /// [mood] either placeholder or real detection
  /// [confidence] detection score (0.0-1.0)
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

    await _log('PIPELINE_START', {
      'mood': mood,
      'confidence': confidence,
      'authenticated': isAuthenticated,
    });

    if (!isAuthenticated) {
      result['error'] = 'Spotify not authenticated';
      result['recommendations'] = _getMockRecommendations(mood);
      result['source'] = 'mock_data';

      await _log('PIPELINE_MOCK_MODE', result);
      return result;
    }

    // Fetch top artist names for diagnostics only
    final topArtists = await getTopArtists(limit: 10, timeRange: 'medium_term');
    final userArtistNames = <String>[];
    if (topArtists != null) {
      for (final a in topArtists) {
        final name = a['name'] as String?;
        if (name != null) userArtistNames.add(name);
      }
    }
    result['user_artists'] = userArtistNames;

    // Main strategy: user's own catalog + mood-keyword scoring
    final catalogResult = await getFromUserCatalog(mood: mood, limit: limit);
    result['catalog_attempt'] = catalogResult;

    final recommendations = (catalogResult['tracks'] as List?)
        ?.cast<Map<String, dynamic>>();

    result['recommendations'] = recommendations;
    result['recommendations_count'] = recommendations?.length ?? 0;
    result['source'] = 'spotify_api';
    result['recommendations_strategy'] = 'user_catalog';

    await _log('PIPELINE_COMPLETE', result);
    return result;
  }

  // ──────────────────────────────────────────────
  //  DEV/TEST: Mock data (when Spotify isn't connected)
  // ──────────────────────────────────────────────

  static List<Map<String, dynamic>> _getMockRecommendations(String mood) {
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

    return mockData[mood.toLowerCase()] ?? mockData['neutral'] ?? [
      {'name': 'Bohemian Rhapsody', 'artist': 'Queen', 'id': 'mock_default_1'},
      {'name': 'Hotel California', 'artist': 'Eagles', 'id': 'mock_default_2'},
      {'name': 'Stairway to Heaven', 'artist': 'Led Zeppelin', 'id': 'mock_default_3'},
    ];
  }

  // ──────────────────────────────────────────────
  //  DEV TEST RUNNER
  // ──────────────────────────────────────────────

  /// Dev test: run the pipeline with placeholder moods
  static Future<void> runDevTest() async {
    await _log('DEV_TEST_START', {
      'message': 'Starting Spotify mood pipeline test',
      'has_client_id': _clientId.isNotEmpty,
      'has_client_secret': _clientSecret.isNotEmpty,
    });

    // Placeholder duygular ile test
    final testMoods = ['happy', 'sad', 'melancholy', 'angry', 'calm', 'excited'];

    for (final mood in testMoods) {
      final confidence = 0.80 + Random().nextDouble() * 0.20; // 0.80 - 1.00
      final result = await getMoodBasedRecommendations(
        mood: mood,
        confidence: double.parse(confidence.toStringAsFixed(2)),
      );

      debugPrint('[SpotifyDev] Mood: $mood → ${result['recommendations_count'] ?? 'mock'} tracks (source: ${result['source']})');
    }

    await _log('DEV_TEST_COMPLETE', {
      'message': 'All mood tests completed. Check this log file for details.',
      'moods_tested': testMoods,
    });
  }

  /// Clear the log file
  static Future<void> clearLog() async {
    final logFile = await _getLogFile();
    if (await logFile.exists()) {
      await logFile.writeAsString('');
      debugPrint('[SpotifyService] Log file cleared');
    }
  }

  /// Clear tokens (logout)
  static Future<void> disconnect() async {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('spotify_access_token');
    await prefs.remove('spotify_refresh_token');
    await prefs.remove('spotify_token_expiry');

    await _log('DISCONNECTED', {'message': 'Spotify tokens cleared'});
  }
}
