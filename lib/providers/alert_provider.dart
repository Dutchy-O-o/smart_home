import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/user_scope.dart';

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
  static const _baseStorageKey = 'alerts_v1';
  static String get _storageKey => UserScope.key(_baseStorageKey);
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

  /// Same as [addAlert] but also pushes the entry to the AWS alerts
  /// endpoint (`POST /{homeId}/alerts`) so it survives across devices.
  /// The local copy is added immediately for snappy UI; the server
  /// call is fire-and-forget and silently no-ops when the route isn't
  /// deployed yet.
  void addAlertSynced(AlertItem alert, {required String homeId}) {
    addAlert(alert);
    if (homeId.isEmpty) return;
    ApiService.postAlert(
      homeId: homeId,
      title: alert.title,
      description: alert.description,
      alertType: alert.type.name,
      alertLevel: alert.level.name,
    );
  }

  /// Pull the latest alerts from AWS and **merge** them with the local
  /// list. Local entries that aren't on the server (push notifications
  /// the FCM handler caught while AWS save races, or anything created
  /// before /alerts was deployed) are preserved. Server entries that
  /// aren't local are prepended.
  ///
  /// Silently no-ops when the route isn't deployed.
  Future<void> hydrateFromAws(String homeId) async {
    if (homeId.isEmpty) return;
    final remote = await ApiService.fetchAlerts(homeId);
    if (remote == null) return; // route not deployed → preserve local
    final loaded = <AlertItem>[];
    for (final j in remote) {
      final created = j['created_at'];
      // Server emits ISO with 'Z' suffix → parse as UTC, convert to
      // local so Today/Yesterday/This-week buckets match the user's
      // wall-clock instead of the server's UTC clock.
      final ts =
          created is String ? DateTime.tryParse(created)?.toLocal() : null;
      AlertType t;
      switch ((j['type'] ?? '').toString()) {
        case 'security':
          t = AlertType.security;
          break;
        case 'emotion':
          t = AlertType.emotion;
          break;
        default:
          t = AlertType.device;
      }
      AlertLevel l;
      switch ((j['level'] ?? '').toString()) {
        case 'critical':
          l = AlertLevel.critical;
          break;
        case 'warning':
          l = AlertLevel.warning;
          break;
        default:
          l = AlertLevel.info;
      }
      loaded.add(AlertItem(
        id: ts != null
            ? ts.millisecondsSinceEpoch.toString()
            : (j['id']?.toString() ?? ''),
        title: (j['title'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        time: ts != null
            ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
            : '',
        type: t,
        level: l,
        isRead: j['is_read'] == true,
      ));
    }

    // Merge: keep both lists, dedupe on (title + description + time)
    // since AWS/local IDs are generated independently. AWS rows win
    // on `is_read` since the server is the source of truth there.
    final merged = <AlertItem>[];
    final seen = <String>{};
    String key(AlertItem a) => '${a.title}|${a.description}|${a.time}';

    for (final a in loaded) {
      if (seen.add(key(a))) merged.add(a);
    }
    for (final a in state) {
      if (seen.add(key(a))) merged.add(a);
    }
    // Newest-first: AWS came back ordered DESC; local was already
    // newest-first; both halves stay roughly sorted, but we don't
    // hard-sort by ID since IDs are non-comparable across sources.
    state = merged;
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
