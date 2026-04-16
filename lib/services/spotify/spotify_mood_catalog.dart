import 'spotify_api_client.dart';
import 'spotify_logger.dart';

/// Mood-to-song matching that ONLY uses the user's own top tracks.
///
/// Spotify deprecated /v1/recommendations and /v1/audio-features for apps
/// created after Nov 2024. This module routes around that by pulling the
/// user's top tracks across multiple time ranges and scoring each track's
/// name/album/artist against mood-specific keyword lists (EN + TR).
class SpotifyMoodCatalog {
  static const Map<String, List<String>> _moodKeywords = {
    'happy': [
      // EN
      'happy', 'joy', 'joyful', 'smile', 'smiling', 'laugh', 'laughter',
      'sunshine', 'sunny', 'summer', 'bright', 'shine', 'shiny', 'good',
      'best', 'alright', 'love', 'lovely', 'sweet', 'party', 'dance',
      'dancing', 'celebrate', 'celebration', 'fun', 'high', 'heaven',
      'paradise', 'magic', 'free', 'freedom', 'alive', 'fly', 'flying',
      'wonderful', 'beautiful', 'lucky', 'yes', 'feel good',
      // TR
      'mutlu', 'mutluluk', 'neşe', 'neşeli', 'gülüm', 'gülme', 'gülüş',
      'aşk', 'sevgi', 'sevgili', 'sevdiğim', 'tatlı', 'güneş', 'yaz',
      'dans', 'parti', 'kutlama', 'özgür', 'özgürlük', 'hayat', 'iyi',
      'güzel', 'harika', 'şans', 'yıldız', 'uçmak',
    ],
    'sad': [
      // EN
      'sad', 'sadness', 'cry', 'crying', 'tear', 'tears', 'alone', 'lonely',
      'lonesome', 'broken', 'break', 'breaking', 'hurt', 'hurts', 'pain',
      'painful', 'miss', 'missing', 'lost', 'lose', 'gone', 'goodbye',
      'bye', 'leave', 'leaving', 'apart', 'without', 'empty', 'numb',
      'cold', 'blue', 'sorry', 'regret', 'mistake', 'fall', 'falling',
      'down', 'die', 'dying', 'death', 'heart', 'heartbreak', 'silence',
      'silent', 'fade',
      // TR
      'hüzün', 'hüzünlü', 'üzgün', 'üzüntü', 'üzül', 'yalnız', 'yalnızlık',
      'kırık', 'kırıl', 'ağla', 'ağlıyor', 'ağlat', 'gözyaşı', 'gözya',
      'veda', 'gitti', 'gitme', 'bırak', 'bıraktı', 'özle', 'özledim',
      'özlem', 'kayıp', 'kayb', 'acı', 'acılı', 'dert', 'keder', 'boş',
      'soğuk', 'ölmek', 'ölüm', 'gönül', 'kalp', 'yıkıl', 'unutul',
      'pişman',
    ],
    'melancholy': [
      'melancholy', 'melancholic', 'nostalgia', 'nostalgic', 'remember',
      'memory', 'memories', 'dream', 'dreaming', 'rain', 'rainy', 'autumn',
      'fall', 'shadow', 'fade', 'faded', 'slow', 'empty', 'alone', 'gone',
      'yesterday', 'forever', 'nowhere', 'quiet', 'still', 'calm',
      'midnight', 'night', 'moon', 'stars',
      'melankoli', 'melankolik', 'hüzün', 'hüzünlü', 'nostalji', 'hatır',
      'anı', 'rüya', 'rüyalar', 'yağmur', 'yağmurlu', 'sonbahar', 'gölge',
      'solgun', 'unut', 'yavaş', 'boş', 'yalnız', 'sessiz', 'gece', 'ay',
      'yıldız',
    ],
    'angry': [
      'angry', 'anger', 'rage', 'fury', 'furious', 'mad', 'hate', 'fight',
      'fighting', 'war', 'battle', 'break', 'breaking', 'fire', 'burn',
      'burning', 'kill', 'killer', 'blood', 'bloody', 'scream', 'screaming',
      'rebel', 'revenge', 'riot', 'noise', 'loud', 'hard', 'heavy', 'metal',
      'rock',
      'öfke', 'öfkeli', 'kızgın', 'nefret', 'kavga', 'savaş', 'kırıl',
      'yak', 'yan', 'ateş', 'kan', 'çığlık', 'isyan', 'intikam', 'gürültü',
      'sert', 'ağır', 'kara',
    ],
    'calm': [
      'calm', 'peace', 'peaceful', 'quiet', 'silent', 'silence', 'still',
      'slow', 'soft', 'softly', 'sleep', 'sleeping', 'sleepy', 'dream',
      'rest', 'breathe', 'breathing', 'breath', 'lullaby', 'whisper',
      'gentle', 'easy', 'light', 'ocean', 'sea', 'water', 'river', 'sky',
      'cloud', 'wind', 'meditation', 'zen', 'relax', 'relaxing', 'chill',
      'sakin', 'sakinlik', 'huzur', 'huzurlu', 'sessiz', 'sessizlik',
      'yavaş', 'yumuşak', 'uyku', 'uyu', 'rüya', 'dinlen', 'nefes',
      'ninni', 'fısıl', 'hafif', 'deniz', 'su', 'gökyüzü', 'bulut',
      'rüzgar',
    ],
    'excited': [
      'party', 'dance', 'dancing', 'hype', 'energy', 'energetic', 'fire',
      'wild', 'crazy', 'alive', 'night', 'nightlife', 'club', 'bass',
      'loud', 'pump', 'jump', 'move', 'moving', 'shake', 'boom', 'bang',
      'rush', 'fast', 'speed', 'high', 'rocket', 'fly', 'flying',
      'electric',
      'parti', 'dans', 'enerji', 'enerjik', 'ateş', 'çılgın', 'hayat',
      'gece', 'kulüp', 'zıpla', 'zıplat', 'hızlı', 'uç', 'elektrik',
    ],
    'neutral': [],
    'fearful': [
      'fear', 'afraid', 'scared', 'scary', 'dark', 'darkness', 'shadow',
      'nightmare', 'haunt', 'haunted', 'ghost', 'devil', 'evil', 'monster',
      'alone', 'hide', 'run', 'running', 'chase', 'panic', 'horror',
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

  /// Build a personalized mood-matched list from the user's own catalog.
  /// Returns { success, tracks, diagnostics }.
  static Future<Map<String, dynamic>> recommend({
    required String mood,
    int limit = 10,
  }) async {
    final diag = <String, dynamic>{'mood': mood};
    final keywords = _moodKeywords[mood.toLowerCase()] ?? const <String>[];

    // 1. Pool the user's top tracks across short/medium/long ranges.
    final pool = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addAll(List<Map<String, dynamic>>? tracks) {
      if (tracks == null) return;
      for (final t in tracks) {
        final id = t['id']?.toString();
        if (id != null && seen.add(id)) pool.add(t);
      }
    }

    addAll(await SpotifyApiClient.getTopTracks(
        limit: 50, timeRange: 'short_term'));
    addAll(await SpotifyApiClient.getTopTracks(
        limit: 50, timeRange: 'medium_term'));
    addAll(await SpotifyApiClient.getTopTracks(
        limit: 50, timeRange: 'long_term'));
    diag['top_tracks_pool'] = pool.length;

    // 2. Score each track via word-boundary keyword matching.
    final patterns = keywords
        .map((kw) => RegExp(
              r'\b' + RegExp.escape(kw) + r'\b',
              caseSensitive: false,
              unicode: true,
            ))
        .toList();

    int scoreOf(Map<String, dynamic> t) {
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

    final scored = pool.map((t) => {...t, '_score': scoreOf(t)}).toList()
      ..sort((a, b) => (b['_score'] as int).compareTo(a['_score'] as int));

    final matched = scored.where((t) => (t['_score'] as int) > 0).toList();
    diag['matched_count'] = matched.length;

    // 3. Fill: mood-matched first, then personal-but-unmatched.
    final out = <Map<String, dynamic>>[];

    Map<String, dynamic> toRec(Map<String, dynamic> t, String source) => {
          'id': t['id'],
          'name': t['name'],
          'artist': t['artist'],
          'album': t['album'],
          'preview_url': t['preview_url'],
          'uri': t['uri'],
          'external_url': t['external_url'],
          'source': source,
          'score': t['_score'],
        };

    for (final t in matched) {
      if (out.length >= limit) break;
      out.add(toRec(t, 'catalog_mood_matched'));
    }
    for (final t in scored) {
      if (out.length >= limit) break;
      if ((t['_score'] as int) > 0) continue;
      out.add({...toRec(t, 'catalog_fill'), 'score': 0});
    }

    await SpotifyLogger.log('USER_CATALOG', {
      ...diag,
      'final_count': out.length,
    });

    return {
      'success': out.isNotEmpty,
      'tracks': out,
      'diagnostics': diag,
    };
  }
}
