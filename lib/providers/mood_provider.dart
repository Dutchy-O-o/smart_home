import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alert_provider.dart';

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

  Map<String, dynamic> toJson() => {
        'mood': mood,
        'confidence': confidence,
        'updatedAt': updatedAt?.toIso8601String(),
        'source': source,
      };

  factory MoodState.fromJson(Map<String, dynamic> json) => MoodState(
        mood: json['mood'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        updatedAt: json['updatedAt'] is String
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
        source: (json['source'] as String?) ?? 'none',
      );
}

class MoodNotifier extends Notifier<MoodState> {
  static const _storageKey = 'mood_state_v1';

  // Map UI/AI long forms to the short FER vocabulary used by the Pi
  // emotion API and the automation rules in the database.
  static const Map<String, String> _canonicalMood = {
    'surprised': 'surprise',
    'fearful': 'fear',
    'disgusted': 'disgust',
  };

  static String _canonical(String mood) {
    final lower = mood.toLowerCase();
    return _canonicalMood[lower] ?? lower;
  }

  @override
  MoodState build() {
    _load();
    return const MoodState();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      state = MoodState.fromJson(json);
    } catch (_) {
      // Corrupt payload — start fresh.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(state.toJson()));
    } catch (_) {
      // Best-effort persistence; ignore write failures.
    }
  }

  void set(String mood, double confidence, {required String source}) {
    final prev = state.mood;
    final next = _canonical(mood);
    state = MoodState(
      mood: next,
      confidence: confidence,
      updatedAt: DateTime.now(),
      source: source,
    );
    _save();
    if (prev != next && source != 'init') {
      _emitLocalAlert(next, source);
    }
  }

  void clear() {
    state = const MoodState();
    _save();
  }

  void _emitLocalAlert(String mood, String source) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final sourceLabel = switch (source) {
      'scan' => 'face scan',
      'manual' => 'manual',
      'chatbot' => 'AI chat',
      _ => source,
    };
    ref.read(alertListProvider.notifier).addAlert(
          AlertItem(
            id: now.millisecondsSinceEpoch.toString(),
            title: 'Mood updated: $mood',
            description: 'New emotion detected via $sourceLabel.',
            time: time,
            type: AlertType.emotion,
            level: AlertLevel.info,
          ),
        );
  }
}

final moodProvider =
    NotifierProvider<MoodNotifier, MoodState>(MoodNotifier.new);
