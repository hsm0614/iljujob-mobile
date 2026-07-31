import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/api_headers.dart';
import '../../config/constants.dart';

class AuthSessionExpiredException implements Exception {
  const AuthSessionExpiredException([this.message = '로그인이 필요합니다.']);

  final String message;

  @override
  String toString() => message;
}

class AuthenticatedHttpClient {
  const AuthenticatedHttpClient._();

  static Future<http.Response> get(Uri uri, {Map<String, String>? headers}) {
    return _sendWithRefresh(() async {
      final token = await _accessToken();
      return http.get(uri, headers: _headers(token, headers));
    });
  }

  static Future<http.Response> postJson(
    Uri uri, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) {
    return _sendWithRefresh(() async {
      final token = await _accessToken();
      return http.post(
        uri,
        headers: _headers(token, headers),
        body: jsonEncode(body ?? const <String, dynamic>{}),
      );
    });
  }

  static Future<http.Response> _sendWithRefresh(
    Future<http.Response> Function() request,
  ) async {
    var response = await request();
    if (response.statusCode != 401) return response;

    final refreshed = await refreshAccessToken();
    if (!refreshed) {
      await clearSession();
      throw const AuthSessionExpiredException();
    }

    response = await request();
    if (response.statusCode == 401) {
      await clearSession();
      throw const AuthSessionExpiredException();
    }
    return response;
  }

  static Future<bool> refreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refreshToken');
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/refresh-token'),
            headers: {...appHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final newToken = data['accessToken'] ?? data['token'];
      if (newToken is! String || newToken.isEmpty) return false;

      await prefs.setString('authToken', newToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static Future<String> _accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken') ?? '';
  }

  static Map<String, String> _headers(
    String token,
    Map<String, String>? headers,
  ) {
    return {...authHeaders(token), if (headers != null) ...headers};
  }
}
