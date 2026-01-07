// lib/data/services/ai_api.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiApi {
  final String base;
  final Duration timeout;
  AiApi(this.base, {this.timeout = const Duration(seconds: 12)});

  // ---------------------------
  
  // 내부 공통 유틸
  // ---------------------------
  Future<Map<String, String>> _headersJson() async {
    final sp = await SharedPreferences.getInstance();
    final token = sp.getString('authToken');
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  T _decode<T>(http.Response r) {
    final text = utf8.decode(r.bodyBytes);
    final obj = text.isEmpty ? null : jsonDecode(text);
    return obj as T;
  }
Future<Map<String, dynamic>?> fetchChatDetail(int chatRoomId) async {
  final url = Uri.parse('$base/api/chat/detail/$chatRoomId');
  final r = await _get(url);
  if (r.statusCode != 200) return null;
  final decoded = _decode<dynamic>(r);
  if (decoded is Map<String, dynamic>) return decoded;
  return null;
}
  Future<http.Response> _get(Uri url) async {
    try {
      return await http.get(url, headers: await _headersJson()).timeout(timeout);
    } on TimeoutException {
      throw '요청 시간이 초과되었습니다.';
    } on SocketException {
      throw '네트워크 연결을 확인해주세요.';
    }
  }
Future<ConsentResult> consentDecision({
  required int roomId,
  required bool accept,
}) async {
  final url = Uri.parse('$base/api/chat/consent');
  final body = {
    'roomId': roomId,
    'action': accept ? 'accept' : 'decline',
  };
  final r = await _post(url, body);
  final text = utf8.decode(r.bodyBytes);

  try {
    final m = text.isEmpty ? {} : jsonDecode(text);
    if (m is Map) return ConsentResult.fromJson(m);
    return ConsentResult(ok: r.statusCode >= 200 && r.statusCode < 300);
  } catch (_) {
    return ConsentResult(
      ok: r.statusCode >= 200 && r.statusCode < 300,
      message: r.statusCode >= 200 && r.statusCode < 300
          ? null
          : '요청 실패 (${r.statusCode})',
    );
  }
}
  Future<http.Response> _post(Uri url, Map<String, dynamic> body) async {
    try {
      return await http
          .post(url, headers: await _headersJson(), body: jsonEncode(body))
          .timeout(timeout);
    } on TimeoutException {
      throw '요청 시간이 초과되었습니다.';
    } on SocketException {
      throw '네트워크 연결을 확인해주세요.';
    }
  }

  // list 응답을 안전하게 꺼내기: {items: []} | []
List _asList(dynamic decoded) {
  if (decoded is List) return decoded;

  if (decoded is Map) {
    if (decoded['items'] is List) return decoded['items'] as List;
    if (decoded['data'] is List) return decoded['data'] as List;
    if (decoded['workers'] is List) return decoded['workers'] as List;
  }

  return const [];
}
  Map<String, dynamic> _asMap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return const {};
  }

  // ---------------------------
  // 기존 메서드(시그니처 유지)
  // ---------------------------

  Future<List<dynamic>> fetchRecommended(int workerId, {int limit = 20}) async {
    final url = Uri.parse('$base/api/rank/jobs?workerId=$workerId&limit=$limit');
    final r = await _get(url);
    if (r.statusCode != 200) return [];
    final decoded = _decode<dynamic>(r);
    return _asList(decoded);
  }

  Future<void> logEvent(int userId, int jobId, String type, {Map<String, dynamic>? ctx}) async {
    final url = Uri.parse('$base/api/ai-events');
    // 실패해도 흐름 끊지 않도록 fire-and-forget 스타일 (에러 무시)
    try {
      await _post(url, {'user_id': userId, 'job_id': jobId, 'event_type': type, 'context': ctx});
    } catch (_) {}
  }

