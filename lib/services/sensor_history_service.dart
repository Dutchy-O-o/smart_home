import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'user_scope.dart';

/// One temperature/humidity reading captured locally from the dashboard
/// poll. Stored as JSON in SharedPreferences so the sparkline survives
/// app restarts.
class SensorReading {
  SensorReading({required this.timestamp, this.temperature, this.humidity});

  final DateTime timestamp;
  final double? temperature;
  final double? humidity;

  Map<String, dynamic> toJson() => {
        't': timestamp.millisecondsSinceEpoch,
        if (temperature != null) 'tc': temperature,
        if (humidity != null) 'h': humidity,
      };

  static SensorReading? fromJson(Map<String, dynamic> j) {
    final t = j['t'];
    if (t is! int) return null;
    return SensorReading(
      timestamp: DateTime.fromMillisecondsSinceEpoch(t),
      temperature: (j['tc'] as num?)?.toDouble(),
      humidity: (j['h'] as num?)?.toDouble(),
    );
  }
}

/// Lightweight local ring buffer of [SensorReading]s, scoped per home so
/// switching homes doesn't mix series. Keeps up to [_maxReadings] (~12h
/// worth at 30 second spacing) and discards same-bucket duplicates.
///
/// Bucket size traded down from 5 minutes → 30 seconds so the dashboard
/// sparkline appears within ~1 minute of a fresh install instead of
/// making the user stare at a "collecting…" placeholder for 10 minutes.
class SensorHistoryService {
  static const _maxReadings = 1440;
  static const _bucketMs = 30 * 1000; // 30 seconds
  static const _retention = Duration(hours: 12);
  static String _key(String homeId) =>
      UserScope.key('sensor_history_v2_$homeId');

  static Future<List<SensorReading>> load(String homeId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(homeId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(SensorReading.fromJson)
          .whereType<SensorReading>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Pull the full server-side history (12 h by default) and overwrite
  /// the local cache with it. Lets the dashboard sparkline come up
  /// already-populated instead of waiting for the 5-second poll to
  /// trickle in samples. No-op when the AWS route isn't deployed.
  static Future<List<SensorReading>> hydrateFromAws(
    String homeId, {
    int hours = 12,
  }) async {
    final remote = await ApiService.fetchSensorHistory(homeId, hours: hours);
    if (remote == null || remote.isEmpty) return load(homeId);
    final readings = <SensorReading>[];
    for (final j in remote) {
      final ts = j['timestamp'];
      // Server appends 'Z' → parse as UTC, then convert to local so
      // the chart x-axis matches the user's wall-clock.
      final t = ts is String ? DateTime.tryParse(ts)?.toLocal() : null;
      if (t == null) continue;
      readings.add(SensorReading(
        timestamp: t,
        temperature: (j['temperature'] as num?)?.toDouble(),
        humidity: (j['humidity'] as num?)?.toDouble(),
      ));
    }
    if (readings.isEmpty) return load(homeId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key(homeId), json.encode(readings.map((r) => r.toJson()).toList()));
    return readings;
  }

  /// Append a reading, discarding entries older than 24h and dropping
  /// duplicates within the same 5-min bucket. No-op if both values null.
  static Future<List<SensorReading>> append(
    String homeId, {
    double? temperature,
    double? humidity,
  }) async {
    if (temperature == null && humidity == null) {
      return load(homeId);
    }
    final history = await load(homeId);
    final now = DateTime.now();
    final cutoff = now.subtract(_retention);

    // Drop the previous reading if it's in the same 5-min bucket so we
    // don't fill the buffer with redundant samples from the 5-second poll.
    if (history.isNotEmpty) {
      final last = history.last;
      if (now.millisecondsSinceEpoch - last.timestamp.millisecondsSinceEpoch <
          _bucketMs) {
        history.removeLast();
      }
    }

    history.add(SensorReading(
      timestamp: now,
      temperature: temperature,
      humidity: humidity,
    ));

    final filtered =
        history.where((r) => r.timestamp.isAfter(cutoff)).toList();
    final trimmed = filtered.length > _maxReadings
        ? filtered.sublist(filtered.length - _maxReadings)
        : filtered;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(homeId),
      json.encode(trimmed.map((r) => r.toJson()).toList()),
    );
    return trimmed;
  }
}
