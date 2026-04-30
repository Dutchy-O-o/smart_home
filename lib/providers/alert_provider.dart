import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AlertType { security, emotion, device }
enum AlertLevel { critical, warning, info }

class AlertItem {
  final String id;
  final String title;
  final String description;
  final String time;
  final String day;
  final AlertType type;
  final AlertLevel level;
  bool isRead;

  AlertItem({
    required this.id,
    required this.title,
    required this.description,
    required this.time,
    this.day = "today",
    required this.type,
    required this.level,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'time': time,
        'day': day,
        'type': type.name,
        'level': level.name,
        'isRead': isRead,
      };

  factory AlertItem.fromJson(Map<String, dynamic> json) => AlertItem(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        time: json['time']?.toString() ?? '',
        day: json['day']?.toString() ?? 'today',
        type: AlertType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => AlertType.device,
        ),
        level: AlertLevel.values.firstWhere(
          (e) => e.name == json['level'],
          orElse: () => AlertLevel.info,
        ),
        isRead: json['isRead'] == true,
      );
}

class AlertFilter {
  final String type;
  final String level;
  const AlertFilter({this.type = "All", this.level = "Any"});

  AlertFilter copyWith({String? type, String? level}) =>
      AlertFilter(type: type ?? this.type, level: level ?? this.level);
}

class AlertFilterNotifier extends Notifier<AlertFilter> {
  @override
  AlertFilter build() => const AlertFilter();
  void setType(String t) => state = state.copyWith(type: t);
  void setLevel(String l) => state = state.copyWith(level: l);
}

final alertFilterProvider =
    NotifierProvider<AlertFilterNotifier, AlertFilter>(AlertFilterNotifier.new);

class AlertListNotifier extends Notifier<List<AlertItem>> {
  static const _storageKey = 'alerts_v1';
  static const _maxStored = 200;

  @override
  List<AlertItem> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      state = list
          .whereType<Map<String, dynamic>>()
          .map(AlertItem.fromJson)
          .toList();
    } catch (_) {
      // Corrupt payload — start fresh.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = state.take(_maxStored).toList();
      final raw = jsonEncode(trimmed.map((a) => a.toJson()).toList());
      await prefs.setString(_storageKey, raw);
    } catch (_) {
      // Best-effort persistence; ignore write failures.
    }
  }

  void addAlert(AlertItem alert) {
    state = [alert, ...state];
    _save();
  }

  void markAllRead() {
    state = [for (final a in state) a..isRead = true];
    _save();
  }

  void markRead(String id) {
    state = [for (final a in state) if (a.id == id) a..isRead = true else a];
    _save();
  }

  void dismiss(String id) {
    state = state.where((a) => a.id != id).toList();
    _save();
  }

  void clearAll() {
    state = [];
    _save();
  }
}

final alertListProvider =
    NotifierProvider<AlertListNotifier, List<AlertItem>>(AlertListNotifier.new);

final filteredAlertsProvider = Provider<List<AlertItem>>((ref) {
  final all = ref.watch(alertListProvider);
  final filter = ref.watch(alertFilterProvider);

  return all.where((a) {
    if (filter.type != "All") {
      final typeStr = a.type.name[0].toUpperCase() + a.type.name.substring(1);
      if (typeStr != filter.type) return false;
    }
    if (filter.level != "Any") {
      final levelStr = a.level.name[0].toUpperCase() + a.level.name.substring(1);
      if (levelStr != filter.level) return false;
    }
    return true;
  }).toList();
});
