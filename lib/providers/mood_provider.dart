import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/mood_history_service.dart';
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
    // Update state synchronously FIRST so the UI rebuilds immediately.
    // Earlier we awaited the disk write before the state change, which
    // meant any hiccup in SharedPreferences (slow phone, locked file)
    // froze the mood card on the previous value. Now the UI flips
    // first; persistence happens after.
    state = MoodState(
      mood: next,
      confidence: confidence,
      updatedAt: DateTime.now(),
      source: source,
    );
    _save();
    // Append history in the background — wrapped in catch so a disk
    // failure never bubbles into the UI as an unhandled future error.
    if (source != 'init') {
      MoodHistoryService.append(next, confidence: confidence)
          .catchError((e) {
        // Best-effort persistence; just log so the state change still
        // reflects in the UI even when the heatmap can't update.
        // ignore: avoid_print
        print('MoodHistoryService.append failed: $e');
      });
    }
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
