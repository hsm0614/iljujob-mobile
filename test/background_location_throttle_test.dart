// 상시 위치는 10분에 한 번 또는 300m 이상 움직였을 때만 보낸다.
// 이걸 틀리면 배터리와 서버 쓰기가 몇십 배로 늘어난다.
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:iljujob/data/services/background_location_service.dart';

Position _at(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 20,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  test('처음 받은 위치는 보낸다', () {
    expect(BackgroundLocationService.shouldSendForTest(_at(37.5, 127.0)), isTrue);
  });

  test('방금 보냈고 제자리면 보내지 않는다', () {
    final sent = _at(37.5, 127.0);
    expect(
      BackgroundLocationService.shouldSendForTest(
        _at(37.5001, 127.0001), // 약 13m
        lastAt: DateTime.now(),
        lastPos: sent,
      ),
      isFalse,
    );
  });

  test('300m 넘게 움직이면 바로 보낸다', () {
    expect(
      BackgroundLocationService.shouldSendForTest(
        _at(37.5045, 127.0), // 약 500m
        lastAt: DateTime.now(),
        lastPos: _at(37.5, 127.0),
      ),
      isTrue,
    );
  });

  test('제자리라도 10분이 지나면 보낸다', () {
    expect(
      BackgroundLocationService.shouldSendForTest(
        _at(37.5, 127.0),
        lastAt: DateTime.now().subtract(const Duration(minutes: 11)),
        lastPos: _at(37.5, 127.0),
      ),
      isTrue,
    );
  });
}
