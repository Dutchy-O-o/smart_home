import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/user_scope.dart';

/// Persisted application theme mode.
/// Stored as a short string ('system' | 'light' | 'dark') in SharedPreferences
/// under [_storageKey] so the choice survives app restarts.
class ThemeNotifier extends Notifier<ThemeMode> {
  static const _baseStorageKey = 'theme_mode_v1';
  static String get _storageKey => UserScope.key(_baseStorageKey);

  @override
  ThemeMode build() {
    // Default to system on first launch — the previous behavior was to
    // hard-code dark, which surprised users on light-mode devices. The
    // saved value is restored asynchronously below.
    _restore();
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    if (saved == null) return;
    switch (saved) {
      case 'light':
        state = ThemeMode.light;
        break;
      case 'dark':
        state = ThemeMode.dark;
        break;
      default:
        state = ThemeMode.system;
    }
  }

  Future<void> _persist(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, mode.name);
  }

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _persist(state);
  }

  void setMode(ThemeMode mode) {
    state = mode;
    _persist(mode);
  }

  bool get isDark => state == ThemeMode.dark;
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);
