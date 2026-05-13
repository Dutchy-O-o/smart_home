import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

class ApiService {
  static const String baseUrl = 'https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod';

  // Avoid spamming the same error while the network is down
  static bool _networkDown = false;

  /// Broadcast stream of network reachability flips. UI layers (e.g. a
  /// global "Reconnecting…" banner) subscribe via the Riverpod provider
  /// in providers/network_status_provider.dart instead of polling.
  static final StreamController<bool> _networkStatusController =
      StreamController<bool>.broadcast();

  /// True when the last API call succeeded (or the app hasn't tried yet).
  /// Defaults to true so we don't flash an "offline" banner on cold start
  /// before any request has run.
  static bool get isOnline => !_networkDown;

  /// Subscribe to online/offline flips. Emits the new `isOnline` value.
  /// Stream is broadcast — multiple listeners (e.g. banner + retry queue)
  /// can subscribe without buffering history.
  static Stream<bool> get networkStatusStream =>
      _networkStatusController.stream;

  static void _logNetworkError(String context, Object err) {
    final isNetwork = err is SocketException ||
        err.toString().contains('Failed host lookup') ||
        err.toString().contains('SocketException');
    if (isNetwork) {
      if (!_networkDown) {
        _networkDown = true;
        safePrint('[ApiService] Network unreachable — suppressing repeat errors until recovery. ($context)');
        _networkStatusController.add(false);
      }
      return;
    }
    // Always log non-network errors
    safePrint('[ApiService] $context: $err');
  }

  static void _markNetworkUp() {
    if (_networkDown) {
      _networkDown = false;
      safePrint('[ApiService] Network recovered.');
      _networkStatusController.add(true);
    }
  }

