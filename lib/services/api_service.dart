import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

class ApiService {
  static const String baseUrl = 'https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod';

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
        safePrint('Command sent successfully: $action -> $value');
        return true;
      } else {
        safePrint('Failed to send command. Status: ${response.statusCode}');
        safePrint('Response Body from AWS: ${response.body}');
        return false;
      }
    } catch (e) {
      safePrint('API connection error: $e');
      return false;
    }
  }

  /// GET /prod/{homeID}/sensor
  static Future<Map<String, dynamic>?> fetchSensors(String homeId) async {
    final url = Uri.parse('$baseUrl/$homeId/sensor');
    final headers = await _getHeaders();

    try {
      final response = await http.get(url, headers: headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        safePrint('Failed to fetch sensors. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      safePrint('API connection error: $e');
      return null;
    }
  }
}
