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
}
