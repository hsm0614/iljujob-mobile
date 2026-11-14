import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iljujob/data/services/acquisition_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('허용된 src와 UTM을 읽고 출처 없는 설치는 미상으로 둔다', () {
    expect(
      AcquisitionService.fromLink(
        Uri.parse('albailju://job/123?src=naver_app_ad'),
      ),
      {'utm_source': 'naver_app_ad', 'landing_path': '/job/123'},
    );
    expect(
      AcquisitionService.fromLink(Uri.parse('albailju://job/123')),
      isNull,
    );
    expect(
      AcquisitionService.fromLink(Uri.parse('albailju://job/123?src=unknown')),
      isNull,
    );
    expect(
      AcquisitionService.fromLink(
        Uri.parse('https://play.invalid/?src=google_ads&utm_campaign=launch'),
        install: true,
      ),
      {
        'utm_source': 'google_ads',
        'utm_campaign': 'launch',
        'landing_path': '/play-install',
      },
    );
  });

  test('Play 설치 출처가 딥링크보다 먼저 저장되고 가입에 유지된다', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('albailju/acquisition');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => 'src=google_ads&utm_campaign=first',
        );
    try {
      await AcquisitionService.captureDeepLink(
        Uri.parse('albailju://job/123?src=naver_app_ad'),
      );
      expect(await AcquisitionService.forSignup(), {
        'utm_source': 'google_ads',
        'utm_campaign': 'first',
        'landing_path': '/play-install',
      });
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
