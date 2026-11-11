import 'dart:convert';
import 'package:iljujob/config/constants.dart';
import 'authenticated_http_client.dart';

/// 일주 매니저 (서버 /api/agent, 2026-11-12)
class AgentService {
  static Future<Map<String, dynamic>> jobRescue(int jobId) async {
    final r = await AuthenticatedHttpClient.get(Uri.parse('$baseUrl/api/agent/job-rescue/$jobId'));
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) throw AgentException(body['message']?.toString() ?? '불러오지 못했어요');
    return body;
  }

  static Future<void> applyJobRescue(int jobId, {int? pay, String? description}) async {
    final r = await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/agent/job-rescue/$jobId/apply'),
      body: {if (pay != null) 'pay': pay, if (description != null) 'description': description},
    );
    if (r.statusCode != 200) {
      throw AgentException((jsonDecode(r.body) as Map)['message']?.toString() ?? '고치지 못했어요');
    }
  }
}

class AgentException implements Exception {
  final String message;
  AgentException(this.message);
  @override
  String toString() => message;
}
