// promo_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/promo_model.dart'; // ← 파일명/경로 확인 (PromoConfig 정의 파일)
import 'package:flutter/foundation.dart';

class PromoService {
  final String baseUrl;
  PromoService(this.baseUrl);

  Future<PromoConfig?> fetchPromo({
    required String platform,
    required String userType,
    String? city,
  }) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final appVer = info.version;

      final prefs = await SharedPreferences.getInstance();
      const etagKey = 'promo_etag';
      const cacheKey = 'promo_cache';
      final cachedEtag = prefs.getString(etagKey);
      final cachedJson = prefs.getString(cacheKey);

      final uri = Uri.parse('$baseUrl/api/app/promo').replace(queryParameters: {
        'platform': platform,
        'appVer': appVer,
        'userType': userType,
        if (city != null) 'city': city,
      });

      // 캐시 없으면 If-None-Match 안 보냄
      final headers = <String, String>{
        if (cachedEtag != null && cachedJson != null) 'If-None-Match': cachedEtag,
      };

      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final raw = jsonDecode(resp.body);
        if (raw is Map) {
          final data = raw.cast<String, dynamic>();
          if (data['enabled'] == true) {
            await prefs.setString(cacheKey, resp.body);
            final et = resp.headers['etag'];
            if (et != null) await prefs.setString(etagKey, et);
            return PromoConfig.fromJson(data);
          }
        }
        return null;
      }

      if (resp.statusCode == 304) {
        // 캐시가 있으면 사용, 없으면 200으로 재시도
        if (cachedJson != null) {
          final raw = jsonDecode(cachedJson);
          if (raw is Map) {
            final data = raw.cast<String, dynamic>();
            return PromoConfig.fromJson(data);
          }
          return null;
        } else {
          final resp2 = await http.get(uri).timeout(const Duration(seconds: 8));
          if (resp2.statusCode == 200) {
            await prefs.setString(cacheKey, resp2.body);
            final et = resp2.headers['etag'];
            if (et != null) await prefs.setString(etagKey, et);

            final raw2 = jsonDecode(resp2.body);
            if (raw2 is Map && raw2['enabled'] == true) {
              final data2 = raw2.cast<String, dynamic>();
              return PromoConfig.fromJson(data2);
            }
          }
          return null;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> shouldShow(PromoConfig p) async {
    final now = DateTime.now();
    if (p.startAt != null && now.isBefore(p.startAt!)) return false;
    if (p.endAt != null && now.isAfter(p.endAt!)) return false;

    final prefs = await SharedPreferences.getInstance();
    final key = 'promo_hide_until_${p.id}';
    final hideUntil = prefs.getInt(key);
    if (hideUntil != null && now.millisecondsSinceEpoch < hideUntil) return false;
    return true;
  }

  // 🔽🔽🔽 여기! 클래스 "내부" 메서드로 정의해야 함
  Future<void> snooze(PromoConfig p) async {
    final prefs = await SharedPreferences.getInstance();
    // snoozeDays가 int(Non-nullable)이면 그대로 사용
    final until = DateTime.now()
        .add(Duration(days: p.snoozeDays))
        .millisecondsSinceEpoch;
    await prefs.setInt('promo_hide_until_${p.id}', until);

    // 서버에 기록 보내고 싶을 때 (선택)
    try {
      final uri = Uri.parse('$baseUrl/api/app/promo/snooze');
      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'promoId': p.id, 'until': until}),
      );
    } catch (e) {
    }
  }
}
