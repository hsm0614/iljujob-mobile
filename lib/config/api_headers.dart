import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';

// 캐시 (앱 시작 시 1회만 조회)
String? _cachedVersion;
String? _cachedPlatform;

Future<void> initAppMeta() async {
  final info = await PackageInfo.fromPlatform();
  _cachedVersion  = info.version;          // e.g. '2.0.93'
  _cachedPlatform = Platform.isIOS ? 'ios' : 'android';
}

/// 모든 API 요청에 공통으로 붙이는 헤더
Map<String, String> get appHeaders => {
  if (_cachedVersion  != null) 'X-App-Version': _cachedVersion!,
  if (_cachedPlatform != null) 'X-Platform':    _cachedPlatform!,
};

/// 인증 헤더와 합산
Map<String, String> authHeaders(String? token) => {
  ...appHeaders,
  if (token != null && token.isNotEmpty)
    'Authorization': 'Bearer $token',
  'Content-Type': 'application/json',
};
