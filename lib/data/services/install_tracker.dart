import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../config/constants.dart';
import 'acquisition_service.dart';
import 'authenticated_http_client.dart';

/// 앱 첫 실행을 기기 id + 첫 유입과 함께 서버(app_installs)에 남기고, 로그인 상태면 계정에 잇는다.
/// 설치했지만 가입 안 한 사람의 출처, 출처별 설치→가입 전환을 보려고(2026-11-23). 실패해도 앱을 막지 않는다.
class InstallTracker {
  static const _key = 'install_id_v1';

  static Future<void> report() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_key);
      if (id == null) {
        id = const Uuid().v4();
        await prefs.setString(_key, id);
      }
      final acq = await AcquisitionService.forSignup();
      await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/tracking/install'),
        body: {
          'install_id': id,
          'platform': Platform.isIOS ? 'app_ios' : 'app_android',
          if (acq != null) 'acquisition': acq,
        },
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}
