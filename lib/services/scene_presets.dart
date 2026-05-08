import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';
import 'user_scope.dart';

/// One Quick-Access scene preset shown on the dashboard. Visual metadata
/// only — the actual device commands live in [_runScene] inside
/// dashboard_screen.dart, keyed by [key].
class ScenePreset {
  const ScenePreset({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.accent,
  });

  final String key;
  final String label;
  final String description;
  final IconData icon;
  final Color accent;
}

/// Catalog of all scenes the user can pick from. The first 4 are the
/// defaults shown out of the box; users can swap any slot via long-press.
class ScenePresets {
  static final List<ScenePreset> all = [
    const ScenePreset(
      key: 'all_off',
      label: 'All Off',
      description: 'Switch every device off',
      icon: Icons.power_settings_new,
      accent: AppColors.accentRed,
    ),
    const ScenePreset(
      key: 'movie',
      label: 'Movie',
      description: 'Dim warm · TV on · speakers off',
      icon: Icons.movie_creation,
      accent: Colors.deepPurpleAccent,
    ),
    ScenePreset(
      key: 'bright',
      label: 'Bright',
      description: 'Lights at full white',
      icon: Icons.wb_sunny,
      accent: Colors.amber.shade700,
    ),
    const ScenePreset(
      key: 'mood',
      label: 'Mood',
      description: 'AI emotion control',
      icon: Icons.palette,
      accent: Colors.pinkAccent,
    ),
    const ScenePreset(
      key: 'reading',
      label: 'Reading',
      description: 'Soft warm light at 60%',
      icon: Icons.menu_book,
      accent: Color(0xFFFFAB40),
    ),
    const ScenePreset(
      key: 'sleep',
      label: 'Sleep',
      description: 'Lights off, speakers off',
      icon: Icons.bedtime,
      accent: Color(0xFF7E57C2),
    ),
    const ScenePreset(
      key: 'party',
      label: 'Party',
      description: 'Vivid color, max brightness',
      icon: Icons.celebration,
      accent: Color(0xFFE040FB),
    ),
    const ScenePreset(
      key: 'romance',
      label: 'Romance',
      description: 'Pink dim · 30%',
      icon: Icons.favorite,
      accent: Color(0xFFE91E63),
    ),
  ];

  static const _defaultKeys = ['all_off', 'movie', 'bright', 'mood'];
  static const _baseStorageKey = 'scene_slots_v1';
  static String get _storageKey => UserScope.key(_baseStorageKey);

  static ScenePreset byKey(String key) =>
      all.firstWhere((p) => p.key == key, orElse: () => all.first);

  /// Returns the 4 user-chosen slot presets, falling back to defaults
  /// when the saved list is missing/short.
  static Future<List<ScenePreset>> loadSlots() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_storageKey);
    final keys = (saved != null && saved.length == 4) ? saved : _defaultKeys;
    return keys.map(byKey).toList();
  }

  static Future<void> saveSlot(int index, String key) async {
    if (index < 0 || index > 3) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_storageKey) ??
        List<String>.from(_defaultKeys);
    while (current.length < 4) {
      current.add(_defaultKeys[current.length]);
    }
    current[index] = key;
    await prefs.setStringList(_storageKey, current);
  }
}
