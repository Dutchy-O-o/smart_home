import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import 'alert_provider.dart';
import 'home_provider.dart';

/// Optimistic device-state overlay shared between the chat assistant and the
/// devices screen. The Pi firmware only echoes `power` today, so AC/oven
/// detail properties (mode, target_temp, fan_speed, timer) and LED detail
/// properties never come back from the device → never land in the DB →
/// the polled `getDevices` response can't surface them. Anything the user
/// or the assistant sets for those properties is parked here and the
/// devices screen merges it on top of the DB values when it renders.
///
/// Also owns the **oven timer countdown**: when a device's `timer` property
/// is set to a positive number, this notifier ticks it down by one every
/// minute, then flips `power` to `off` and writes a notification when it
/// reaches zero. We park it on the notifier (instead of inside the devices
/// screen) so the countdown keeps running while the user is on the chat
/// tab or anywhere else in the app.
///
/// Entries live until the app process exits.
class DeviceOverridesNotifier
    extends Notifier<Map<String, Map<String, dynamic>>> {
  final Map<String, Timer> _countdowns = {};

  @override
  Map<String, Map<String, dynamic>> build() {
    ref.onDispose(() {
      for (final t in _countdowns.values) {
        t.cancel();
      }
      _countdowns.clear();
    });
    return const {};
  }

  void set(String deviceId, String property, dynamic value) {
    final current = Map<String, dynamic>.from(state[deviceId] ?? const {});
    current[property] = value;
    state = {...state, deviceId: current};

    // Countdown lifecycle hooks. Only `timer` and `power` can start or
    // stop a running countdown — everything else just lands in state.
    if (property == 'timer') {
      _cancelCountdown(deviceId);
      final minutes = _readInt(value);
      if (minutes > 0) {
        _startCountdown(deviceId);
      }
    } else if (property == 'power' && value?.toString() == 'off') {
      _cancelCountdown(deviceId);
    }
  }

  Map<String, dynamic> forDevice(String deviceId) =>
      state[deviceId] ?? const {};

  void _cancelCountdown(String deviceId) {
    _countdowns.remove(deviceId)?.cancel();
  }

  /// Starts a 60-second periodic that decrements the device's `timer`
  /// override. When it hits zero we flip `power` to off, push a real
  /// command to the Pi (so the physical relay actually shuts), and write
  /// an alert so the user sees the timer fired even if they were on
  /// another screen.
  void _startCountdown(String deviceId) {
    _countdowns[deviceId] = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _tick(deviceId),
    );
  }

  void _tick(String deviceId) {
    final current = Map<String, dynamic>.from(state[deviceId] ?? const {});
    final minutes = _readInt(current['timer']);
    if (minutes <= 0) {
      _cancelCountdown(deviceId);
      return;
    }
    final next = minutes - 1;
    current['timer'] = next.toString();
    if (next <= 0) {
      // Auto-off when the timer expires.
      current['power'] = 'off';
      _cancelCountdown(deviceId);
      _fireExpiry(deviceId);
    }
    state = {...state, deviceId: current};
  }

  /// Sends the real `power=off` command and writes a local alert when an
  /// oven timer hits zero. Best-effort — the device screen's polling will
  /// reconcile if the AWS call fails.
  void _fireExpiry(String deviceId) {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ??
            selectedHome?['id'] ??
            selectedHome?['homeid'])
        ?.toString() ??
        '';
    if (homeId.isNotEmpty) {
      ApiService.sendCommand(
        homeId: homeId,
        deviceId: deviceId,
        action: 'power',
        value: 'off',
      );
    }

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    ref.read(alertListProvider.notifier).addAlert(AlertItem(
          id: now.millisecondsSinceEpoch.toString(),
          title: 'Timer finished',
          description: 'The oven timer ran out and the device was turned off.',
          time: timeStr,
          type: AlertType.device,
          level: AlertLevel.info,
        ));
  }

  int _readInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

final deviceOverridesProvider = NotifierProvider<DeviceOverridesNotifier,
    Map<String, Map<String, dynamic>>>(DeviceOverridesNotifier.new);
