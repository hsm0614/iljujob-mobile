import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

import '../../config/constants.dart';
import 'authenticated_http_client.dart';

class ScreenAnalyticsService {
  ScreenAnalyticsService._();
  static final ScreenAnalyticsService instance = ScreenAnalyticsService._();

  static const _dedupeWindow = Duration(minutes: 5);
  static const _uuid = Uuid();
  final Lock _deliveryLock = Lock();
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
  void logEvent(
    String eventName, {
    Map<String, Object?>? params,
    String? attemptId,
  }) {
    // fire-and-forget. 계측이 UX를 막으면 안 된다.
    final eventId = _uuid.v4();
    final occurredAt = DateTime.now().toUtc().toIso8601String();
    unawaited(
      _deliveryLock.synchronized(
        () => _sendEvent(eventName, params, eventId, attemptId, occurredAt),
      ),
    );
  }

  Future<void> _sendEvent(
    String eventName,
    Map<String, Object?>? params,
    String eventId,
    String? attemptId,
    String occurredAt,
  ) async {
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
        await _enqueue(eventName, params, eventId, attemptId, occurredAt);
        return;
      }

      await _flushQueue(token);
      await _post(token, eventName, params, eventId, attemptId, occurredAt);
    } catch (_) {
      try {
        await _enqueue(eventName, params, eventId, attemptId, occurredAt);
      } catch (_) {}
    }
  }

  Future<void> _post(
    String token,
    String eventName,
    Map<String, Object?>? params,
    String eventId,
    String? attemptId,
    String occurredAt,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/tracking/event'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'event_type': eventName,
            'event_id': eventId,
            if (attemptId != null) 'attempt_id': attemptId,
            if (params != null) 'properties': params,
            'platform': _platform,
            'occurred_at': occurredAt,
          }),
        )
        .timeout(const Duration(seconds: 3));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('tracking response ${response.statusCode}');
    }
  }

  // ── 로그인 이전 이벤트 큐 ──────────────────────────────
  // 무한정 쌓이면 안 되므로 상한을 둔다. 넘치면 오래된 것부터 버린다.
  static const _queueKey = 'analytics_pending_events';
  static const _queueMax = 50;

  Future<void> _enqueue(
    String eventName,
    Map<String, Object?>? params,
    String eventId,
    String? attemptId,
    String occurredAt,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_queueKey) ?? [];
    list.add(
      jsonEncode({
        'event_type': eventName,
        'event_id': eventId,
        if (attemptId != null) 'attempt_id': attemptId,
        if (params != null) 'properties': params,
        'occurred_at': occurredAt,
      }),
    );
    if (list.length > _queueMax) {
      list.removeRange(0, list.length - _queueMax);
    }
    await prefs.setStringList(_queueKey, list);
  }

  Future<void> _flushQueue(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_queueKey) ?? [];
    if (list.isEmpty) return;

    final remaining = <String>[];
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 7));
    // 복귀 직후 이벤트 하나가 오래된 대기열 50건에 막히지 않도록 10건만 처리한다.
    for (var i = 0; i < list.length && i < 10; i++) {
      final raw = list[i];
      try {
        final e = jsonDecode(raw) as Map<String, dynamic>;
        // 구버전 대기열은 ID가 없어 중복 방지가 불가능하다.
        final eventId = e['event_id']?.toString();
        final occurredAt = e['occurred_at']?.toString();
        final at = DateTime.tryParse(occurredAt ?? '');
        if (eventId == null || at == null || at.isBefore(cutoff)) continue;
        await _post(
          token,
          e['event_type'] as String,
          (e['properties'] as Map?)?.cast<String, Object?>(),
          eventId,
          e['attempt_id']?.toString(),
          occurredAt!,
        );
      } catch (_) {
        remaining.add(raw);
        remaining.addAll(list.skip(i + 1));
        break;
      }
    }
    if (list.length > 10 && remaining.isEmpty) remaining.addAll(list.skip(10));
    if (remaining.isEmpty) {
      await prefs.remove(_queueKey);
    } else {
      await prefs.setStringList(_queueKey, remaining);
    }
  }

  String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'app_ios';
    if (Platform.isAndroid) return 'app_android';
    return 'app';
  }
}
