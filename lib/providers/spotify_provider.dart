import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/spotify_service.dart';

/// Spotify connection state
final spotifyAuthProvider = NotifierProvider<SpotifyAuthNotifier, SpotifyAuthState>(
  SpotifyAuthNotifier.new,
);

/// Mood-based recommendation result
final spotifyMoodProvider = FutureProvider.family<Map<String, dynamic>, MoodRequest>((ref, request) async {
  return SpotifyService.getMoodBasedRecommendations(
    mood: request.mood,
    confidence: request.confidence,
  );
});

class MoodRequest {
  final String mood;
  final double confidence;

  const MoodRequest({required this.mood, this.confidence = 0.94});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoodRequest && mood == other.mood && confidence == other.confidence;

  @override
  int get hashCode => mood.hashCode ^ confidence.hashCode;
}

enum SpotifyConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class SpotifyAuthState {
  final SpotifyConnectionStatus status;
  final String? errorMessage;

  const SpotifyAuthState({
    this.status = SpotifyConnectionStatus.disconnected,
    this.errorMessage,
  });

  SpotifyAuthState copyWith({
    SpotifyConnectionStatus? status,
    String? errorMessage,
  }) {
    return SpotifyAuthState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class SpotifyAuthNotifier extends Notifier<SpotifyAuthState> {
  @override
  SpotifyAuthState build() {
    Future.microtask(() => _tryLoadSavedToken());
    return const SpotifyAuthState();
  }

  Future<void> _tryLoadSavedToken() async {
    final loaded = await SpotifyService.loadSavedToken();
    if (loaded) {
      state = state.copyWith(status: SpotifyConnectionStatus.connected);
    }
  }

  Future<void> handleAuthCode(String code) async {
    state = state.copyWith(status: SpotifyConnectionStatus.connecting);

    final success = await SpotifyService.exchangeCodeForToken(code);
    if (success) {
      state = state.copyWith(status: SpotifyConnectionStatus.connected);
    } else {
      state = state.copyWith(
        status: SpotifyConnectionStatus.error,
        errorMessage: 'Token exchange failed',
      );
    }
  }

  Future<void> disconnect() async {
    await SpotifyService.disconnect();
    state = state.copyWith(status: SpotifyConnectionStatus.disconnected);
  }
}
