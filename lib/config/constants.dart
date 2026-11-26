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
const String vworldApiKey = '6F9CB6D9-FF03-3CD5-8140-D33D84A59E24';
// ✅ 국세청 사업자등록 상태조회 API KEY
const String odCloudApiKeyEnc = "mzkQ7JJ9%2BK6GGApYVpbkfT15KKC1PIMcA4cmLmo0ZtgUKOYr%2FFekXGHmD3vdHd%2BtLHNwxY%2BsnjYhzkscBWS8Hg%3D%3D"; // URL 쿼리스트링에 사용
const String odCloudApiKeyDec = "mzkQ7JJ9+K6GGApYVpbkfT15KKC1PIMcA4cmLmo0ZtgUKOYr/FekXGHmD3vdHd+tLHNwxY+snjYhzkscBWS8Hg==";           // 보통 미사용

/// 카카오톡 채널(_xaJren) 1:1 채팅 — 공고 대행 접수 창구. 웹 `kakaoChatUrl`과 같이 /kakao?src=<자리>로 거쳐 자리별 클릭을 센다.
String kakaoChannelChatUrl(String src) => 'https://albailju.co.kr/kakao?src=$src';
