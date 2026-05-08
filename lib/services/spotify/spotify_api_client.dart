import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'spotify_auth.dart';
import 'spotify_logger.dart';

/// Thin wrapper around the raw Spotify Web API endpoints the app uses.
/// Each method returns plain maps/lists to keep callers independent of
/// Spotify's JSON shape.
class SpotifyApiClient {
  static const String _apiBase = 'https://api.spotify.com/v1';

  static Future<List<Map<String, dynamic>>?> getRecentlyPlayed({
    int limit = 20,
  }) async {
    final headers = await SpotifyAuth.getHeaders();
    if (headers == null) {
      await SpotifyLogger.log('RECENTLY_PLAYED', {'error': 'Not authenticated'});
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
        await SpotifyLogger.log(
            'RECENTLY_PLAYED_SUCCESS', {'count': items.length});
        return List<Map<String, dynamic>>.from(items);
      }

      await SpotifyLogger.log('RECENTLY_PLAYED_FAILED', {
        'status': response.statusCode,
        'body': response.body,
      });
      return null;
    } catch (e) {
      await SpotifyLogger.log('RECENTLY_PLAYED_ERROR', {'error': e.toString()});
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> getTopArtists({
    int limit = 10,
    String timeRange = 'medium_term',
  }) async {
    final headers = await SpotifyAuth.getHeaders();
    if (headers == null) return null;

    try {
      final response = await http.get(
        Uri.parse(
            '$_apiBase/me/top/artists?limit=$limit&time_range=$timeRange'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = (data['items'] as List)
            .map((artist) => {
                  'id': artist['id'],
                  'name': artist['name'],
                  'genres':
                      (artist['genres'] as List?)?.cast<String>() ?? <String>[],
                  'popularity': artist['popularity'],
                })
            .toList();
        await SpotifyLogger.log('TOP_ARTISTS_SUCCESS', {
          'count': items.length,
          'time_range': timeRange,
        });
        return List<Map<String, dynamic>>.from(items);
      }

      await SpotifyLogger.log('TOP_ARTISTS_FAILED', {
        'status': response.statusCode,
        'body': response.body,
      });
      debugPrint(
          '[SpotifyApi] TOP_ARTISTS FAILED: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      await SpotifyLogger.log('TOP_ARTISTS_ERROR', {'error': e.toString()});
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> getTopTracks({
    int limit = 20,
    String timeRange = 'medium_term',
  }) async {
    final headers = await SpotifyAuth.getHeaders();
    if (headers == null) return null;

    try {
      final response = await http.get(
        Uri.parse(
            '$_apiBase/me/top/tracks?limit=$limit&time_range=$timeRange'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = (data['items'] as List)
            .map((track) => {
                  'id': track['id'],
                  'name': track['name'],
                  'artist':
                      (track['artists'] as List).map((a) => a['name']).join(', '),
                  'album': track['album']['name'],
                  'popularity': track['popularity'],
                  'uri': track['uri'],
                })
            .toList();
        await SpotifyLogger.log('TOP_TRACKS_SUCCESS', {
          'count': items.length,
          'time_range': timeRange,
        });
        return List<Map<String, dynamic>>.from(items);
      }

      await SpotifyLogger.log(
          'TOP_TRACKS_FAILED', {'status': response.statusCode});
      return null;
    } catch (e) {
      await SpotifyLogger.log('TOP_TRACKS_ERROR', {'error': e.toString()});
      return null;
    }
  }

  /// NOTE: Spotify deprecated /v1/artists/{id}/top-tracks for apps created
  /// after Nov 2024 and now returns 403. Left here for completeness.
  static Future<List<Map<String, dynamic>>?> getArtistTopTracks(
      String artistId) async {
    final headers = await SpotifyAuth.getHeaders();
    if (headers == null) return null;

    try {
      final url = '$_apiBase/artists/$artistId/top-tracks?market=TR';
      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['tracks'] as List)
            .map<Map<String, dynamic>>(
                (t) => parseTrack(t, 'personalized'))
            .toList();
      }
      debugPrint(
          '[SpotifyApi] Artist top tracks FAILED: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[SpotifyApi] Artist top tracks ERROR: $e');
      return null;
    }
  }

  /// Search for a single track by title + artist. Returns the first hit as a
  /// parsed track map (with the provided [source] tag) or null if no match.
  /// Uses Spotify's `track:` and `artist:` field filters for precision.
  static Future<Map<String, dynamic>?> searchTrack({
    required String title,
    required String artist,
    String source = 'claude_search',
  }) async {
    final headers = await SpotifyAuth.getHeaders();
    if (headers == null) return null;

    final query = 'track:"$title" artist:"$artist"';
    final url = Uri.parse(
        '$_apiBase/search?q=${Uri.encodeQueryComponent(query)}&type=track&limit=1');

    try {
      final response = await http.get(url, headers: headers);
      if (response.statusCode != 200) {
        await SpotifyLogger.log('SEARCH_FAILED', {
          'status': response.statusCode,
          'query': query,
        });
        return null;
      }
      final data = jsonDecode(response.body);
      final items = (data['tracks']?['items'] as List?) ?? const [];
      if (items.isEmpty) return null;
      return parseTrack(items.first, source);
    } catch (e) {
      await SpotifyLogger.log('SEARCH_ERROR', {
        'error': e.toString(),
        'query': query,
      });
      return null;
    }
  }

  /// Parse a raw Spotify track JSON into the flat map shape the app uses.
  static Map<String, dynamic> parseTrack(dynamic track, String source) {
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

  static Future<List<Map<String, dynamic>>?> getDevices() async {
    final headers = await SpotifyAuth.getHeaders();
    if (headers == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_apiBase/me/player/devices'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = ((data['devices'] as List?) ?? const [])
            .map((d) => {
                  'id': d['id'],
                  'name': d['name'],
                  'is_active': d['is_active'],
                  'type': d['type'],
                  'volume_percent': d['volume_percent'],
                })
            .toList();
        await SpotifyLogger.log('DEVICES_SUCCESS', {'count': items.length});
        return List<Map<String, dynamic>>.from(items);
      }
      await SpotifyLogger.log('DEVICES_FAILED', {
        'status': response.statusCode,
        'body': response.body,
      });
      return null;
    } catch (e) {
      await SpotifyLogger.log('DEVICES_ERROR', {'error': e.toString()});
      return null;
    }
  }

  static Future<Map<String, dynamic>?> findDeviceByName(String name) async {
    final devices = await getDevices();
    if (devices == null) return null;
    final target = name.toLowerCase();
    for (final d in devices) {
      if ((d['name'] ?? '').toString().toLowerCase() == target) return d;
    }
    return null;
  }

  /// First Spotify Connect device whose name starts with [prefix].
  /// The Pi self-derives `AkilliEv-<machineid6>` at boot so the mobile app
  /// only needs the shared prefix — no hardcoded device name on either side.
  static Future<Map<String, dynamic>?> findDeviceByPrefix(String prefix) async {
    final devices = await getDevices();
    if (devices == null) return null;
    final target = prefix.toLowerCase();
    for (final d in devices) {
      if ((d['name'] ?? '').toString().toLowerCase().startsWith(target)) return d;
    }
    return null;
  }

  static Future<bool> transferPlayback(String deviceId,
      {bool play = true}) async {
    final headers = await SpotifyAuth.getHeaders();
    if (headers == null) return false;

    try {
      final response = await http.put(
        Uri.parse('$_apiBase/me/player'),
        headers: headers,
        body: jsonEncode({'device_ids': [deviceId], 'play': play}),
      );
      if (response.statusCode == 204) {
        await SpotifyLogger.log('TRANSFER_SUCCESS', {'device_id': deviceId});
        return true;
      }
      await SpotifyLogger.log('TRANSFER_FAILED', {
        'status': response.statusCode,
        'body': response.body,
      });
      return false;
    } catch (e) {
      await SpotifyLogger.log('TRANSFER_ERROR', {'error': e.toString()});
      return false;
    }
  }

  static Future<bool> playTracks({
    required String deviceId,
    required List<String> uris,
    int? positionMs,
  }) async {
    final headers = await SpotifyAuth.getHeaders();
    if (headers == null) return false;

    final body = <String, dynamic>{'uris': uris};
    if (positionMs != null) body['position_ms'] = positionMs;

    try {
      final response = await http.put(
        Uri.parse('$_apiBase/me/player/play?device_id=$deviceId'),
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 204) {
        await SpotifyLogger.log('PLAY_SUCCESS', {
          'device_id': deviceId,
          'count': uris.length,
        });
        return true;
      }
      await SpotifyLogger.log('PLAY_FAILED', {
        'status': response.statusCode,
        'body': response.body,
      });
      return false;
    } catch (e) {
      await SpotifyLogger.log('PLAY_ERROR', {'error': e.toString()});
      return false;
    }
  }

  /// PUT /me/player/pause?device_id=X
  static Future<bool> pausePlayback(String deviceId) async =>
      _simpleControl('PUT', '/me/player/pause', deviceId, 'PAUSE');

  /// PUT /me/player/play?device_id=X with no body — resumes current track.
  static Future<bool> resumePlayback(String deviceId) async =>
      _simpleControl('PUT', '/me/player/play', deviceId, 'RESUME');

  /// POST /me/player/next?device_id=X
  static Future<bool> nextTrack(String deviceId) async =>
      _simpleControl('POST', '/me/player/next', deviceId, 'NEXT');

  /// POST /me/player/previous?device_id=X
  static Future<bool> previousTrack(String deviceId) async =>
      _simpleControl('POST', '/me/player/previous', deviceId, 'PREV');

  static Future<bool> _simpleControl(
      String method, String path, String deviceId, String tag) async {
    final headers = await SpotifyAuth.getHeaders();
    if (headers == null) return false;
    final url = Uri.parse('$_apiBase$path?device_id=$deviceId');
    try {
      final response = method == 'PUT'
          ? await http.put(url, headers: headers)
          : await http.post(url, headers: headers);
      // 2xx all mean the command was accepted. Spotify mostly returns 204
      // but also 200 / 202 in some cases (e.g. resume on empty queue).
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await SpotifyLogger.log('${tag}_SUCCESS',
            {'device_id': deviceId, 'status': response.statusCode});
        return true;
      }
      await SpotifyLogger.log('${tag}_FAILED', {
        'status': response.statusCode,
        'body': response.body,
      });
      return false;
    } catch (e) {
      await SpotifyLogger.log('${tag}_ERROR', {'error': e.toString()});
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getCurrentlyPlaying() async {
    final headers = await SpotifyAuth.getHeaders();
    if (headers == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_apiBase/me/player/currently-playing'),
        headers: headers,
      );
      if (response.statusCode == 204) return null;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final item = data['item'];
        if (item == null) return null;
        final artists = (item['artists'] as List?) ?? const [];
        final dev = data['device'];
        return {
          'is_playing': data['is_playing'],
          'track': {
            'name': item['name'],
            'artist': artists.map((a) => a['name']).join(', '),
            'album': item['album']?['name'],
            'uri': item['uri'],
            'id': item['id'],
          },
          // Device info from the playback session — useful as a
          // fallback when /me/player/devices doesn't surface the active
          // speaker (e.g. raspotify just woke up and isn't in the
          // device list yet, but is already streaming).
          if (dev is Map<String, dynamic>) 'device': {
            'id': dev['id'],
            'name': dev['name'],
            'type': dev['type'],
          },
          'progress_ms': data['progress_ms'],
          'duration_ms': item['duration_ms'],
        };
      }
      return null;
    } catch (e) {
      await SpotifyLogger.log(
          'CURRENTLY_PLAYING_ERROR', {'error': e.toString()});
      return null;
    }
  }
}
