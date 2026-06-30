import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClientTrackingService {
  static final ClientTrackingService _instance = ClientTrackingService._();
  static ClientTrackingService get instance => _instance;
  ClientTrackingService._();

  String? _baseUrl;
  int? _sessionId;
  DateTime? _sessionStart;

  void init(String baseUrl) => _baseUrl = baseUrl;

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

  void track(String eventType, {Map<String, dynamic>? properties}) {
    if (_baseUrl == null) return;
    unawaited(_sendEvent(eventType, properties: properties));
  }

  Future<void> _sendEvent(String eventType,
      {Map<String, dynamic>? properties}) async {
    try {
      final url = Uri.parse('$_baseUrl/api/tracking/event');
      await http
          .post(
            url,
            headers: await _headers(),
            body: jsonEncode({
              'event_type': eventType,
              if (properties != null) 'properties': properties,
              'platform': _platform,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
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
            body: jsonEncode({
              'platform': _platform,
              'app_version': version,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>?;
        _sessionId = (body?['sessionId'] as num?)?.toInt();
      }
    } catch (_) {}
  }

  Future<void> endSession() async {
    if (_baseUrl == null || _sessionId == null) return;
    try {
      final durationSec = _sessionStart != null
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
