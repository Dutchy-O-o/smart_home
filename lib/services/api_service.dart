import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

class ApiService {
  static const String baseUrl = 'https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod';

  // Avoid spamming the same error while the network is down
  static bool _networkDown = false;

  static void _logNetworkError(String context, Object err) {
    final isNetwork = err is SocketException ||
        err.toString().contains('Failed host lookup') ||
        err.toString().contains('SocketException');
    if (isNetwork) {
      if (!_networkDown) {
        _networkDown = true;
        safePrint('[ApiService] Network unreachable — suppressing repeat errors until recovery. ($context)');
      }
      return; // spam yapma
    }
    // Always log non-network errors
    safePrint('[ApiService] $context: $err');
  }

  static void _markNetworkUp() {
    if (_networkDown) {
      _networkDown = false;
      safePrint('[ApiService] Network recovered.');
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
}
