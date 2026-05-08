import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'user_scope.dart';

/// One mood reading captured locally whenever moodProvider.set() runs.
/// Stored as compact JSON in SharedPreferences for the per-hour heatmap.
class MoodEntry {
  MoodEntry({
    required this.mood,
    required this.timestamp,
    this.confidence = 1.0,
  });

  final String mood;
  final DateTime timestamp;
  final double confidence;

  Map<String, dynamic> toJson() => {
        'm': mood,
        't': timestamp.millisecondsSinceEpoch,
        'c': confidence,
      };

  static MoodEntry? fromJson(Map<String, dynamic> j) {
    final m = j['m'];
    final t = j['t'];
    if (m is! String || t is! int) return null;
    return MoodEntry(
      mood: m,
      timestamp: DateTime.fromMillisecondsSinceEpoch(t),
      confidence: (j['c'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Per-user mood history, kept locally so the weekly heatmap survives
/// app restarts without needing a backend endpoint. Retains the last
/// 7 days × 24 hours of entries (max ~168 readings, but we cap higher
/// for safety) and dedupes within the same calendar hour.
class MoodHistoryService {
  static const _retention = Duration(days: 7);
  static const _maxEntries = 500;
  static const _baseKey = 'mood_history_v1';
  static String get _key => UserScope.key(_baseKey);

  static Future<List<MoodEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(MoodEntry.fromJson)
          .whereType<MoodEntry>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Append a mood entry, replacing any earlier entry recorded in the
  /// same calendar hour so the heatmap shows one dominant mood per hour.
  /// Older-than-7-day entries are pruned.
  static Future<void> append(String mood, {double confidence = 1.0}) async {
    final history = await load();
    final now = DateTime.now();
    final cutoff = now.subtract(_retention);

    final hourBucket = DateTime(now.year, now.month, now.day, now.hour);
    history.removeWhere((e) {
      final eb =
          DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day, e.timestamp.hour);
      return eb == hourBucket;
    });

    history.add(MoodEntry(
      mood: mood,
      timestamp: now,
      confidence: confidence,
    ));

    final filtered = history.where((e) => e.timestamp.isAfter(cutoff)).toList();
    final trimmed = filtered.length > _maxEntries
        ? filtered.sublist(filtered.length - _maxEntries)
        : filtered;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(trimmed.map((e) => e.toJson()).toList()));
  }

  /// Returns the dominant mood per (day, hour) bucket for the last 7 days,
  /// indexed as map[dayOffset][hour] → mood, where dayOffset 0 = today,
  /// 6 = 7 days ago. Empty buckets are absent from the inner map.
  ///
  /// Pulls from AWS (`/emotion-history`) when [homeId] is provided and
  /// the route is deployed; otherwise falls back to local SharedPreferences.
  /// AWS results are mirrored into the local cache so subsequent offline
  /// reads still get the data.
  static Future<Map<int, Map<int, String>>> weeklyGrid({String? homeId}) async {
    List<MoodEntry> history = const [];

    if (homeId != null && homeId.isNotEmpty) {
      final remote = await ApiService.fetchMoodHistory(homeId, days: 7);
      if (remote != null) {
        history = remote
            .map((j) {
              final ts = j['timestamp'];
              // Server stamps 'Z' suffix → DateTime.parse treats as UTC.
              // Convert to local so the heatmap groups by the user's
              // wall-clock hour, not the RDS server's UTC hour.
              final t = ts is String ? DateTime.tryParse(ts)?.toLocal() : null;
              if (t == null) return null;
              return MoodEntry(
                mood: (j['emotion'] ?? '').toString(),
                timestamp: t,
                confidence: (j['confidence'] as num?)?.toDouble() ?? 1.0,
              );
            })
            .whereType<MoodEntry>()
            .toList();
        // Mirror to local cache so offline readers still see it.
        await _writeAll(history);
      }
    }
    if (history.isEmpty) {
      history = await load();
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = <int, Map<int, String>>{};
    for (final e in history) {
      // Defensive .toLocal(): entries written by older builds may still
      // be UTC-flavored; new ones from append() are already local.
      final ts = e.timestamp.isUtc ? e.timestamp.toLocal() : e.timestamp;
      final day = DateTime(ts.year, ts.month, ts.day);
      final dayOffset = today.difference(day).inDays;
      if (dayOffset < 0 || dayOffset > 6) continue;
      result.putIfAbsent(dayOffset, () => <int, String>{});
      result[dayOffset]![ts.hour] = e.mood;
    }
    return result;
  }

  static Future<void> _writeAll(List<MoodEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, json.encode(entries.map((e) => e.toJson()).toList()));
  }
}
