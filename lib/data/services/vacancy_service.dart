import 'dart:convert';
import 'package:iljujob/config/constants.dart';
import 'authenticated_http_client.dart';

/// 결원 복구 (서버 /api/vacancy, 2026-11-11)
class VacancyService {
  /// 진행 중 복구가 있으면 {'recovery': {...}}, 없으면 {'origin','candidates','draft'}
  static Future<Map<String, dynamic>> forConfirmation(int confirmId) async {
    final r = await AuthenticatedHttpClient.get(Uri.parse('$baseUrl/api/vacancy/confirm/$confirmId'));
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) throw VacancyException(body['message']?.toString() ?? '불러오지 못했어요');
    return body;
  }

  static Future<int> send(int confirmId, List<int> workerIds, String message) async {
    final r = await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/vacancy/confirm/$confirmId/send'),
      body: {'workerIds': workerIds, 'message': message},
    );
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 201) throw VacancyException(body['message']?.toString() ?? '보내지 못했어요');
    return (body['sent'] as num?)?.toInt() ?? 0;
  }

  static Future<List<Map<String, dynamic>>> myOffers() async {
    final r = await AuthenticatedHttpClient.get(Uri.parse('$baseUrl/api/vacancy/offers/mine'));
    if (r.statusCode != 200) return [];
    return ((jsonDecode(r.body) as Map)['offers'] as List).cast<Map<String, dynamic>>();
  }

  /// 수락 성공 시 채팅방 id. 이미 마감이면 VacancyException
  static Future<int?> respond(int offerId, bool accept) async {
    final r = await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/vacancy/offers/$offerId/respond'),
      body: {'answer': accept ? 'accepted' : 'declined'},
    );
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) throw VacancyException(body['message']?.toString() ?? '처리하지 못했어요');
    return (body['chatRoomId'] as num?)?.toInt();
  }
}

class VacancyException implements Exception {
  final String message;
  VacancyException(this.message);
  @override
  String toString() => message;
}
