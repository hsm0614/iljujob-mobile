import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

String getBaseUrl() {
  if (kIsWeb) {
    return 'https://albailju.co.kr';
  } else if (Platform.isAndroid || Platform.isIOS) {
    return 'https://albailju.co.kr'; // 배포 환경
  } else {
    return 'http://localhost:3000'; // 로컬 디버깅용
  }
}
final String baseUrl = getBaseUrl();