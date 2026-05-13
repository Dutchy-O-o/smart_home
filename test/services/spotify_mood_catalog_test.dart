import 'package:flutter_test/flutter_test.dart';

import 'package:akilli_ev/services/spotify/spotify_mood_catalog.dart';

/// Regex matcher is the kingmaker of mood recommendations — if word
/// boundaries break, Turkish keywords stop firing, or the per-field
/// weights drift, every recommendation in the AI Hub starts looking
/// random. These tests pin the behavior so a future "small tweak"
/// can't silently degrade it.
void main() {
  // Convenience: build a track payload with only the fields scoreTrackForMood reads.
  Map<String, dynamic> track({
    String name = '',
    String album = '',
    String artist = '',
  }) =>
      {'name': name, 'album': album, 'artist': artist};

  group('SpotifyMoodCatalog.scoreTrackForMood — happy', () {
    test('matches English "sunshine" on track name (weight 10)', () {
      final score = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'happy',
        track: track(name: 'Walking on Sunshine'),
      );
      expect(score, 10);
    });

    test('matches Turkish "mutlu" on track name (weight 10)', () {
      final score = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'happy',
        track: track(name: 'Mutlu Günler'),
      );
      expect(score, 10);
    });

    test('artist match weights 5, less than name match', () {
      final nameScore = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'happy',
        track: track(name: 'Happy Days', artist: 'X'),
      );
      final artistScore = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'happy',
        track: track(name: 'X', artist: 'Happy Days'),
      );
      expect(nameScore, greaterThan(artistScore));
      expect(artistScore, 5);
    });

    test('album match weights 3, the lowest', () {
      final score = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'happy',
        track: track(name: 'Unrelated', album: 'Sunshine Edition'),
      );
      expect(score, 3);
    });
  });

  group('SpotifyMoodCatalog.scoreTrackForMood — Turkish characters', () {
    test('matches "hüzün" on track name despite umlaut', () {
      final score = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'melancholy',
        track: track(name: 'Hüzün Akşamı'),
      );
      expect(score, 10);
    });

    test('matches "ölmek" on artist (ö + word boundary)', () {
      final score = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'sad',
        track: track(name: 'X', artist: 'Ölmek Üzere'),
      );
      expect(score, 5);
    });

    test('matches "şaşır" stem with word-boundary regex', () {
      final score = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'surprised',
        track: track(name: 'Şaşır beni'),
      );
      expect(score, 10);
    });

    test('mixed EN+TR matches stack additively', () {
      final score = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'happy',
        track: track(
          name: 'Sunshine',
          album: 'Mutluluk',
          artist: 'Happy Crew',
        ),
      );
      // name 'sunshine' = 10, album 'mutluluk' = 3, artist 'happy' = 5
      expect(score, 18);
    });
  });

  group('SpotifyMoodCatalog.scoreTrackForMood — non-matches', () {
    test('unrelated track scores 0', () {
      final score = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'happy',
        track: track(name: 'Imagine', artist: 'John Lennon'),
      );
      expect(score, 0);
    });

    test('neutral mood always scores 0 (empty keyword list)', () {
      final score = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'neutral',
        track: track(name: 'Walking on Sunshine'),
      );
      expect(score, 0);
    });

    test('unknown mood scores 0 without throwing', () {
      final score = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'sleepyhead',
        track: track(name: 'Happy Days'),
      );
      expect(score, 0);
    });

    test('case-insensitive: "HAPPY" matches "happy"', () {
      final score = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'happy',
        track: track(name: 'HAPPY HOUR'),
      );
      expect(score, 10);
    });
  });

  group('SpotifyMoodCatalog.scoreTrackForMood — word boundary', () {
    test('substring inside a longer word does NOT match', () {
      // "happy" is in "unhappy" but should NOT trigger a happy-mood match
      // because of the leading boundary — that's exactly what \b enforces.
      final score = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'happy',
        track: track(name: 'unhappy'),
      );
      expect(score, 0);
    });

    test('"fall" matches "fall" but not "fallout"', () {
      // 'fall' is in melancholy keywords. The boundary must reject 'fallout'.
      final standalone = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'melancholy',
        track: track(name: 'fall season'),
      );
      final compound = SpotifyMoodCatalog.scoreTrackForMood(
        mood: 'melancholy',
        track: track(name: 'fallout'),
      );
      expect(standalone, greaterThan(0));
      expect(compound, 0);
    });
  });
}
