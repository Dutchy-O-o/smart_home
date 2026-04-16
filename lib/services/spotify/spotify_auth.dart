import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'spotify_logger.dart';

/// OAuth 2.0 PKCE flow + access/refresh token lifecycle.
/// Exposes the auth header every other Spotify call needs.
class SpotifyAuth {
  static const String _authUrl = 'https://accounts.spotify.com/authorize';
  static const String _tokenUrl = 'https://accounts.spotify.com/api/token';
  static const String _redirectUri = 'akilliev://callback';

  static String get _clientId => dotenv.env['SPOTIFY_CLIENT_ID'] ?? '';
  static String get _clientSecret => dotenv.env['SPOTIFY_CLIENT_SECRET'] ?? '';

  static String? _accessToken;
  static String? _refreshToken;
  static DateTime? _tokenExpiry;

  static bool get isAuthenticated => _accessToken != null;

  /// Build the OAuth authorization URL (redirect the user to it).
  static String _buildAuthUrl() {
    final scopes = [
      'user-read-recently-played',
      'user-top-read',
      'user-read-playback-state',
      'user-modify-playback-state',
      'user-read-currently-playing',
      'playlist-read-private',
    ].join(' ');

    return '$_authUrl?'
        'client_id=$_clientId'
        '&response_type=code'
        '&redirect_uri=${Uri.encodeComponent(_redirectUri)}'
        '&scope=${Uri.encodeComponent(scopes)}'
        '&show_dialog=true';
  }

  /// One-shot login: open in-app browser → user signs in → capture code
  /// → exchange for tokens. Returns true if tokens were persisted.
  static Future<bool> login() async {
    try {
      final url = _buildAuthUrl();
      await SpotifyLogger.log('AUTH_URL_GENERATED', {'url': url});

      final result = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: 'akilliev',
      );

      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) {
        await SpotifyLogger.log('LOGIN_FAILED', {
          'error': 'No code in callback',
          'result': result,
        });
        return false;
      }

      return await exchangeCodeForToken(code);
    } catch (e) {
      await SpotifyLogger.log('LOGIN_ERROR', {'error': e.toString()});
      return false;
    }
  }

  /// Exchange an auth code captured from the redirect URL for tokens.
  static Future<bool> exchangeCodeForToken(String code) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$_clientId:$_clientSecret'))}',
        },
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': _redirectUri,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _refreshToken = data['refresh_token'];
        _tokenExpiry =
            DateTime.now().add(Duration(seconds: data['expires_in']));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('spotify_access_token', _accessToken!);
        await prefs.setString('spotify_refresh_token', _refreshToken!);
        await prefs.setString(
            'spotify_token_expiry', _tokenExpiry!.toIso8601String());

        await SpotifyLogger.log('TOKEN_EXCHANGE_SUCCESS', {
          'expires_in': data['expires_in'],
          'scope': data['scope'],
          'token_type': data['token_type'],
        });
        return true;
      }

      await SpotifyLogger.log('TOKEN_EXCHANGE_FAILED', {
        'status': response.statusCode,
        'body': response.body,
      });
      return false;
    } catch (e) {
      await SpotifyLogger.log('TOKEN_EXCHANGE_ERROR', {'error': e.toString()});
      return false;
    }
  }

  static Future<bool> _refreshAccessToken() async {
    if (_refreshToken == null) return false;
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$_clientId:$_clientSecret'))}',
        },
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken!,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _tokenExpiry =
            DateTime.now().add(Duration(seconds: data['expires_in']));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('spotify_access_token', _accessToken!);
        await prefs.setString(
            'spotify_token_expiry', _tokenExpiry!.toIso8601String());

        await SpotifyLogger.log(
            'TOKEN_REFRESH_SUCCESS', {'expires_in': data['expires_in']});
        return true;
      }
      return false;
    } catch (e) {
      await SpotifyLogger.log('TOKEN_REFRESH_ERROR', {'error': e.toString()});
      return false;
    }
  }

  /// Load tokens persisted from a previous session; refresh if expired.
  static Future<bool> loadSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('spotify_access_token');
    _refreshToken = prefs.getString('spotify_refresh_token');
    final expiryStr = prefs.getString('spotify_token_expiry');
    if (expiryStr != null) _tokenExpiry = DateTime.parse(expiryStr);

    if (_accessToken != null && _tokenExpiry != null) {
      if (_tokenExpiry!.isBefore(DateTime.now())) {
        return await _refreshAccessToken();
      }
      return true;
    }
    return false;
  }

  /// Authorization header for API calls. Refreshes the token silently if
  /// expired. Returns null if the user isn't logged in.
  static Future<Map<String, String>?> getHeaders() async {
    if (_accessToken == null) return null;
    if (_tokenExpiry != null && _tokenExpiry!.isBefore(DateTime.now())) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) return null;
    }
    return {
      'Authorization': 'Bearer $_accessToken',
      'Content-Type': 'application/json',
    };
  }

  /// Clear in-memory and persisted tokens (logout).
  static Future<void> disconnect() async {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('spotify_access_token');
    await prefs.remove('spotify_refresh_token');
    await prefs.remove('spotify_token_expiry');
    await SpotifyLogger.log('DISCONNECTED', {'message': 'tokens cleared'});
  }

  /// Useful for dev/test to confirm env is wired.
  static bool get hasClientId => _clientId.isNotEmpty;
  static bool get hasClientSecret => _clientSecret.isNotEmpty;

  // Keep debugPrint wired so nothing changes when called during login.
  // ignore: unused_element
  static void _debug(String s) => debugPrint('[SpotifyAuth] $s');
}
