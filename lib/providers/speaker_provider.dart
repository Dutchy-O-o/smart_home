import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cross-screen state for the smart speaker(s) so the Dashboard mini-card and
/// the Devices screen never disagree about what's happening with playback.
///
/// Why this exists: both screens previously kept their own `_playbackPulse`
/// map and their own poll for `getCurrentlyPlaying`, so pausing on one
/// screen would leave the other showing "playing" until its next API tick
/// (and the now-playing track only appeared on whichever screen happened
/// to fetch it). Lifting these to a single Riverpod notifier means a single
/// source of truth — and the Devices speaker card can now show the same
/// "▶ Track — Artist" line the Dashboard already had.
@immutable
class SpeakerSyncState {
  final Map<String, String> playbackPulse; // deviceId → 'play' | 'pause'
  final Map<String, dynamic>? nowPlaying;  // {track: {name, artist}, is_playing, device}

  const SpeakerSyncState({
    this.playbackPulse = const {},
    this.nowPlaying,
  });

  SpeakerSyncState copyWith({
    Map<String, String>? playbackPulse,
    Map<String, dynamic>? nowPlaying,
    bool clearNowPlaying = false,
  }) {
    return SpeakerSyncState(
      playbackPulse: playbackPulse ?? this.playbackPulse,
      nowPlaying: clearNowPlaying ? null : (nowPlaying ?? this.nowPlaying),
    );
  }
}

class SpeakerSyncNotifier extends Notifier<SpeakerSyncState> {
  @override
  SpeakerSyncState build() => const SpeakerSyncState();

  /// Record what the user just tapped (play/pause) for a given device. Both
  /// screens read from this so the highlighted button matches everywhere.
  void setPlayback(String deviceId, String value) {
    final next = Map<String, String>.from(state.playbackPulse);
    next[deviceId] = value;
    state = state.copyWith(playbackPulse: next);
  }

  /// Update the global "now playing" snapshot. Called by whichever screen
  /// is currently polling — both write, both read, neither owns it.
  void setNowPlaying(Map<String, dynamic>? track) {
    if (track == null) {
      state = state.copyWith(clearNowPlaying: true);
      return;
    }
    // Skip rebuilds when nothing meaningful changed.
    final newName = track['track']?['name'];
    final oldName = state.nowPlaying?['track']?['name'];
    if (newName == oldName &&
        track['is_playing'] == state.nowPlaying?['is_playing']) {
      return;
    }
    state = state.copyWith(nowPlaying: track);
  }
}

final speakerSyncProvider =
    NotifierProvider<SpeakerSyncNotifier, SpeakerSyncState>(
  SpeakerSyncNotifier.new,
);
