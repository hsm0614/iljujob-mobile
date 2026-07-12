import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/constants.dart';

class ScreenAnalyticsService {
  ScreenAnalyticsService._();
  static final ScreenAnalyticsService instance = ScreenAnalyticsService._();

  static const _dedupeWindow = Duration(minutes: 5);
  final Map<String, DateTime> _lastSentAt = {};

  Future<void> logScreenView(String screenName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('authToken') ?? prefs.getString('accessToken') ?? '';
      final userType = prefs.getString('userType') ?? 'unknown';
      if (token.isEmpty) return;

      final key = '$userType:$screenName';
      final now = DateTime.now();
      final last = _lastSentAt[key];
      if (last != null && now.difference(last) < _dedupeWindow) return;
      _lastSentAt[key] = now;

      await http
          .post(
            Uri.parse('$baseUrl/api/tracking/screen-view'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'screen_name': screenName,
              'user_type': userType,
              'platform': _platform,
            }),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // 화면 로그 실패는 UX에 영향을 주지 않습니다.
    }
  }

  String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'app_ios';
    if (Platform.isAndroid) return 'app_android';
    return 'app';
  }
}