Future<List<dynamic>> fetchCandidatesForJob(int jobId, {int limit = 50}) async {
  final url = Uri.parse('$base/api/target/workers?jobId=$jobId&limit=$limit');
  final r = await _get(url);
  if (r.statusCode != 200) return [];

  final decoded = _decode<dynamic>(r);
  final list = _asList(decoded);

  // 🔥 여기서 서버 응답을 정규화해서 name / photoUrl / workerId를 강제로 붙여줌
  return list.map((e) {
    if (e is! Map) return e;
    final m = Map<String, dynamic>.from(e as Map);

    // workerId 추출 (worker_id / workerId / id 아무거나)
    final rawId = m['worker_id'] ?? m['workerId'] ?? m['id'];
    int? workerId;
    if (rawId is num) {
      workerId = rawId.toInt();
    } else if (rawId is String) {
      workerId = int.tryParse(rawId);
    }

    // 이름 / 프로필 이미지 여러 키에 대응
    final rawName = (m['name'] ?? m['worker_name'] ?? m['user_name']);
    final rawPhoto = (m['photo_url'] ??
        m['thumbnail_url'] ??
        m['photoUrl'] ??
        m['thumbnailUrl']);

    return {
      ...m,
      if (workerId != null) 'workerId': workerId,
      if (rawName != null) 'name': rawName.toString(),
      if (rawPhoto != null) 'photoUrl': rawPhoto.toString(),
    };
  }).toList();
}


  /// 인재 간략 프로필 배치 조회 (이름/사진 등)
   Future<Map<int, Map<String, dynamic>>> fetchWorkerBriefBatch(List<int> ids) async {
  if (ids.isEmpty) return {};
  final url = Uri.parse('$base/api/worker/brief-batch');

 
  final r = await _post(url, {'ids': ids});

 

  if (r.statusCode != 200) return {};

  final decoded = _decode<dynamic>(r);
  final list = _asList(decoded);

  final out = <int, Map<String, dynamic>>{};
  for (final e in list) {
    if (e is Map) {
      final m = Map<String, dynamic>.from(e);
      final id = (m['id'] as num?)?.toInt();
      if (id != null) out[id] = m;
    }
  }
  
  return out;
}
  /// 공고 상세를 다양한 응답 모양에서 안전하게 파싱해 Map<String,dynamic>으로 반환
  Future<Map<String, dynamic>?> fetchJobDetailRaw(int jobId) async {
    final candidates = <Uri>[
      Uri.parse('$base/api/job/jobs/$jobId'),
      Uri.parse('$base/api/job/detail?jobId=$jobId'),
      Uri.parse('$base/api/job/detail?id=$jobId'),
      Uri.parse('$base/api/job/$jobId'),
      Uri.parse('$base/api/jobs/$jobId'),
    ];

    for (final url in candidates) {
      try {
        final r = await _get(url);
        if (r.statusCode != 200) continue;
        final decoded = _decode<dynamic>(r);

        Map<String, dynamic>? obj;
        if (decoded is Map) {
          final root = Map<String, dynamic>.from(decoded);
          if (root['job'] is Map) {
            obj = Map<String, dynamic>.from(root['job'] as Map);
          } else if (root['data'] is Map) {
            obj = Map<String, dynamic>.from(root['data'] as Map);
          } else if (root['item'] is Map) {
            obj = Map<String, dynamic>.from(root['item'] as Map);
          } else {
            obj = root;
          }
        } else {
          continue;
        }
        if (obj.isEmpty) continue;

        // 키 정규화
        obj = Map<String, dynamic>.from(obj);
        if (obj['id'] == null && obj['jobId'] != null) {
          obj['id'] = obj['jobId'].toString();
        }
        if (obj['pay'] != null && obj['pay'] is num) {
          obj['pay'] = (obj['pay'] as num).toString();
        }
        if (obj['title'] == null && obj['name'] != null) {
          obj['title'] = obj['name'];
        }
        return obj;
      } catch (_) {
        // 다음 후보 시도
      }
    }
    return null;
  }

  // ---------------------------
  // 신규 추가
  // ---------------------------

  /// 배치 상태 조회 (하이드레이션용)
  /// 서버 응답 예시: { items: [ {workerId: 10, roomId: 123, status: "pending"}, ... ] }
  Future<List<Map<String, dynamic>>> fetchChatStatusBatch({
    required int jobId,
    required int clientId,
    required List<int> workerIds,
  }) async {
    if (workerIds.isEmpty) return const [];
    final url = Uri.parse('$base/api/chat/status-batch');
    final r = await _post(url, {
      'jobId': jobId,
      'clientId': clientId,
      'workerIds': workerIds,
    });
    if (r.statusCode != 200) return const [];
    final decoded = _decode<dynamic>(r);
    final list = _asList(decoded);
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// 클라이언트가 먼저 채팅 요청 (초대)
  Future<RequestChatResult> requestChatFromClient({
    required int workerId,
    required int jobId,
    String? openerMessage,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final clientId = sp.getInt('userId');      // 로그인 시 저장한 clientId
    final userType = sp.getString('userType'); // 'client' 기대

    if (userType != 'client' || clientId == null) {
      return RequestChatResult(ok: false, message: '클라이언트 계정으로 로그인하세요.');
    }

    final url = Uri.parse('$base/api/chat/request');
    final r = await _post(url, {
      'workerId': workerId,
      'jobId': jobId,
      'clientId': clientId, // 서버에서 body.clientId로 소유권 확인
      'openerMessage': openerMessage ?? '안녕하세요! 일자리 관련해서 대화 요청드립니다.',
    });

    // 2xx → fromJson, 그 외 → 에러 메시지 파싱
    if (r.statusCode >= 200 && r.statusCode < 300) {
      final decoded = _decode<dynamic>(r);
      final map = _asMap(decoded);
      if (map.isNotEmpty) {
        return RequestChatResult.fromJson(map);
      }
      return RequestChatResult(ok: true);
    } else {
      try {
        final decoded = _decode<dynamic>(r);
        final map = _asMap(decoded);
        final msg = map['message']?.toString();
        return RequestChatResult(ok: false, message: msg ?? '요청 실패 (${r.statusCode})');
      } catch (_) {
        return RequestChatResult(ok: false, message: '요청 실패 (${r.statusCode})');
      }
    }
  }
}
extension SubscriptionApi on AiApi {
  // 날짜 파서(ISO8601, MySQL DATETIME, epoch(ms)까지 모두 수용)
  DateTime? _parseDateLoose(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // epoch millis 숫자 문자열
    if (RegExp(r'^\d{11,}$').hasMatch(s)) {
      final ms = int.tryParse(s);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }

    // MySQL DATETIME → ISO 보정
    final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');

    try {
      return DateTime.parse(normalized).toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<SubscriptionStatus> fetchMySubscription() async {
    final sp = await SharedPreferences.getInstance();
    final jwt = sp.getString('authToken');          // ← 너희가 저장한 토큰 키명 확인
    final clientId = sp.getInt('userId');

    // 1) 전용 엔드포인트 우선 (서버에서 이미 만들어둔 /api/subscription/status)
    try {
      final r = await http.get(
        Uri.parse('$base/api/subscription/status'),
        headers: {
          'Content-Type': 'application/json',
          if (jwt != null && jwt.isNotEmpty) 'Authorization': 'Bearer $jwt',
        },
      ).timeout(timeout);

      // 디버깅에 도움
      // ignore: avoid_print
      print('GET /subscription/status -> ${r.statusCode} ${r.body}');

      if (r.statusCode == 200) {
        final m = jsonDecode(utf8.decode(r.bodyBytes));
        if (m is Map) {
          final active = m['active'] == true;
          final plan = m['plan']?.toString();
          final expiresAt = _parseDateLoose(m['expiresAt']);
          return SubscriptionStatus(active: active, plan: plan, expiresAt: expiresAt);
        }
      }
    } catch (_) {
      // 무시하고 폴백
    }

    // 2) 폴백: /api/client/:id (응답 형태가 제각각일 수 있으니 방어적으로 파싱)
    if (clientId == null) return const SubscriptionStatus(active: false);

    try {
      final r = await _get(Uri.parse('$base/api/client/$clientId'));
      if (r.statusCode != 200) return const SubscriptionStatus(active: false);

      final data = jsonDecode(utf8.decode(r.bodyBytes));

      // 최상위 or 중첩(client, data 등)에서 꺼내기
      Map obj;
      if (data is Map && data['client'] is Map) {
        obj = data['client'] as Map;
      } else if (data is Map && data['data'] is Map) {
        obj = data['data'] as Map;
      } else if (data is Map) {
        obj = data;
      } else {
        return const SubscriptionStatus(active: false);
      }

      final plan = (obj['subscription_plan'] ?? obj['subscriptionPlan'])?.toString();
      final expiresRaw = obj['subscription_expires_at'] ?? obj['subscriptionExpiresAt'];
      final expiresAt = _parseDateLoose(expiresRaw);
      final active = expiresAt != null && expiresAt.isAfter(DateTime.now());

      return SubscriptionStatus(active: active, plan: plan, expiresAt: expiresAt);
    } catch (_) {
      return const SubscriptionStatus(active: false);
    }
  }
}

class SubscriptionStatus {
  final bool active;
  final String? plan;
  final DateTime? expiresAt;
  const SubscriptionStatus({required this.active, this.plan, this.expiresAt});
}


// ---------------------------
// DTOs
// ---------------------------

class RequestChatResult {
  final bool ok;
  final int? roomId;
  final String? status;
  final String? message;

  const RequestChatResult({
    required this.ok,
    this.roomId,
    this.status,
    this.message,
  });

  factory RequestChatResult.fromJson(Map<String, dynamic> json) {
    int? _readRoomId(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    // 서버가 여러 형태로 줄 수 있으니 모두 대비
    final fromTopLevel     = _readRoomId(json['roomId']);
    final fromChatRoomId   = _readRoomId(json['chatRoomId']);
    final fromRoomObject   = (json['room'] is Map) ? _readRoomId((json['room'] as Map)['id']) : null;

    return RequestChatResult(
      ok: json['ok'] == true,
      roomId: fromTopLevel ?? fromChatRoomId ?? fromRoomObject,
      status: json['status']?.toString(),
      message: json['message']?.toString(),
    );
  }
}
class ConsentResult {
  final bool ok;
  final String? status;  // 'active' | 'blocked' ...
  final String? message;
  ConsentResult({required this.ok, this.status, this.message});
  factory ConsentResult.fromJson(Map m) => ConsentResult(
    ok: m['ok'] == true || m['status'] != null, // 서버가 ok 안줄 수도 있으니 완화
    status: m['status']?.toString(),
    message: m['message']?.toString(),
  );
}


