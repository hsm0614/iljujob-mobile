// 원더(wonder) 광고 배너 조회 + 이벤트 로깅 (ad_banners / ad_banner_events)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/constants.dart';
import '../models/ad_banner.dart';
import 'authenticated_http_client.dart';

class AdBannerService {
  static final AdBannerService _instance = AdBannerService._();
  static AdBannerService get instance => _instance;
  AdBannerService._();

  Future<Map<String, String>> _headers() async {
    final token = await AuthenticatedHttpClient.accessToken();
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'app_ios';
    if (Platform.isAndroid) return 'app_android';
    return 'web';
  }

  /// 활성 배너 목록 조회. 실패 시 빈 리스트 (배너 영역은 접힘)
  Future<List<AdBanner>> fetchBanners(String placement) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/api/banners',
      ).replace(queryParameters: {'placement': placement});
      final resp = await http
          .get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode != 200) return [];

      final body = jsonDecode(resp.body);
      final list = body is Map ? body['banners'] : null;
      if (list is! List) return [];

      return list
          .whereType<Map>()
          .map((e) => AdBanner.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 이벤트 기록 (impression / click) — fire-and-forget
  void logEvent(int bannerId, String eventType, String placement) {
    unawaited(_sendEvent(bannerId, eventType, placement));
  }

  /// 파트너 채용공고 '지원하기' 클릭 (landing_cta) — 배너 CTA와 같은 리포트에서 집계됨.
  /// 정산 대사 근거라 외부 링크 열기 전에 짧게 기다린다(실패해도 화면은 계속 진행).
  Future<void> logPartnerCta(String partnerCode, {String? placement}) async {
    try {
      await http
          .post(
            Uri.parse('$baseUrl/api/banners/partner-cta'),
            headers: await _headers(),
            body: jsonEncode({
              'partner_code': partnerCode,
              'placement': placement,
              'platform': _platform,
            }),
          )
          .timeout(const Duration(milliseconds: 1500));
    } catch (_) {}
  }

  Future<void> _sendEvent(
    int bannerId,
    String eventType,
    String placement,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/api/banners/$bannerId/event');
      await http
          .post(
            uri,
            headers: await _headers(),
            body: jsonEncode({
              'event_type': eventType,
              'placement': placement,
              'platform': _platform,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}
