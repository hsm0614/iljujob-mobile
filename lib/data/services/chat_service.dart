// lib/data/services/chat_service.dart
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:iljujob/config/constants.dart';

Future<int?> startChatRoom(
  int workerId,
  String jobId,
  int clientId,
)
async {
  final url = Uri.parse('$baseUrl/api/job/start-chat');

  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'workerId': workerId,
        'jobId': jobId,
        'clientId': clientId,
      }),
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
