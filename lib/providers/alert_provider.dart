import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/alert_localizer.dart';
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
  /// How many identical events were folded into this single entry by the
  /// coalescing logic in [AlertListNotifier.addAlert]. 1 for a normal
  /// alert; >1 when, e.g., the vibration sensor fired ten times in a
  /// minute and the notifications screen would otherwise be unreadable.
  int count;

  AlertItem({
    required this.id,
    required this.title,
    required this.description,
    required this.time,
    this.day = "today",
    required this.type,
    required this.level,
    this.isRead = false,
    this.count = 1,
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
        'count': count,
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
        count: (json['count'] is num) ? (json['count'] as num).toInt() : 1,
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
  /// Window during which identical alerts get folded into a single entry
  /// instead of stacking. Five minutes is wide enough to catch the
  /// vibration-sensor-firing-10-times-in-a-minute case while still
  /// surfacing a *new* tremor that follows half an hour later.
  static const _coalesceWindow = Duration(minutes: 5);
  /// How far down the list we look for a coalesce target. Bounded so a
  /// fresh alert that genuinely matches something old (e.g. half an hour
  /// later) still creates a new row.
  static const _coalesceScanDepth = 8;

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
      // Upgrade English-only records that were saved before the bilingual
      // rollout to the new TR/EN format. Matches on title keywords —
      // `reskinAlert` returns null when nothing recognizable is found, in
      // which case we leave the original copy alone.
      state = list.whereType<Map<String, dynamic>>().map((j) {
        final item = AlertItem.fromJson(j);
        final reskinned = reskinAlert(item.title, item.description);
        if (reskinned == null) return item;
        return AlertItem(
          id: item.id,
          title: reskinned.title,
          description: reskinned.body,
          time: item.time,
          day: item.day,
          type: item.type,
          level: item.level,
          isRead: item.isRead,
          count: item.count,
        );
      }).toList();
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

  /// Adds [alert] to the list. If an identical alert (same title,
  /// description, and type) was already inserted within
  /// [_coalesceWindow], bumps that entry's `count` and refreshes its
  /// timestamp instead of stacking a new row — keeps the notifications
  /// screen readable when, e.g., the vibration sensor fires repeatedly.
  ///
  /// Returns `true` if a brand-new row was prepended, `false` if the
  /// call was folded into an existing one. [addAlertSynced] uses the
  /// return value to skip the AWS POST on duplicates.
  bool addAlert(AlertItem alert) {
    final now = DateTime.now();
    final scanEnd =
        state.length < _coalesceScanDepth ? state.length : _coalesceScanDepth;
    for (var i = 0; i < scanEnd; i++) {
      final existing = state[i];
      if (existing.title != alert.title) continue;
      if (existing.description != alert.description) continue;
      if (existing.type != alert.type) continue;
      final ts = int.tryParse(existing.id);
      if (ts == null) continue;
      final age = now.difference(DateTime.fromMillisecondsSinceEpoch(ts));
      if (age > _coalesceWindow) continue;

      // Coalesce: bump count, refresh time, keep severity/read state.
      final folded = AlertItem(
        id: existing.id,
        title: existing.title,
        description: existing.description,
        time: alert.time.isNotEmpty ? alert.time : existing.time,
        day: existing.day,
        type: existing.type,
        level: existing.level,
        isRead: false, // a new identical event should re-notify the user
        count: existing.count + 1,
      );
      state = [
        for (var j = 0; j < state.length; j++)
          if (j == i) folded else state[j],
      ];
      _save();
      return false;
    }

    state = [alert, ...state];
    _save();
    return true;
  }

  /// Same as [addAlert] but also pushes the entry to the AWS alerts
  /// endpoint (`POST /{homeId}/alerts`) so it survives across devices.
  /// The local copy is added immediately for snappy UI; the server
  /// call is fire-and-forget and silently no-ops when the route isn't
  /// deployed yet. Skips the POST when [addAlert] folded the entry into
  /// an existing one — no point in syncing duplicates.
  void addAlertSynced(AlertItem alert, {required String homeId}) {
    final added = addAlert(alert);
    if (!added) return;
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
      var rawTitle = (j['title'] ?? '').toString();
      var rawBody = (j['description'] ?? '').toString();
      // Old server-side records from before the bilingual rollout still
      // hold English-only titles like "⚠️ EARTHQUAKE ALERT!". Sniff the
      // title and swap them for the bilingual version on hydrate so the
      // notifications screen doesn't show a permanent reminder that the
      // feature was added halfway through the project.
      final reskinned = reskinAlert(rawTitle, rawBody);
      if (reskinned != null) {
        rawTitle = reskinned.title;
        rawBody = reskinned.body;
      }
      loaded.add(AlertItem(
        id: ts != null
            ? ts.millisecondsSinceEpoch.toString()
            : (j['id']?.toString() ?? ''),
        title: rawTitle,
        description: rawBody,
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
