import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:iljujob/data/services/acquisition_service.dart';

/// 네이버 앱광고의 설치·인앱 전환을 제휴 MMP로 전송한다.
/// Dev Key는 공개 저장소에 넣지 않고 스토어 빌드의 dart-define으로 주입한다.
class AppsFlyerAttributionService {
  static const _devKey = String.fromEnvironment('APPSFLYER_DEV_KEY');
  static const _iosAppId = '6748399207';
  static final _sdk = AppsFlyerSdk.instance;
  static Future<void>? _initialization;

  static Future<void> initialize() => _initialization ??= _initialize();

  static Future<void> _initialize() async {
    if (_devKey.isEmpty) return;
    try {
      await _sdk.init(
        devKey: _devKey,
        appId: Platform.isIOS ? _iosAppId : null,
      );
      await _sdk.registerConversionListener(
        onConversionDataSuccess: (data) {
          unawaited(AcquisitionService.captureAppsFlyerInstall(data));
        },
      );
      await _sdk.registerSessionReadyListener(() async {
        try {
          await _sdk.start();
        } catch (error) {
          debugPrint('AppsFlyer 시작 실패: $error');
        }
      });
    } catch (error) {
      debugPrint('AppsFlyer 초기화 실패: $error');
    }
  }

  static Future<void> logEvent(
    String name, {
    Map<String, dynamic>? values,
  }) async {
    if (_devKey.isEmpty) return;
    await initialize();
    try {
      await _sdk.logEvent(name, eventValues: values);
    } catch (error) {
      debugPrint('AppsFlyer 이벤트 실패: $error');
    }
  }
}
