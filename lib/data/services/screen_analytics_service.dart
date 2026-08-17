import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/constants.dart';
import 'authenticated_http_client.dart';

class ScreenAnalyticsService {
  ScreenAnalyticsService._();
  static final ScreenAnalyticsService instance = ScreenAnalyticsService._();

  static const _dedupeWindow = Duration(minutes: 5);
  final Map<String, DateTime> _lastSentAt = {};

  Future<void> logScreenView(String screenName) async {
    // Firebase Analytics(GA4) 화면별 기록 — 토큰/로그인 무관하게 항상 전송.
    // (백엔드 app_screen_events는 아래에서 별도 처리)
    try {
      await FirebaseAnalytics.instance.logScreenView(screenName: screenName);
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = await AuthenticatedHttpClient.accessToken();
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

  /// 액션 이벤트. 화면 진입이 아니라 "무엇을 눌렀나/무슨 일이 일어났나".
  ///
  /// 화면뷰와 달리 중복 제거를 하지 않는다 — 같은 액션을 두 번 한 건
  /// 그 자체가 신호다(예: 지원 버튼을 두 번 누름 = 첫 시도 실패).
  ///
  /// 서버는 user_type을 토큰에서 직접 읽어 client_events에 저장한다.
  /// 구직자·사장님이 같은 테이블을 쓰므로 그 구분자가 필수다.
  void logEvent(String eventName, {Map<String, Object?>? params}) {
    // fire-and-forget. 계측이 UX를 막으면 안 된다.
    unawaited(_sendEvent(eventName, params));
  }

  Future<void> _sendEvent(String eventName, Map<String, Object?>? params) async {
    try {
      // Firebase는 num/String만 받는다. 나머지는 문자열로 눌러 담는다.
      final fbParams = <String, Object>{};
      params?.forEach((k, v) {
        if (v == null) return;
        fbParams[k] = (v is num || v is String) ? v : '$v';
      });
      await FirebaseAnalytics.instance.logEvent(
        name: eventName,
        parameters: fbParams.isEmpty ? null : fbParams,
      );
    } catch (_) {}

    try {
      final token = await AuthenticatedHttpClient.accessToken();

      // 토큰이 없으면 그냥 버리고 있었다. 그런데 가입 퍼널(worker_signup_*)은
      // 전부 계정이 생기기 전에 일어나서 30일간 서버에 2건밖에 안 쌓였다.
      // 큐에 담아두고 로그인 후 첫 이벤트에서 함께 올린다.
      // (GA4 쪽은 위에서 이미 토큰 없이 전송되므로 영향 없음)
      if (token.isEmpty) {
        await _enqueue(eventName, params);
        return;
      }

      await _flushQueue(token);
      await _post(token, eventName, params, null);
    } catch (_) {
      // 계측 실패는 조용히 넘긴다.
    }
  }

  Future<void> _post(
    String token,
    String eventName,
    Map<String, Object?>? params,
    String? occurredAt,
  ) async {
    await http
        .post(
          Uri.parse('$baseUrl/api/tracking/event'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'event_type': eventName,
            if (params != null) 'properties': params,
            'platform': _platform,
            if (occurredAt != null) 'occurred_at': occurredAt,
          }),
        )
        .timeout(const Duration(seconds: 3));
  }

  // ── 로그인 이전 이벤트 큐 ──────────────────────────────
  // 무한정 쌓이면 안 되므로 상한을 둔다. 넘치면 오래된 것부터 버린다.
  static const _queueKey = 'analytics_pending_events';
  static const _queueMax = 50;

  Future<void> _enqueue(String eventName, Map<String, Object?>? params) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_queueKey) ?? [];
    list.add(jsonEncode({
      'event_type': eventName,
      if (params != null) 'properties': params,
      // 실제 발생 시각. 나중에 올리므로 서버 수신 시각과 다르다.
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    }));
    if (list.length > _queueMax) {
      list.removeRange(0, list.length - _queueMax);
    }
    await prefs.setStringList(_queueKey, list);
  }

  Future<void> _flushQueue(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_queueKey) ?? [];
    if (list.isEmpty) return;

    // 먼저 비우고 보낸다. 전송 실패로 큐가 영원히 안 비는 상황을 막는다.
    await prefs.remove(_queueKey);
    for (final raw in list) {
      try {
        final e = jsonDecode(raw) as Map<String, dynamic>;
        await _post(
          token,
          e['event_type'] as String,
          (e['properties'] as Map?)?.cast<String, Object?>(),
          e['occurred_at'] as String?,
        );
      } catch (_) {}
    }
  }

  String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'app_ios';
    if (Platform.isAndroid) return 'app_android';
    return 'app';
  }
}
