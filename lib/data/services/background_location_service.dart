// 상시 위치 공유 — 구직자가 직접 켜는 기능.
//
// 왜: 지금까지 위치는 홈 화면을 열 때만 올라갔다. 앱을 닫으면 좌표가 그 시점에
// 멈춰서, 사장님의 긴급 호출 5km 후보가 몇 달 전 좌표로 뽑히기도 했다.
//
// 한계(정직하게): OS 가 허락하는 범위까지다.
//  · 안드로이드 — 포그라운드 서비스 알림이 떠 있는 동안 계속 받는다.
//  · iOS — 앱이 살아 있는 동안(백그라운드·잠금 포함) 받는다. 사용자가 앱을
//    강제 종료하면 멈춘다. 종료 후 자동 재시작은 geolocator 로는 안 된다.
//  · '항상 허용' 을 주지 않으면 켜지지 않는다. 안드로이드 11+ 는 설정 화면에서만 줄 수 있다.
//
// 서버 부하: 300m 이상 움직였을 때만, 그리고 10분에 한 번까지만 보낸다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/constants.dart';
import 'authenticated_http_client.dart';

class BackgroundLocationService {
  static const prefsKey = 'alwaysShareLocation';
  static const _minInterval = Duration(minutes: 10);
  static const _minDistanceM = 300;

  static StreamSubscription<Position>? _sub;
  static DateTime? _lastSentAt;
  static Position? _lastSentPos;

  static bool get isRunning => _sub != null;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) ?? false;
  }

  /// 앱 시작 시 호출. 켜둔 사람만 다시 흐름을 띄운다.
  static Future<void> resumeIfEnabled() async {
    if (!await isEnabled()) return;
    if (await Geolocator.checkPermission() != LocationPermission.always) return;
    await _start();
  }

  /// 켜기. '항상 허용' 을 못 받으면 false — 호출부가 설정 화면으로 안내한다.
  static Future<bool> enable() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    // whileInUse 상태에서 한 번 더 물으면 OS 가 '항상 허용' 을 띄운다(iOS).
    if (perm == LocationPermission.whileInUse) {
      perm = await Geolocator.requestPermission();
    }
    if (perm != LocationPermission.always) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, true);
    await _start();
    return true;
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, false);
    await _sub?.cancel();
    _sub = null;
    _lastSentAt = null;
    _lastSentPos = null;
  }

  static Future<void> _start() async {
    if (_sub != null) return;
    _sub = Geolocator.getPositionStream(locationSettings: _settings())
        .listen(_onPosition, onError: (e) => debugPrint('상시 위치 오류: $e'));
  }

  static LocationSettings _settings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: _minDistanceM,
        // 알림 없이 백그라운드 위치를 받으면 안드로이드가 몇 분 뒤 끊는다.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: '알바일주',
          notificationText: '내 주변 알바를 찾기 위해 위치를 확인하고 있어요',
          notificationChannelName: '상시 위치 공유',
          enableWakeLock: false,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: _minDistanceM,
        allowBackgroundLocationUpdates: true,
        // 멈춰 있으면 OS 가 알아서 쉬게 둔다 — 배터리 때문에 켠다.
        pauseLocationUpdatesAutomatically: true,
        activityType: ActivityType.other,
        showBackgroundLocationIndicator: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: _minDistanceM,
    );
  }

  static Future<void> _onPosition(Position pos) async {
    if (!_shouldSend(pos)) return;
    _lastSentAt = DateTime.now();
    _lastSentPos = pos;
    await _send(pos);
  }

  @visibleForTesting
  static bool shouldSendForTest(Position pos, {DateTime? lastAt, Position? lastPos}) {
    _lastSentAt = lastAt;
    _lastSentPos = lastPos;
    return _shouldSend(pos);
  }

  static bool _shouldSend(Position pos) {
    final last = _lastSentPos;
    final lastAt = _lastSentAt;
    if (last == null || lastAt == null) return true;
    if (DateTime.now().difference(lastAt) >= _minInterval) return true;
    return Geolocator.distanceBetween(
          last.latitude, last.longitude, pos.latitude, pos.longitude,
        ) >=
        _minDistanceM;
  }

  static Future<void> _send(Position pos) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    if (userId == null) return;
    try {
      await AuthenticatedHttpClient.patchJson(
        Uri.parse('$baseUrl/api/worker/update-location'),
        body: {
          'userId': userId,
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'source': 'background',
        },
      );
      await prefs.setDouble('currentLatitude', pos.latitude);
      await prefs.setDouble('currentLongitude', pos.longitude);
    } catch (e) {
      debugPrint('상시 위치 전송 실패: $e');
    }
  }
}
