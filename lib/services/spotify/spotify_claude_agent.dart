import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'spotify_api_client.dart';
import 'spotify_logger.dart';

/// Uses Claude Haiku as a music curator: given the user's listening profile
/// and a mood, Claude proposes real-world song candidates (title + artist);
/// we then resolve each to a real Spotify track via the Search endpoint.
///
/// This routes around Spotify's deprecated /recommendations and
/// /artists/{id}/top-tracks endpoints while still grounding every returned
/// track in the Spotify catalog.
class SpotifyClaudeAgent {
  static const String _model = 'claude-haiku-4-5-20251001';
  static const String _apiUrl = 'https://api.anthropic.com/v1/messages';
  static const Duration _cacheTtl = Duration(minutes: 10);
  static const int _candidateCount = 20;

  static String get _apiKey => dotenv.env['CLAUDE_API_KEY'] ?? '';
  static bool get isConfigured => _apiKey.isNotEmpty;

  static final Map<String, _CacheEntry> _cache = {};

  /// Returns { success, tracks, diagnostics } matching SpotifyMoodCatalog.
  /// Returns success=false on any failure so callers can fall back.
  static Future<Map<String, dynamic>> recommend({
    required String mood,
    int limit = 10,
  }) async {
    final diag = <String, dynamic>{'mood': mood, 'agent': 'claude_haiku'};

    if (!isConfigured) {
      diag['error'] = 'claude_api_key_missing';
      return {'success': false, 'tracks': <Map<String, dynamic>>[], 'diagnostics': diag};
    }

    final cacheKey = mood.toLowerCase();
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      diag['cache_hit'] = true;
      return {
        'success': cached.tracks.isNotEmpty,
        'tracks': cached.tracks.take(limit).toList(),
        'diagnostics': diag,
      };
    }

    // 1. Build user listening profile from working Spotify endpoints.
    final profile = await _buildProfile();
    diag['profile_artists'] = profile.topArtists.length;
    diag['profile_tracks'] = profile.sampleTracks.length;
    diag['profile_genres'] = profile.genres.length;

    if (profile.topArtists.isEmpty && profile.sampleTracks.isEmpty) {
      diag['error'] = 'empty_profile';
      return {'success': false, 'tracks': <Map<String, dynamic>>[], 'diagnostics': diag};
    }

    // 2. Ask Claude for candidate songs grounded in that profile.
    final candidates = await _askClaude(mood: mood, profile: profile);
    diag['claude_candidates'] = candidates.length;
    if (candidates.isEmpty) {
      diag['error'] = 'claude_returned_no_candidates';
      return {'success': false, 'tracks': <Map<String, dynamic>>[], 'diagnostics': diag};
    }

    // 3. Resolve each candidate to a real Spotify track ID via search,
    //    post-filtered for artist diversity + no duplicates of known titles.
    final resolved = await _resolveCandidates(
      candidates,
      limit: limit,
      knownTitles: profile.knownTitles.map((t) => t.toLowerCase()).toSet(),
    );
    diag['resolved_tracks'] = resolved.length;

    _cache[cacheKey] = _CacheEntry(resolved);

    await SpotifyLogger.log('CLAUDE_AGENT', {
      ...diag,
      'final_count': resolved.length,
    });

