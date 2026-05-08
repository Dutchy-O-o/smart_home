import 'package:shared_preferences/shared_preferences.dart';

/// Process-wide owner of the currently signed-in user's identifier so any
/// service that persists data via SharedPreferences can scope its keys to
/// that user. Without this, two accounts on the same device share mood
/// history / scene slots / theme — which the user explicitly didn't want.
///
/// Usage:
///   - After login (or session restore), call [setUser] with the Cognito
///     `sub` (preferred) or another stable identifier.
///   - In services, build keys via `UserScope.key('mood_history_v1')`.
///   - On logout, call [clear] so the next user starts clean.
class UserScope {
  UserScope._();

  static const _activeUserKey = 'active_user_id';
  static String? _userId;

  static String? get currentUserId => _userId;

  /// Restore [_userId] from the previous session. Call once before any
  /// service tries to read scoped keys (e.g. from main()).
  static Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_activeUserKey);
    if (saved != null && saved.isNotEmpty) {
      _userId = saved;
    }
  }

  /// Set the active user. No-op if [userId] matches the current value.
  /// Persists to disk so [bootstrap] can restore on next launch.
  static Future<void> setUser(String? userId) async {
    if (_userId == userId) return;
    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    if (userId == null || userId.isEmpty) {
      await prefs.remove(_activeUserKey);
    } else {
      await prefs.setString(_activeUserKey, userId);
    }
  }

  /// Wipe the in-memory + persisted user id. Called on logout.
  static Future<void> clear() => setUser(null);

  /// Build a SharedPreferences key scoped to the current user. Falls back
  /// to the unscoped key when no user is set so unauthenticated paths
  /// (onboarding, login screens) keep working.
  static String key(String base) {
    final id = _userId;
    if (id == null || id.isEmpty) return base;
    return '${base}__u_$id';
  }

  /// One-time migration of legacy unscoped keys into the current user's
  /// scoped namespace. Without this, anyone who used the app before the
  /// scoping change would see their mood history / scene slots / alerts
  /// disappear after upgrading. Runs once per user (guarded by a flag),
  /// no-op if already done or if [_userId] is empty.
  ///
  /// Pass the list of legacy base keys you want migrated. We only copy
  /// when the unscoped value exists AND the scoped slot is currently
  /// empty, so we never overwrite fresh data.
  static Future<void> migrateLegacyKeys(List<String> baseKeys) async {
    final id = _userId;
    if (id == null || id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final flag = 'user_scope_migrated__u_$id';
    if (prefs.getBool(flag) == true) return;

    for (final base in baseKeys) {
      final scopedKey = '${base}__u_$id';
      if (prefs.containsKey(scopedKey)) continue;
      // Try string, list-string, and bool — covers every type the app
      // currently writes through SharedPreferences.
      if (prefs.containsKey(base)) {
        if (prefs.getString(base) != null) {
          await prefs.setString(scopedKey, prefs.getString(base)!);
        } else if (prefs.getStringList(base) != null) {
          await prefs.setStringList(scopedKey, prefs.getStringList(base)!);
        } else if (prefs.get(base) is bool) {
          await prefs.setBool(scopedKey, prefs.getBool(base)!);
        }
      }
    }
    await prefs.setBool(flag, true);
  }
}
