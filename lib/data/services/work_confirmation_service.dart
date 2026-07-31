import 'dart:convert';
import 'package:iljujob/config/constants.dart';
import 'authenticated_http_client.dart';

class WorkConfirmation {
  final int id;
  final int chatRoomId;
  final int jobId;
  final int workerId;
  final int clientId;
  final String workDate;
  final String startTime;
  final String endTime;
  final int hourlyWage;
  final String? location;
  final String status;
  final String? workerName;
  final String? companyName;

  const WorkConfirmation({
    required this.id,
    required this.chatRoomId,
    required this.jobId,
    required this.workerId,
    required this.clientId,
    required this.workDate,
    required this.startTime,
    required this.endTime,
    required this.hourlyWage,
    this.location,
    required this.status,
    this.workerName,
    this.companyName,
  });

  factory WorkConfirmation.fromJson(Map<String, dynamic> j) => WorkConfirmation(
    id: j['id'] as int,
    chatRoomId: j['chat_room_id'] as int,
    jobId: j['job_id'] as int,
    workerId: j['worker_id'] as int,
    clientId: j['client_id'] as int,
    workDate: j['work_date']?.toString() ?? '',
    startTime: j['start_time']?.toString() ?? '',
    endTime: j['end_time']?.toString() ?? '',
    hourlyWage: (j['hourly_wage'] as num?)?.toInt() ?? 0,
    location: j['location']?.toString(),
    status: j['status']?.toString() ?? 'proposed',
    workerName: j['worker_name']?.toString(),
    companyName: j['company_name']?.toString(),
  );
}

class WorkConfirmationService {
  static Future<int> propose({
    required int chatRoomId,
    required int jobId,
    required int workerId,
    required int clientId,
    required String workDate,
    required String startTime,
    required String endTime,
    required int hourlyWage,
    String? location,
  }) async {
    final resp = await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/work-confirmation'),
      body: {
        'chatRoomId': chatRoomId,
        'jobId': jobId,
        'workerId': workerId,
        'clientId': clientId,
        'workDate': workDate,
        'startTime': startTime,
        'endTime': endTime,
        'hourlyWage': hourlyWage,
        'location': location,
      },
    );
    if (resp.statusCode == 201) {
      return jsonDecode(resp.body)['confirmId'] as int;
    }
    throw Exception('근무 확정 제안 실패: ${resp.body}');
  }

  static Future<void> updateStatus(
    int confirmId,
    String status, {
    String actorType = 'worker',
  }) async {
    final resp = await AuthenticatedHttpClient.patchJson(
      Uri.parse('$baseUrl/api/work-confirmation/$confirmId/status'),
      body: {'status': status, 'actorType': actorType},
    );
    if (resp.statusCode != 200) {
      throw Exception('상태 업데이트 실패: ${resp.body}');
    }
  }

  static Future<List<WorkConfirmation>> getByRoom(int chatRoomId) async {
    final resp = await AuthenticatedHttpClient.get(
      Uri.parse('$baseUrl/api/work-confirmation/room/$chatRoomId'),
    );
    if (resp.statusCode == 200) {
      final list = jsonDecode(resp.body) as List;
      return list
          .map((e) => WorkConfirmation.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }
}
