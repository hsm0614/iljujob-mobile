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
  /// 근로계약서: null(없음) · client_signed(알바생 서명 전) · signed · void
  final String? contractStatus;

  /// 카드가 제안된 시각(UTC). 서버는 proposed_at 을 UTC_TIMESTAMP() 로 쓰고
  /// wc.* 로 그대로 내려준다. 이걸 안 읽으면 카드를 대화 흐름에 끼워넣을
  /// 수 없어 항상 맨 아래로 밀린다.
  final DateTime? proposedAt;

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
    this.proposedAt,
    this.contractStatus,
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
    proposedAt: _parseUtc(j['proposed_at']),
    contractStatus: j['contract_status']?.toString(),
  );

  static DateTime? _parseUtc(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    // "2026-09-11 01:23:45"(MySQL) 과 ISO 둘 다 온다. 전자는 UTC 로 읽는다.
    final iso = s.contains('T') ? s : '${s.replaceFirst(' ', 'T')}Z';
    final dt = DateTime.tryParse(iso);
    return dt?.toLocal();
  }
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
    bool contract = false,
    Map<String, dynamic>? contractTerms, // 사장님이 미리보기에서 고친 업무 내용·휴게시간
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
        if (contract) 'contract': true,
        if (contract) ...?contractTerms,
      },
    );
    if (resp.statusCode == 201) {
      return jsonDecode(resp.body)['confirmId'] as int;
    }
    String msg = '근무 확정 제안 실패';
    String? code;
    try {
      final b = jsonDecode(resp.body) as Map;
      msg = b['message']?.toString() ?? msg;
      code = b['code']?.toString();
    } catch (_) {}
    throw WorkConfirmationException(msg, code: code);
  }

  static Future<void> updateStatus(
    int confirmId,
    String status, {
    String actorType = 'worker',
    bool signContract = false,
    String? identityImpUid, // 근로계약서 서명 직전 본인인증(다날)
  }) async {
    final resp = await AuthenticatedHttpClient.patchJson(
      Uri.parse('$baseUrl/api/work-confirmation/$confirmId/status'),
      body: {
        'status': status,
        'actorType': actorType,
        if (signContract) 'signContract': true,
        if (identityImpUid != null) 'identityImpUid': identityImpUid,
      },
    );
    if (resp.statusCode != 200) {
      String? msg;
      try {
        msg = (jsonDecode(resp.body) as Map)['message']?.toString();
      } catch (_) {}
      throw WorkConfirmationException(msg ?? '상태 업데이트 실패');
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

/// 서버가 알려준 이유(본인인증 불일치 등) — 화면에 그대로 보여준다
class WorkConfirmationException implements Exception {
  final String message;
  final String? code; // NEED_CONTRACT_PROFILE 등
  WorkConfirmationException(this.message, {this.code});
  @override
  String toString() => message;
}
