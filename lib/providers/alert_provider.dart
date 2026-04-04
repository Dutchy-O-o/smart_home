import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  @override
  List<AlertItem> build() => [];

  void addAlert(AlertItem alert) {
    state = [alert, ...state];
  }

  void markAllRead() {
    state = [for (final a in state) a..isRead = true];
  }

  void markRead(String id) {
    state = [for (final a in state) if (a.id == id) a..isRead = true else a];
  }

  void dismiss(String id) {
    state = state.where((a) => a.id != id).toList();
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
