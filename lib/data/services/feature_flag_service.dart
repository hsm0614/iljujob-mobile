// 피처 플래그 (feature_flags) — 2.0 롤백 인프라
//
// 앱에는 2.0 코드가 들어가 있고, 켜고 끄는 건 서버가 한다.
// 스토어 재배포 없이 되돌리기 위한 구조이므로, 새 기능 화면은 반드시
// FeatureFlags.instance.isOn('...') 로 감싼다.
//
// 실패 시 정책: 항상 false(꺼짐). 서버가 죽어도 1.0 동작에 영향이 없어야 한다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/constants.dart';
import 'authenticated_http_client.dart';

class FeatureFlags extends ChangeNotifier {
  static final FeatureFlags _instance = FeatureFlags._();
  static FeatureFlags get instance => _instance;
  FeatureFlags._();

  static const _prefsKey = 'feature_flags_cache';
  static const _refreshInterval = Duration(minutes: 5);

  Map<String, bool> _flags = {};
  DateTime? _lastFetch;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// 플래그 확인. 모르는 키·미로딩·서버 장애는 전부 false.
  bool isOn(String key) => _flags[key] == true;

  /// 앱 부팅 시 1회. 캐시를 먼저 올려 첫 프레임이 깜빡이지 않게 한다.
  Future<void> init() async {
    await _loadCache();
    _loaded = true;
    notifyListeners();
    unawaited(refresh());
  }

  /// 로그인·로그아웃 직후엔 주체가 바뀌므로 강제 갱신해야 한다.
  Future<void> refresh({bool force = false}) async {
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _refreshInterval) {
      return;
    }
    try {
      final token = await AuthenticatedHttpClient.accessToken();
      final resp = await http.get(
        Uri.parse('$baseUrl/api/feature-flags'),
        headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));

      if (resp.statusCode != 200) return;

      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      final raw = body is Map ? body['flags'] : null;
      if (raw is! Map) return;

      final next = <String, bool>{};
      raw.forEach((k, v) => next['$k'] = v == true);

      _lastFetch = DateTime.now();
      if (mapEquals(next, _flags)) return;

      _flags = next;
      await _saveCache();
      notifyListeners();
    } catch (_) {
      // 네트워크 실패는 조용히 무시. 직전 캐시를 그대로 쓴다.
    }
  }

  /// 로그아웃 시 호출 — 이전 사용자의 플래그가 남으면 안 된다.
  Future<void> clear() async {
    _flags = {};
    _lastFetch = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final next = <String, bool>{};
      decoded.forEach((k, v) => next['$k'] = v == true);
      _flags = next;
    } catch (_) {
      // 캐시가 깨졌으면 빈 상태로 시작한다 (= 전부 off)
    }
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_flags));
    } catch (_) {}
  }
}

/// 2.0 플래그 키 — 서버 feature_flags.flag_key 와 반드시 일치
class FF {
  static const longtermCheckin = 'longterm_checkin';
  static const checkout = 'checkout';
  static const workerBankAccount = 'worker_bank_account';
  static const workLedger = 'work_ledger';
  static const laborContract = 'labor_contract';
  static const paydayBadge = 'payday_badge';
  // ⚠️ 자금 — 화이트리스트로만 켠다
  static const wagePrepay = 'wage_prepay';
  static const wagePayout = 'wage_payout';
  static const autoApprove = 'auto_approve';
}
