import 'package:flutter_riverpod/flutter_riverpod.dart';

class MoodState {
  final String? mood;
  final double confidence;
  final DateTime? updatedAt;
  final String source; // 'scan', 'manual', 'chatbot'

  const MoodState({
    this.mood,
    this.confidence = 0.0,
    this.updatedAt,
    this.source = 'none',
  });
}

class MoodNotifier extends Notifier<MoodState> {
  @override
  MoodState build() => const MoodState();

  void set(String mood, double confidence, {required String source}) {
    state = MoodState(
      mood: mood.toLowerCase(),
      confidence: confidence,
      updatedAt: DateTime.now(),
      source: source,
    );
  }

  void clear() => state = const MoodState();
}

final moodProvider =
    NotifierProvider<MoodNotifier, MoodState>(MoodNotifier.new);
