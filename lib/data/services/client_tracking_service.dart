import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';
import 'tracking_delivery_policy.dart';

class ClientTrackingService {
  static final ClientTrackingService _instance = ClientTrackingService._();
  static ClientTrackingService get instance => _instance;
  ClientTrackingService._();

  String? _baseUrl;
  int? _sessionId;
  DateTime? _sessionStart;
  String? _appVersion;
  final Lock _deliveryLock = Lock();
  static const Uuid _uuid = Uuid();

  void init(String baseUrl) {
    _baseUrl = baseUrl;
    unawaited(_loadAppVersion());
  }

  Future<void> _loadAppVersion() async {
    if (_appVersion != null) return;
    try {
      _appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
  }

  // ── 내부 유틸 ────────────────────────────────────────────────

  Future<Map<String, String>> _headers() async {
    final sp = await SharedPreferences.getInstance();
    final token = sp.getString('authToken');
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  // ── 이벤트 추적 (fire-and-forget) ───────────────────────────

  void track(
    String eventType, {
    Map<String, dynamic>? properties,
    String? attemptId,
    String? flowType,
  }) {
    if (_baseUrl == null) return;
    final eventId = _uuid.v4();
    final occurredAt = DateTime.now().toUtc().toIso8601String();
    unawaited(
      _deliveryLock.synchronized(
        () => _sendEvent(
          eventType,
          properties: properties,
          eventId: eventId,
          attemptId: attemptId,
          flowType: flowType,
          occurredAt: occurredAt,
        ),
      ),
    );
  }

  Future<void> _sendEvent(
    String eventType, {
    Map<String, dynamic>? properties,
    required String eventId,
    String? attemptId,
    String? flowType,
    required String occurredAt,
  }) async {
    // 밀린 게 있으면 먼저 올린다. 순서가 뒤집히면 퍼널 단계 간 소요시간이 음수가 된다.
    await _flushQueue();
    final delivery = await _post(
      eventType,
      properties,
      occurredAt,
      eventId: eventId,
      attemptId: attemptId,
      flowType: flowType,
    );
    if (delivery == TrackingDelivery.retry) {
      await _enqueue(
        eventType,
        properties,
        occurredAt,
        eventId: eventId,
        attemptId: attemptId,
        flowType: flowType,
      );
    }
  }

  Future<TrackingDelivery> _post(
    String eventType,
    Map<String, dynamic>? properties,
    String occurredAt, {
    required String eventId,
    String? attemptId,
    String? flowType,
  }) async {
    try {
      final r = await http
          .post(
            Uri.parse('$_baseUrl/api/tracking/event'),
            headers: await _headers(),
            body: jsonEncode({
              'event_type': eventType,
              'event_id': eventId,
              if (attemptId != null) 'attempt_id': attemptId,
              if (_sessionId != null) 'session_id': _sessionId,
              if (properties != null) 'properties': properties,
              'platform': _platform,
              if (_appVersion != null) 'app_version': _appVersion,
              if (flowType != null) 'flow_type': flowType,
              'occurred_at': occurredAt,
            }),
          )
          .timeout(const Duration(seconds: 5));
      final delivery = classifyTrackingResponse(r.statusCode);
      if (delivery == TrackingDelivery.dropInvalid && kDebugMode) {
        debugPrint(
          '[tracking] invalid event dropped: $eventType (${r.statusCode})',
        );
      }
      return delivery;
    } catch (_) {
      return TrackingDelivery.retry;
    }
  }

  // ── 실패한 이벤트 큐 ────────────────────────────────────────
  //
  // 예전엔 전송 실패를 그냥 삼켰다. 하필 네트워크가 나쁠 때 이벤트가 사라지는데,
  // 우리가 가장 알고 싶은 실패(느린 회선에서만 재현되는 버그)가 정확히 그 순간에
  // 일어난다. 실제로 퍼널에 job_post_schedule_complete(307) >
  // job_post_location_complete(301) 같은 불가능한 역전이 남아 있었다 — 유실의 흔적.
  static const _queueKey = 'client_tracking_pending';
  static const _queueMax = 100;
  static const _maxAge = Duration(days: 7); // 서버가 occurred_at 을 7일까지만 인정
  bool _flushing = false;
  DateTime? _lastFlush;
  // 회선이 계속 끊겨 있으면 track() 마다 큐 전체(최대 100건 × 5초)를 다시 시도하게
  // 된다. 이벤트 하나 보내려다 앱이 몇 분을 붙잡는 셈이라 간격을 둔다.
  static const _flushInterval = Duration(seconds: 30);

  Future<void> _enqueue(
    String eventType,
    Map<String, dynamic>? properties,
    String occurredAt, {
    required String eventId,
    String? attemptId,
    String? flowType,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_queueKey) ?? [];
      list.add(
        jsonEncode({
          'event_type': eventType,
          'event_id': eventId,
          if (attemptId != null) 'attempt_id': attemptId,
          if (flowType != null) 'flow_type': flowType,
          if (properties != null) 'properties': properties,
          'occurred_at': occurredAt,
        }),
      );
      // 넘치면 오래된 것부터 버린다 — 무한정 쌓이면 앱 저장소를 갉아먹는다.
      if (list.length > _queueMax) {
        list.removeRange(0, list.length - _queueMax);
      }
      await prefs.setStringList(_queueKey, list);
    } catch (_) {}
  }

  Future<void> _flushQueue({bool force = false}) async {
    if (_flushing) return;
    if (!force &&
        _lastFlush != null &&
        DateTime.now().difference(_lastFlush!) < _flushInterval) {
      return;
    }
    _flushing = true;
    _lastFlush = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_queueKey) ?? [];
      if (list.isEmpty) return;

      final cutoff = DateTime.now().toUtc().subtract(_maxAge);
      // 한 번에 20개까지만 보내 앱 복귀·이벤트 기록이 오래 묶이지 않게 한다.
      final batch = list.take(20).toList();
      final stillPending = <String>[...list.skip(20)];
      final deliveries = <Future<({String raw, TrackingDelivery delivery})>>[];
      for (final raw in batch) {
        Map<String, dynamic> e;
        try {
          e = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          continue; // 깨진 항목은 버린다
        }
        final at = DateTime.tryParse('${e['occurred_at']}');
        // 7일이 넘으면 서버가 발생 시각을 무시하므로 올려봐야 시간이 틀어진다.
        if (at == null || at.isBefore(cutoff)) continue;
        deliveries.add(
          _post(
            e['event_type'] as String,
            (e['properties'] as Map?)?.cast<String, dynamic>(),
            e['occurred_at'] as String,
            eventId: e['event_id']?.toString() ?? _uuid.v4(),
            attemptId: e['attempt_id']?.toString(),
            flowType: e['flow_type']?.toString(),
          ).then((delivery) => (raw: raw, delivery: delivery)),
        );
      }
      // 한 건씩 5초를 기다리면 최악 100초가 된다. 최대 20건을 함께 보내 한 번의
      // 타임아웃 안에 큐를 비우되, 저장 갱신은 아래에서 한 번만 수행한다.
      for (final result in await Future.wait(deliveries)) {
        if (result.delivery == TrackingDelivery.retry) {
          stillPending.add(result.raw);
        }
      }
      if (stillPending.isEmpty) {
        await prefs.remove(_queueKey);
      } else {
        await prefs.setStringList(_queueKey, stillPending);
      }
    } catch (_) {
    } finally {
      _flushing = false;
    }
  }

  // ── 세션 관리 ────────────────────────────────────────────────

  Future<void> startSession() async {
    if (_baseUrl == null) return;
    try {
      _sessionStart = DateTime.now();
      String? version;
      try {
        final info = await PackageInfo.fromPlatform();
        version = info.version;
      } catch (_) {}

      final url = Uri.parse('$_baseUrl/api/tracking/session/start');
      final r = await http
          .post(
            url,
            headers: await _headers(),
            body: jsonEncode({'platform': _platform, 'app_version': version}),
          )
          .timeout(const Duration(seconds: 5));

      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>?;
        _sessionId = (body?['sessionId'] as num?)?.toInt();
      }
    } catch (_) {}

    // 로그인 직후가 밀린 이벤트를 올릴 첫 기회다 — 401 로 큐에 남은 것들이 여기서 간다.
    await _deliveryLock.synchronized(() => _flushQueue(force: true));
  }

  Future<void> endSession() async {
    if (_baseUrl == null || _sessionId == null) return;
    try {
      final durationSec =
          _sessionStart != null
              ? DateTime.now().difference(_sessionStart!).inSeconds
              : null;

      final url = Uri.parse('$_baseUrl/api/tracking/session/end');
      await http
          .post(
            url,
            headers: await _headers(),
            body: jsonEncode({
              'session_id': _sessionId,
              'duration_sec': durationSec,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
    } finally {
      _sessionId = null;
      _sessionStart = null;
    }
  }
}