    return {
      'success': resolved.isNotEmpty,
      'tracks': resolved,
      'diagnostics': diag,
    };
  }

  static Future<_ListenerProfile> _buildProfile() async {
    final results = await Future.wait([
      SpotifyApiClient.getTopArtists(limit: 10, timeRange: 'short_term'),
      SpotifyApiClient.getTopArtists(limit: 10, timeRange: 'medium_term'),
      SpotifyApiClient.getTopTracks(limit: 15, timeRange: 'medium_term'),
      SpotifyApiClient.getRecentlyPlayed(limit: 10),
    ]);

    final shortArtists = (results[0] ?? const []).cast<Map<String, dynamic>>();
    final mediumArtists = (results[1] ?? const []).cast<Map<String, dynamic>>();
    final tracks = (results[2] ?? const []).cast<Map<String, dynamic>>();
    final recent = (results[3] ?? const []).cast<Map<String, dynamic>>();

    // Merge top artists: short_term (current taste) weighted first.
    final topArtistNames = <String>[];
    final seenArtists = <String>{};
    for (final a in [...shortArtists, ...mediumArtists]) {
      final name = a['name']?.toString() ?? '';
      if (name.isNotEmpty && seenArtists.add(name.toLowerCase())) {
        topArtistNames.add(name);
      }
    }

    final genres = <String>{};
    for (final a in [...shortArtists, ...mediumArtists]) {
      for (final g in (a['genres'] as List?) ?? const []) {
        genres.add(g.toString());
      }
    }

    // Titles-only set so Claude can avoid re-suggesting what the user has already heard.
    final knownTitles = <String>{};
    for (final t in [...tracks, ...recent]) {
      final name = t['name']?.toString().trim();
      if (name != null && name.isNotEmpty) knownTitles.add(name);
    }

    return _ListenerProfile(
      topArtists: topArtistNames,
      genres: genres.take(12).toList(),
      sampleTracks: tracks
          .map((t) => '${t['name']} — ${t['artist']}')
          .where((s) => s.trim().isNotEmpty)
          .toList(),
      recentTracks: recent
          .map((t) => '${t['name']} — ${t['artist']}')
          .where((s) => s.trim().isNotEmpty)
          .toList(),
      knownTitles: knownTitles.toList(),
    );
  }

  static Future<List<_Candidate>> _askClaude({
    required String mood,
    required _ListenerProfile profile,
  }) async {
    const system = '''You are a music curator for ONE specific listener. Your job: produce a personal list that feels hand-picked — NOT a generic mood playlist that anyone could get from a Spotify editorial.

COMPOSITION (strict targets for a list of N tracks):
1. About 60% of the list MUST be songs by artists listed in `top_artists` — pick OTHER tracks from those artists' catalogs that match the mood. These artists are the listener's core taste; give them back their own artists with songs they may not have discovered yet.
2. About 40% should be by artists the listener does NOT already listen to, but who are a genuinely tight taste match. Micro-adjacent, not chart-adjacent. Think: same scene, same producers, same era, same subculture. NOT generic pop radio.
3. Maximum 2 tracks per artist. Variety matters.

HARD BANS:
- Do NOT suggest any song title that appears in `sample_liked_tracks` or `recent_tracks`. The listener already has those.
- Do NOT fall back to textbook mood anthems ("Happy" by Pharrell, "Walking on Sunshine", "Firework", "Roar", "Don't Stop Believin'", "Someone Like You", "Fix You", "Killing in the Name", etc.) UNLESS the artist literally appears in `top_artists`.
- Do NOT pad the list with household-name pop stars (Dua Lipa, Ed Sheeran, Taylor Swift, Bruno Mars, Ariana Grande, Katy Perry, P!nk, Coldplay, etc.) unless they are in `top_artists` or demonstrably core to the listener's profile.

QUALITY:
- ONLY real songs that exist on Spotify. Do NOT invent titles or artists.
- Prefer the artist's official studio version.
- The `reason` field MUST cite a concrete signal from THIS listener's profile — which top artist, which sample track, which genre. Bad reason: "upbeat dance pop". Good reason: "Dove Cameron — matches the Descendants-era energy in sample".

OUTPUT: JSON only, no prose, no code fences.
Schema: {"tracks":[{"title":"<song>","artist":"<primary artist>","reason":"<=14 words, cite profile>"}]}
Return exactly N tracks.''';

    final userPayload = {
      'target_mood': mood,
      'count': _candidateCount,
      'top_artists': profile.topArtists,
      'genres': profile.genres,
      'sample_liked_tracks': profile.sampleTracks,
      'recent_tracks': profile.recentTracks,
      'already_known_titles_do_not_repeat': profile.knownTitles,
    };

    final userMessage =
        'Listener profile and request:\n```json\n${const JsonEncoder.withIndent('  ').convert(userPayload)}\n```\n\nReturn the JSON object now.';

    final body = jsonEncode({
      'model': _model,
      'max_tokens': 1500,
      'system': system,
      'messages': [
        {'role': 'user', 'content': userMessage},
      ],
    });

    await _writeIoLog(
      mood: mood,
      system: system,
      userMessage: userMessage,
      payload: userPayload,
      response: null,
      status: null,
      error: null,
      phase: 'request',
    );

    debugPrint('═══ CLAUDE AGENT → REQUEST (mood=$mood) ═══');
    debugPrint('payload: ${const JsonEncoder.withIndent('  ').convert(userPayload)}');

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: body,
      );

      if (response.statusCode != 200) {
        debugPrint('[ClaudeAgent] API ${response.statusCode}: ${response.body}');
        await SpotifyLogger.log('CLAUDE_API_FAILED', {
          'status': response.statusCode,
          'body': response.body,
        });
        await _writeIoLog(
          mood: mood,
          system: system,
          userMessage: userMessage,
          payload: userPayload,
          response: response.body,
          status: response.statusCode,
          error: null,
          phase: 'response_error',
        );
        return const [];
      }

      final data = jsonDecode(response.body);
      final content = (data['content'] as List?) ?? const [];
      final text = content
          .where((b) => b['type'] == 'text')
          .map((b) => b['text']?.toString() ?? '')
          .join('\n');

      await _writeIoLog(
        mood: mood,
        system: system,
        userMessage: userMessage,
        payload: userPayload,
        response: text,
        status: response.statusCode,
        error: null,
        phase: 'response',
      );

      debugPrint('═══ CLAUDE AGENT ← RESPONSE (status=${response.statusCode}) ═══');
      debugPrint(text);
      debugPrint('═══ CLAUDE AGENT RESPONSE END ═══');

      return _parseCandidates(text);
    } catch (e) {
      debugPrint('[ClaudeAgent] request error: $e');
      await SpotifyLogger.log('CLAUDE_API_ERROR', {'error': e.toString()});
      await _writeIoLog(
        mood: mood,
        system: system,
        userMessage: userMessage,
        payload: userPayload,
        response: null,
        status: null,
        error: e.toString(),
        phase: 'exception',
      );
      return const [];
    }
  }

  /// Append a human-readable record of what went to Claude and what came back
  /// to `<docs>/logs/claude_agent_io.txt`. Separate from the JSON logger so
  /// the raw prompt/response are easy to eyeball.
  static Future<void> _writeIoLog({
    required String mood,
    required String system,
    required String userMessage,
    required Map<String, dynamic> payload,
    required String? response,
    required int? status,
    required String? error,
    required String phase,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!logDir.existsSync()) logDir.createSync(recursive: true);
      final file = File('${logDir.path}/claude_agent_io.txt');

      final ts = DateTime.now().toIso8601String();
      final buf = StringBuffer()
        ..writeln('================================================================')
        ..writeln('[$ts] phase=$phase mood=$mood model=$_model')
        ..writeln('================================================================');

      if (phase == 'request') {
        buf
          ..writeln('--- SYSTEM PROMPT ---')
          ..writeln(system)
          ..writeln('--- USER MESSAGE ---')
          ..writeln(userMessage)
          ..writeln('--- RAW PAYLOAD (JSON) ---')
          ..writeln(const JsonEncoder.withIndent('  ').convert(payload));
      } else {
        if (status != null) buf.writeln('HTTP status: $status');
        if (error != null) buf.writeln('Error: $error');
        if (response != null) {
          buf
            ..writeln('--- CLAUDE RESPONSE TEXT ---')
            ..writeln(response);
        }
      }
      buf.writeln();

      await file.writeAsString(buf.toString(), mode: FileMode.append);
      if (phase == 'request') {
        debugPrint('[ClaudeAgent] IO log: ${file.path}');
      }
    } catch (e) {
      debugPrint('[ClaudeAgent] IO log write failed: $e');
    }
  }

  static List<_Candidate> _parseCandidates(String text) {
    // Claude may wrap JSON in prose or code fences — extract the first object.
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return const [];
    try {
      final obj = jsonDecode(text.substring(start, end + 1));
      final list = (obj['tracks'] as List?) ?? const [];
      return list
          .map((e) {
            if (e is! Map) return null;
            final title = e['title']?.toString().trim() ?? '';
            final artist = e['artist']?.toString().trim() ?? '';
            if (title.isEmpty || artist.isEmpty) return null;
            return _Candidate(
              title: title,
              artist: artist,
              reason: e['reason']?.toString() ?? '',
            );
          })
          .whereType<_Candidate>()
          .toList();
    } catch (e) {
      debugPrint('[ClaudeAgent] JSON parse failed: $e');
      return const [];
    }
  }

  static Future<List<Map<String, dynamic>>> _resolveCandidates(
    List<_Candidate> candidates, {
    required int limit,
    required Set<String> knownTitles,
  }) async {
    // Resolve in small parallel batches to stay polite to Spotify's rate limit.
    // Post-filter: skip tracks the user already knows + cap each artist at 2.
    const batchSize = 5;
    const perArtistCap = 2;
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    final artistCounts = <String, int>{};
    var misses = 0;
    var skippedKnown = 0;
    var skippedArtistCap = 0;

    for (var i = 0; i < candidates.length && out.length < limit; i += batchSize) {
      final slice = candidates.skip(i).take(batchSize).toList();
      final results = await Future.wait(slice.map((c) => SpotifyApiClient.searchTrack(
            title: c.title,
            artist: c.artist,
            source: 'claude_agent',
          )));

      for (var j = 0; j < results.length; j++) {
        final track = results[j];
        final cand = slice[j];
        if (track == null) {
          misses++;
          debugPrint('[ClaudeAgent] ✗ search miss: "${cand.title}" — ${cand.artist}');
          continue;
        }
        final id = track['id']?.toString();
        if (id == null || !seen.add(id)) continue;

        final title = track['name']?.toString() ?? '';
        if (knownTitles.contains(title.toLowerCase())) {
          skippedKnown++;
          debugPrint('[ClaudeAgent] ⊘ skip known: "$title"');
          continue;
        }

        // Primary artist for diversity cap = first listed.
        final primaryArtist =
            (track['artist']?.toString() ?? '').split(',').first.trim().toLowerCase();
        final count = artistCounts[primaryArtist] ?? 0;
        if (count >= perArtistCap) {
          skippedArtistCap++;
          debugPrint('[ClaudeAgent] ⊘ artist cap: "$title" — $primaryArtist');
          continue;
        }
        artistCounts[primaryArtist] = count + 1;

        debugPrint('[ClaudeAgent] ✓ resolved: "$title" — ${track['artist']} (${track['id']})');
        out.add({
          ...track,
          'reason': cand.reason,
        });
        if (out.length >= limit) break;
      }
    }

    debugPrint(
        '[ClaudeAgent] resolve complete: ${out.length} hits, $misses miss, $skippedKnown known-skip, $skippedArtistCap cap-skip of ${candidates.length} candidates');
    return out;
  }

  @visibleForTesting
  static void clearCache() => _cache.clear();
}

class _ListenerProfile {
  final List<String> topArtists;
  final List<String> genres;
  final List<String> sampleTracks;
  final List<String> recentTracks;
  final List<String> knownTitles;

  _ListenerProfile({
    required this.topArtists,
    required this.genres,
    required this.sampleTracks,
    required this.recentTracks,
    required this.knownTitles,
  });
}

class _Candidate {
  final String title;
  final String artist;
  final String reason;

  _Candidate({required this.title, required this.artist, required this.reason});
}

class _CacheEntry {
  final List<Map<String, dynamic>> tracks;
  final DateTime createdAt;

  _CacheEntry(this.tracks) : createdAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt) > SpotifyClaudeAgent._cacheTtl;
}
