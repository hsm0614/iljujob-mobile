// lib/data/services/chat_service.dart
import 'dart:convert';
import 'package:iljujob/config/constants.dart';
import 'authenticated_http_client.dart';

Future<int?> startChatRoom(
  int workerId,
  String jobId,
  int clientId,
)
async {
  final url = Uri.parse('$baseUrl/api/job/start-chat');

  try {
    // 서버가 /api/job/start-chat에 본인 검증을 건다 — 토큰 없이 부르면 401이다
    final response = await AuthenticatedHttpClient.postJson(
      url,
      body: {'workerId': workerId, 'jobId': jobId, 'clientId': clientId},
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['roomId'];
    } else {
      print('❌ 채팅방 생성 실패: ${response.body}');
      return null;
    }
  } catch (e) {
    print('❌ 네트워크 오류: $e');
    return null;
  }
}
