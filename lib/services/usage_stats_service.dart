import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_scope.dart';

/// Tiny per-user usage counter, kept locally so the profile screen can
/// surface "you've used this app for N days, top scene is Movie, you've
/// chatted with the AI X times" without needing a backend table.
class UsageStatsService {
  static const _baseFirstLaunch = 'usage_first_launch_v1';
  static const _baseSceneCounts = 'usage_scene_counts_v1';
  static const _baseChatTurns = 'usage_chat_turns_v1';

  static String get _firstLaunchKey => UserScope.key(_baseFirstLaunch);
  static String get _sceneCountsKey => UserScope.key(_baseSceneCounts);
  static String get _chatTurnsKey => UserScope.key(_baseChatTurns);

  /// Day the current user first opened the app. Stamped lazily on the
  /// first read; subsequent reads return the original date so the
  /// "Days active" stat keeps growing.
  static Future<DateTime> firstLaunchDate() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_firstLaunchKey);
    if (saved != null) return DateTime.fromMillisecondsSinceEpoch(saved);
    final now = DateTime.now();
    await prefs.setInt(_firstLaunchKey, now.millisecondsSinceEpoch);
    return now;
  }

  static Future<int> daysActive() async {
    final first = await firstLaunchDate();
    final delta = DateTime.now().difference(first).inDays;
    return delta < 1 ? 1 : delta + 1; // include today
  }

  static Future<Map<String, int>> sceneCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sceneCountsKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
    } catch (_) {
      return const {};
    }
  }

  static Future<void> recordSceneRun(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final counts = Map<String, int>.from(await sceneCounts());
    counts[key] = (counts[key] ?? 0) + 1;
    await prefs.setString(_sceneCountsKey, json.encode(counts));
  }

  static Future<int> chatTurns() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_chatTurnsKey) ?? 0;
  }

  static Future<void> recordChatTurn() async {
    final prefs = await SharedPreferences.getInstance();
    final cur = prefs.getInt(_chatTurnsKey) ?? 0;
    await prefs.setInt(_chatTurnsKey, cur + 1);
  }
}
