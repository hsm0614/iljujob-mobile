//lib/presentation/screens/post_job/post_job_controller.dart
import 'package:geolocator/geolocator.dart';

/// 위치 권한 및 현재 위치 받아오기
Future<Position?> getCurrentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
    }

    // 핵심: 명시적으로 AndroidSettings를 전달
    return await Geolocator.getCurrentPosition(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        forceLocationManager: true, // 여기선 이름이 바뀜!
      ),
    );
  } catch (e) {
    return null;
  }
}