  static Future<Map<String, String>> _getHeaders() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      if (session is CognitoAuthSession) {
        final token = session.userPoolTokensResult.value.idToken.raw;
        return {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        };
      }
    } catch (e) {
      safePrint('Error fetching Cognito session: $e');
    }
    return {'Content-Type': 'application/json'};
  }

  /// POST /prod/{homeID}/command
  static Future<bool> sendCommand({
    required String homeId,
    required String deviceId,
    required String action,
    required dynamic value,
  }) async {
    final url = Uri.parse('$baseUrl/$homeId/command');
    final headers = await _getHeaders();

    try {
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'deviceID': deviceId,
          'commands': [
            {
              'property_name': action,
              'value': value
            }
          ]
        }),
      );
      if (response.statusCode == 200) {
        _markNetworkUp();
        safePrint('Command sent successfully: $action -> $value');
        return true;
      } else {
        safePrint('Failed to send command. Status: ${response.statusCode}');
        safePrint('Response Body from AWS: ${response.body}');
        return false;
      }
    } catch (e) {
      _logNetworkError('sendCommand', e);
      return false;
    }
  }

  static Future<Map<String, dynamic>?> fetchSensors(String homeId) async {
    final url = Uri.parse('$baseUrl/$homeId/sensor');
    final headers = await _getHeaders();

    try {
      final response = await http.get(url, headers: headers);
      if (response.statusCode == 200) {
        _markNetworkUp();
        return jsonDecode(response.body);
      } else {
        safePrint('Failed to fetch sensors. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      _logNetworkError('fetchSensors', e);
      return null;
    }
  }

  /// GET /prod/{homeID}/devices
  static Future<List<dynamic>?> fetchDevices(String homeId) async {
    final url = Uri.parse('$baseUrl/$homeId/devices');
    final headers = await _getHeaders();

    try {
      final response = await http.get(url, headers: headers);
      if (response.statusCode == 200) {
        _markNetworkUp();
        final data = jsonDecode(response.body);
        return data['devices'] as List<dynamic>?;
      } else {
        safePrint('Failed to fetch devices. Status: ${response.statusCode}');
        safePrint('Response Body from AWS: ${response.body}');
        return null;
      }
    } catch (e) {
      _logNetworkError('fetchDevices', e);
      return null;
    }
  }

  /// GET /prod/{homeID}/automations
  static Future<List<dynamic>?> fetchAutomations(String homeId) async {
    final url = Uri.parse('$baseUrl/$homeId/automations');
    final headers = await _getHeaders();

    try {
      final response = await http.get(url, headers: headers);
      if (response.statusCode == 200) {
        _markNetworkUp();
        final data = jsonDecode(response.body);
        return data['automations'] as List<dynamic>?;
      } else {
        safePrint('Failed to fetch automations. Status: ${response.statusCode}');
        safePrint('Body: ${response.body}');
        return null;
      }
    } catch (e) {
      _logNetworkError('fetchAutomations', e);
      return null;
    }
  }

  /// GET /prod/{homeID}/automation-history
  static Future<List<dynamic>?> fetchAutomationHistory(String homeId) async {
    final url = Uri.parse('$baseUrl/$homeId/automation-history');
    final headers = await _getHeaders();

    try {
      final response = await http.get(url, headers: headers);
      if (response.statusCode == 200) {
        _markNetworkUp();
        final data = jsonDecode(response.body);
        return data['history'] as List<dynamic>?;
      } else {
        safePrint('Failed to fetch automation history. Status: ${response.statusCode}');
        safePrint('Body: ${response.body}');
        return null;
      }
    } catch (e) {
      _logNetworkError('fetchAutomationHistory', e);
      return null;
    }
  }

  /// POST /prod/{homeID}/automations
  static Future<bool> saveAutomation(String homeId, Map<String, dynamic> payload) async {
    final url = Uri.parse('$baseUrl/$homeId/automations');
    final headers = await _getHeaders();

    try {
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        _markNetworkUp();
        return true;
      } else {
        safePrint('Failed to save automation. Status: ${response.statusCode}');
        safePrint('Response Body: ${response.body}');
        return false;
      }
    } catch (e) {
      _logNetworkError('saveAutomation', e);
      return false;
    }
  }

  /// DELETE /prod/{homeID}/automations?rule_id={ruleId}
  static Future<bool> deleteAutomation(String homeId, String ruleId) async {
    final url = Uri.parse('$baseUrl/$homeId/automations').replace(
      queryParameters: {'rule_id': ruleId},
    );
    final headers = await _getHeaders();

    try {
      final response = await http.delete(url, headers: headers);

      if (response.statusCode == 200 || response.statusCode == 204) {
        _markNetworkUp();
        return true;
      } else {
        safePrint('Failed to delete automation. Status: ${response.statusCode}');
        safePrint('Response Body: ${response.body}');
        return false;
      }
    } catch (e) {
      _logNetworkError('deleteAutomation', e);
      return false;
    }
  }


  /// GET /prod/{homeID}/emotion
  static Future<Map<String, dynamic>?> fetchLatestEmotion(String homeId) async {
    final url = Uri.parse('$baseUrl/$homeId/emotion');
    final headers = await _getHeaders();

    try {
      final response = await http.get(url, headers: headers);
      if (response.statusCode == 200) {
        _markNetworkUp();
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      _logNetworkError('fetchLatestEmotion', e);
      return null;
    }
  }

  /// POST /prod/{homeID}/evaluate-emotion
  static Future<bool> evaluateEmotion(String homeId, String emotion, {double confidenceScore = 1.0}) async {
    final url = Uri.parse('$baseUrl/$homeId/evaluate-emotion');
    final headers = await _getHeaders();

    try {
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          "detected_emotion": emotion,
          "confidence_score": confidenceScore
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        _markNetworkUp();
        safePrint('Emotion evaluated successfully: $emotion');
        return true;
      } else {
        safePrint('Failed to evaluate emotion. Status: ${response.statusCode}');
        safePrint('Response Body: ${response.body}');
        return false;
      }
    } catch (e) {
      _logNetworkError('evaluateEmotion', e);
      return false;
    }
  }

  // ─── History endpoints ───────────────────────────────────────────
  // Each one returns null when the route isn't deployed yet (404), so
  // the caller can transparently fall back to its local cache.

  /// GET /prod/{homeID}/emotion-history?days=N
  /// Returns last [days] days of mood entries from `ai_analyses`.
  /// Shape: `{"entries": [{"emotion","confidence","timestamp"}, ...]}`
  static Future<List<Map<String, dynamic>>?> fetchMoodHistory(
      String homeId, {int days = 7}) async {
    final url = Uri.parse('$baseUrl/$homeId/emotion-history?days=$days');
    try {
      final res = await http.get(url, headers: await _getHeaders());
      if (res.statusCode == 200) {
        _markNetworkUp();
        final data = jsonDecode(res.body);
        return (data['entries'] as List?)?.cast<Map<String, dynamic>>();
      }
      if (res.statusCode == 404) return null; // not deployed yet
      _logNetworkError('fetchMoodHistory ${res.statusCode}', res.body);
      return null;
    } catch (e) {
      _logNetworkError('fetchMoodHistory', e);
      return null;
    }
  }

  /// GET /prod/{homeID}/sensor-history?hours=N
  /// Returns minute-bucketed sensor readings for the home over [hours].
  /// Shape: `{"readings": [{"timestamp","temperature","humidity"}, ...]}`
  static Future<List<Map<String, dynamic>>?> fetchSensorHistory(
      String homeId, {int hours = 12}) async {
    final url = Uri.parse('$baseUrl/$homeId/sensor-history?hours=$hours');
    try {
      final res = await http.get(url, headers: await _getHeaders());
      if (res.statusCode == 200) {
        _markNetworkUp();
        final data = jsonDecode(res.body);
        return (data['readings'] as List?)?.cast<Map<String, dynamic>>();
      }
      if (res.statusCode == 404) return null;
      _logNetworkError('fetchSensorHistory ${res.statusCode}', res.body);
      return null;
    } catch (e) {
      _logNetworkError('fetchSensorHistory', e);
      return null;
    }
  }

  /// POST /prod/{homeID}/alerts
  /// Persist an alert server-side so it survives across devices.
  /// Returns the new alert id, or null on failure.
  static Future<String?> postAlert({
    required String homeId,
    required String title,
    required String description,
    required String alertType, // 'security' | 'emotion' | 'device'
    required String alertLevel, // 'critical' | 'warning' | 'info'
  }) async {
    final url = Uri.parse('$baseUrl/$homeId/alerts');
    try {
      final res = await http.post(
        url,
        headers: await _getHeaders(),
        body: jsonEncode({
          'title': title,
          'description': description,
          'alert_type': alertType,
          'alert_level': alertLevel,
        }),
      );
      if (res.statusCode == 200) {
        _markNetworkUp();
        final data = jsonDecode(res.body);
        return data['alert_id']?.toString();
      }
      if (res.statusCode == 404) return null;
      _logNetworkError('postAlert ${res.statusCode}', res.body);
      return null;
    } catch (e) {
      _logNetworkError('postAlert', e);
      return null;
    }
  }

  /// GET /prod/{homeID}/alerts?limit=N
  /// Returns recent alerts for the calling user, newest first.
  static Future<List<Map<String, dynamic>>?> fetchAlerts(
      String homeId, {int limit = 50}) async {
    final url = Uri.parse('$baseUrl/$homeId/alerts?limit=$limit');
    try {
      final res = await http.get(url, headers: await _getHeaders());
      if (res.statusCode == 200) {
        _markNetworkUp();
        final data = jsonDecode(res.body);
        return (data['alerts'] as List?)?.cast<Map<String, dynamic>>();
      }
      if (res.statusCode == 404) return null;
      _logNetworkError('fetchAlerts ${res.statusCode}', res.body);
      return null;
    } catch (e) {
      _logNetworkError('fetchAlerts', e);
      return null;
    }
  }

  /// GET /prod/{homeID}/members
  ///
  /// Admin-only endpoint. Returns the list of users in a home with their
  /// roles + best-effort email/name from Cognito. Powers the Profile
  /// "Guest Management" screen.
  ///
  /// Returns:
  ///   - List of member maps on 200 success.
  ///   - `null` when the endpoint isn't deployed yet (404) or the caller
  ///     isn't an admin (403) — callers should show a friendly fallback.
  static Future<List<Map<String, dynamic>>?> fetchHomeMembers(String homeId) async {
    final url = Uri.parse('$baseUrl/$homeId/members');
    try {
      final res = await http.get(url, headers: await _getHeaders());
      if (res.statusCode == 200) {
        _markNetworkUp();
        final data = jsonDecode(res.body);
        return (data['members'] as List?)?.cast<Map<String, dynamic>>();
      }
      if (res.statusCode == 403 || res.statusCode == 404) return null;
      _logNetworkError('fetchHomeMembers ${res.statusCode}', res.body);
      return null;
    } catch (e) {
      _logNetworkError('fetchHomeMembers', e);
      return null;
    }
  }

  /// PATCH /prod/{homeID}/members/{userID}
  ///
  /// Admin-only: change a member's role (promote guest → admin, demote
  /// admin → guest). Backend refuses to demote the last admin (409).
  static Future<({bool success, String? errorMessage, String? newRole})>
      updateMemberRole({
    required String homeId,
    required String userId,
    required String newRole, // 'admin' or 'guest'
  }) async {
    final url = Uri.parse('$baseUrl/$homeId/members/$userId');
    try {
      final res = await http.patch(
        url,
        headers: await _getHeaders(),
        body: jsonEncode({'role': newRole}),
      );
      if (res.statusCode == 200) {
        _markNetworkUp();
        final body = jsonDecode(res.body);
        return (
          success: true,
          errorMessage: null,
          newRole: body['role']?.toString(),
        );
      }
      String? msg;
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['error'] is String) {
          msg = body['error'] as String;
        }
      } catch (_) {/* fall through */}
      _logNetworkError('updateMemberRole ${res.statusCode}', res.body);
      return (
        success: false,
        errorMessage: msg ?? 'Could not change role (HTTP ${res.statusCode}).',
        newRole: null,
      );
    } catch (e) {
      _logNetworkError('updateMemberRole', e);
      return (success: false, errorMessage: 'Network error.', newRole: null);
    }
  }

  /// DELETE /prod/{homeID}/leave
  ///
  /// User-driven counterpart to revokeGuestAccess: removes the caller's
  /// own membership from a home. The backend refuses to leave a home
  /// admin-less (409) — the user must promote someone first.
  static Future<({bool success, String? errorMessage})> leaveHome(
      String homeId) async {
    final url = Uri.parse('$baseUrl/$homeId/leave');
    try {
      final res = await http.delete(url, headers: await _getHeaders());
      if (res.statusCode == 200) {
        _markNetworkUp();
        return (success: true, errorMessage: null);
      }
      String? msg;
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['error'] is String) {
          msg = body['error'] as String;
        }
      } catch (_) {/* fall through */}
      _logNetworkError('leaveHome ${res.statusCode}', res.body);
      return (
        success: false,
        errorMessage: msg ?? 'Could not leave home (HTTP ${res.statusCode}).',
      );
    } catch (e) {
      _logNetworkError('leaveHome', e);
      return (success: false, errorMessage: 'Network error.');
    }
  }

  /// DELETE /prod/{homeID}/members/{userID}
  ///
  /// Admin-only endpoint. Removes a guest from a home. The backend refuses
  /// to delete other admins or the caller themselves — those return 403/400
  /// and we surface a friendly message via [errorMessage].
  ///
  /// Returns a `(success, errorMessage)` record. On success `errorMessage`
  /// is null; on failure the message is suitable for showing in a snackbar.
  static Future<({bool success, String? errorMessage})> revokeGuestAccess({
    required String homeId,
    required String userId,
  }) async {
    final url = Uri.parse('$baseUrl/$homeId/members/$userId');
    try {
      final res = await http.delete(url, headers: await _getHeaders());
      if (res.statusCode == 200) {
        _markNetworkUp();
        return (success: true, errorMessage: null);
      }
      // Surface server-side error messages so the UI can show specifics
      // ("Cannot remove another admin." / "User is not a member." etc).
      String? msg;
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['error'] is String) {
          msg = body['error'] as String;
        }
      } catch (_) {/* non-JSON body — fall through */}
      _logNetworkError('revokeGuestAccess ${res.statusCode}', res.body);
      return (
        success: false,
        errorMessage: msg ?? 'Could not remove member (HTTP ${res.statusCode}).',
      );
    } catch (e) {
      _logNetworkError('revokeGuestAccess', e);
      return (success: false, errorMessage: 'Network error.');
    }
  }
}
