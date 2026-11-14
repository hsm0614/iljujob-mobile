import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android의 확인 가능한 첫 유입만 기기에 보관한다. 출처가 없으면 미상으로 둔다.
class AcquisitionService {
  static const _channel = MethodChannel('albailju/acquisition');
  static const _firstTouchKey = 'acquisition_first_touch_v1';
  static Future<void>? _installCapture;

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  static Map<String, String>? fromLink(Uri uri, {bool install = false}) {
    final params = uri.queryParameters;
    final src = params['src']?.trim().toLowerCase();
    final allowedSrc =
        src != null &&
        (const {
              'naver_app_ad',
              'google_ads',
              'sms_lead',
              'sms_openchat',
              'agency',
              'referral',
              'insta',
            }.contains(src) ||
            RegExp(r'^community_[a-z0-9_]{1,60}$').hasMatch(src));
    final utmSource = _safe(params['utm_source'], 100);
    final source = utmSource ?? (allowedSrc ? src : null);
    if (source == null) return null;
    final path =
        install
            ? '/play-install'
            : uri.host == 'job' && uri.pathSegments.isNotEmpty
            ? '/job/${uri.pathSegments.first}'
            : uri.path;
    return {
      'utm_source': source,
      if (_safe(params['utm_medium'], 100) case final medium?)
        'utm_medium': medium,
      if (_safe(params['utm_campaign'], 150) case final campaign?)
        'utm_campaign': campaign,
      'landing_path': path.length <= 200 && path.startsWith('/') ? path : '/',
    };
  }

  static String? _safe(String? raw, int max) {
    final value = raw?.trim().toLowerCase();
    if (value == null ||
        value.isEmpty ||
        value.length > max ||
        !RegExp(r'^[a-z0-9][a-z0-9_.-]*$').hasMatch(value)) {
      return null;
    }
    return value;
  }

  static Future<void> capturePlayInstallReferrer() {
    if (!_isAndroid) return Future.value();
    return _installCapture ??= _readPlayInstallReferrer();
  }

  static Future<void> _readPlayInstallReferrer() async {
    try {
      final raw = await _channel
          .invokeMethod<String>('getInstallReferrer')
          .timeout(const Duration(seconds: 3));
      if (raw == null || raw.isEmpty) return;
      final uri = Uri.tryParse(
        'https://play.invalid/?${raw.replaceFirst(RegExp(r'^\?'), '')}',
      );
      if (uri != null) await _store(fromLink(uri, install: true));
    } catch (_) {
      // Play Store가 없거나 응답이 없으면 출처를 추정하지 않는다.
    }
  }

  static Future<void> captureDeepLink(Uri uri) async {
    if (!_isAndroid || uri.scheme != 'albailju') return;
    await capturePlayInstallReferrer();
    await _store(fromLink(uri));
  }

  static Future<void> _store(Map<String, String>? acquisition) async {
    if (acquisition == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_firstTouchKey)) return;
    await prefs.setString(
      _firstTouchKey,
      Uri(queryParameters: acquisition).query,
    );
  }

  static Future<Map<String, String>?> forSignup() async {
    if (!_isAndroid) return null;
    await capturePlayInstallReferrer();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_firstTouchKey);
    if (raw == null) return null;
    return Uri.splitQueryString(raw);
  }
}
