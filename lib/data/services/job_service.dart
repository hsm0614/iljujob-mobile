  // job_service.dart
  import 'dart:convert';
  import 'dart:io';
  import 'package:http/http.dart' as http;
  import '../models/job.dart';
  import 'package:iljujob/config/constants.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import 'package:flutter/foundation.dart'; // ✅ debugPrint, kDebugMode
  import 'dart:async';
  class JobService {


DateTime? _parseDateToLocal(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;

  // 1) 에폭 숫자 처리 (ms/초 추정)
  if (RegExp(r'^\d+$').hasMatch(s)) {
    try {
      final numVal = int.parse(s);
      // 13자리면 ms, 10자리면 s로 가정
      final dt = (s.length >= 13)
          ? DateTime.fromMillisecondsSinceEpoch(numVal, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(numVal * 1000, isUtc: true);
      return dt.toLocal();
    } catch (_) {}
  }

  // 2) ISO 8601 (Z 또는 오프셋 포함) → 그대로 파싱, 로컬로 변환
  if (RegExp(r'[zZ]|[+\-]\d{2}:\d{2}$').hasMatch(s)) {
    try {
      final dt = DateTime.parse(s);
      return dt.isUtc ? dt.toLocal() : dt;
    } catch (_) {}
  }

  // 3) "YYYY-MM-DD HH:mm:ss" → 로컬로 취급 (Z 붙이지 않음!)
  if (RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}(:\d{2})?$').hasMatch(s)) {
    final localLike = s.replaceFirst(' ', 'T'); // 예: 2025-08-20T11:55:31
    try {
      // 오프셋이 없으므로 Dart는 로컬로 해석함
      final dt = DateTime.parse(localLike);
      return dt; // 이미 로컬
    } catch (_) {}
  }

  // 4) 기타 케이스: 파싱 시도 → 로컬 변환
  try {
    final dt = DateTime.parse(s);
    return dt.isUtc ? dt.toLocal() : dt;
  } catch (_) {
    return null;
  }
}

    // 🔹 1. 공고 리스트 조회 (구직자용 또는 도급사용)
static Future<List<Job>> fetchJobs({int? clientId}) async {
  // ── 1) URI 구성 (엔드포인트는 유지)
  final String base = (clientId != null)
      ? '$baseUrl/api/client/jobs'
      : '$baseUrl/api/job/jobs';

  final qp = <String, String>{
    if (clientId != null) 'clientId': '$clientId',
    'page': '1',
    'size': '50',
    // 🔒 서버가 무시해도 무방하지만, 있으면 정렬 고정에 도움
    'order': 'publish_at_desc_id_desc',
    // ETag 쓰기 전까지 캐시깨기 유지 (원래 있던 값)
    '_ts': DateTime.now().millisecondsSinceEpoch.toString(),
  };

  final uri = Uri.parse(base).replace(queryParameters: qp);

  // ── 2) 헤더 구성 (토큰은 있으면만 붙임)
  final headers = <String, String>{
    'Accept': 'application/json',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
  };
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
  } catch (_) {
    // 토큰 로드 실패는 무시(익명 요청 가능)
  }

  // ── 3) 요청
  if (kDebugMode) debugPrint('[API/jobs] GET $uri'); // ✅ 실제 호출 URL 찍기
  final sw = Stopwatch()..start();
  http.Response response;
  try {
    response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
  } on TimeoutException {
    throw Exception('공고 불러오기 타임아웃');
  } catch (e) {
    throw Exception('공고 불러오기 중 오류 발생');
  } finally {
    sw.stop();
  }

  if (response.statusCode != 200) {
    throw Exception('공고 불러오기 실패 (status: ${response.statusCode})');
  }

  // ── 5) JSON 파싱 (배열 또는 {content:[]} / {data:[]} 모두 허용)
  final decoded = json.decode(response.body);
  List<dynamic> jsonList;
  if (decoded is List) {
    jsonList = decoded;
  } else if (decoded is Map && decoded['content'] is List) {
    jsonList = List<dynamic>.from(decoded['content'] as List);
  } else if (decoded is Map && decoded['data'] is List) {
    jsonList = List<dynamic>.from(decoded['data'] as List);
  } else {
    throw Exception('예상치 못한 응답 형식');
  }

  // ── 6) 모델 매핑
  final jobs = <Job>[];
  for (final m in jsonList.whereType<Map<String, dynamic>>()) {
    try {
      jobs.add(Job.fromJson(m)); // ✅ 날짜 파싱은 모델에서 UTC로 일원화
    } catch (e) {
    }
  }

  // ── 7) 안정 정렬(서버 보장 없을 때 안전망)
  // publishAt(없으면 createdAt) DESC → id DESC
  jobs.sort((a, b) {
    final ap = a.publishAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final bp = b.publishAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final c1 = bp.compareTo(ap);
    if (c1 != 0) return c1;

    // ⚠️ Job.id가 String이면 숫자 비교로 보정 (가능하면 모델을 int로 바꾸는 걸 권장)
    int ai, bi;
    try { ai = (a.id is int) ? a.id as int : int.parse(a.id.toString()); }
    catch (_) { ai = 0; }
    try { bi = (b.id is int) ? b.id as int : int.parse(b.id.toString()); }
    catch (_) { bi = 0; }

    return bi.compareTo(ai); // id DESC
  });

  if (kDebugMode) {
    for (final j in jobs.take(5)) {
    }
  }

  return jobs;
}
    // 🔹 2. 공고 등록 (이미지 + 요일 + 위치 위경도 포함)
static Future<void> postJobWithImages({
  required String title,
  required String category,
   String? categoryMajor,  // ✅ 추가
  String? categorySub,    // ✅ 추가
  required String location,
  required String locationCity,
  required String startDate,
  required String endDate,
  required String startTime,
  required String endTime,
  required String payType,
  required int pay,
  required String description,
  required int clientId,
  required bool isScheduled,
  String? weekdays,
  double? lat,
  double? lng,
  List<File> images = const [],
  String? publishAt,
  bool isSameDayPay = false,
  required bool isPaid,

  // ✅ 추가 (대행)
  bool isAgency = false,
  String? agencyPhone,
  String? agencyEmail,
  String? agencyNote,
}) async {

  final uri = Uri.parse('$baseUrl/api/job/post_job');

  // 🔐 토큰 읽어서 Authorization 헤더에 붙임
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? '';
  if (token.isEmpty) {
    throw Exception('로그인이 필요합니다(토큰 없음)');
  }

  final request = http.MultipartRequest('POST', uri)
    ..headers['Authorization'] = 'Bearer $token'
  ..fields.addAll({
  'title': title.trim(),
   'category': category.trim(),
  if (categoryMajor != null && categoryMajor.isNotEmpty) 'category_major': categoryMajor.trim(),  // ✅ 추가
  if (categorySub != null && categorySub.isNotEmpty)    'category_sub':   categorySub.trim(),     // ✅ 추가
  'location': location.trim(),
  'location_city': locationCity.trim(),
  'start_date': startDate,
  'end_date': endDate,
  'start_time': startTime,
  'end_time': endTime,
  'pay_type': payType,
  'pay': pay.toString(),
  'description': description.trim(),
  'client_id': clientId.toString(),
  'is_same_day_pay': isSameDayPay ? '1' : '0',
  if (weekdays != null && weekdays.isNotEmpty) 'weekdays': weekdays,
  if (lat != null) 'lat': lat.toString(),
  if (lng != null) 'lng': lng.toString(),

  // ✅ 대행
  'is_agency': isAgency ? '1' : '0',
  if (agencyPhone != null && agencyPhone.trim().isNotEmpty) 'agency_phone': agencyPhone.trim(),
  if (agencyEmail != null && agencyEmail.trim().isNotEmpty) 'agency_email': agencyEmail.trim(),
  if (agencyNote  != null && agencyNote.trim().isNotEmpty)  'agency_note': agencyNote.trim(),
});
  // ⏰ 예약 공개면 publishAt 포함(비어있으면 아예 안보냄)
if (publishAt != null && publishAt.isNotEmpty) {
  request.fields['publish_at'] = publishAt; // UTC ISO(Z)
}
  // 💰 유료 여부(서버가 '1'/'0' 읽으므로 그대로)
  request.fields['is_paid'] = isPaid ? '1' : '0';

    // 🖼️ 여러 장 파일 첨부 (서버 필드명 예: images[])
    for (final f in images) {
      request.files.add(await http.MultipartFile.fromPath('images[]', f.path));
    }

  final resp = await request.send();
  final body = await resp.stream.bytesToString();

 if (resp.statusCode != 200) {
  debugPrint('❌ POST /post_job 실패: ${resp.statusCode} | $body');

  // ✅ body를 그대로 throw에 포함 (여기서 모달 트리거 문자열이 살아있어야 함)
  throw Exception('HTTP_${resp.statusCode}: $body');
} else {

  }
}
    // 🔥 공통 fetch 메서드로 정리
    static Future<List<Job>> _fetchJobsFromUri(Uri uri) async {
      try {
        final response = await http.get(uri);
        if (response.statusCode == 200) {
          final List<dynamic> jsonList = json.decode(response.body);
          return jsonList.map((json) => Job.fromJson(json)).toList();
        } else {
          throw Exception('공고 불러오기 실패 (status: ${response.statusCode})');
        }
      } catch (e) {
        throw Exception('공고 불러오기 중 오류 발생');
      }
    }

    // 🔹 3. 공고 상세 조회 (ID로)
    static Future<Job> fetchJobById(String id) async {
      final uri = Uri.parse('$baseUrl/api/job/$id');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return Job.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('공고 정보를 불러오지 못했습니다');
      }
    }

    // 🔹 4. 공고 수정
    static Future<void> updateJob(String id, Map<String, dynamic> data) async {
      final uri = Uri.parse('$baseUrl/api/job/$id');
      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );

      if (response.statusCode != 200) {
        throw Exception('공고 수정 실패');
      }
    }

    // 🔹 5. 공고 삭제
  static Future<void> deleteJob(String jobId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    final uri = Uri.parse('$baseUrl/api/job/delete/$jobId');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('공고 삭제 실패');
    }
  }
// 🔹 6. 공고 수정 (이미지 포함, 키/시간/불리언 보정 포함)
static Future<void> updateJobWithImages({
  required String id,
  required Map<String, dynamic> data,
  List<File> newImages = const [],          // 새로 추가할 이미지
  List<String> deleteImageUrls = const [],  // 기존 이미지 중 삭제할 URL
}) async {
  final uri = Uri.parse('$baseUrl/api/job/update/$id');

  // 🔐 토큰
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? '';
  if (token.isEmpty) {
    throw Exception('로그인이 필요합니다(토큰 없음)');
  }

  final req = http.MultipartRequest('POST', uri)
    ..headers['Authorization'] = 'Bearer $token'
    ..headers['Accept'] = 'application/json';

  // ---- helpers ----
  String _toHm(dynamic v) {
    // "9:5" / "09:5" / "9:05" / "09:05" → "HH:mm"
    if (v == null) return '';
    final s = v.toString().trim();
    if (s.isEmpty) return '';
    final m = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(s);
    if (m == null) return s; // 이미 "HH:mm" 이거나 서버가 허용하는 형식이면 그대로
    final h = int.tryParse(m.group(1)!) ?? 0;
    final n = int.tryParse(m.group(2)!) ?? 0;
    return '${h.toString().padLeft(2, '0')}:${n.toString().padLeft(2, '0')}';
  }

  String _toYmd(dynamic v) {
    // DateTime → (KST 자정 의미면) KST yyyy-MM-dd
    // String "yyyy-MM-dd" → 그대로
    if (v == null) return '';
    if (v is DateTime) {
      final kst = v.toUtc().add(const Duration(hours: 9));
      return '${kst.year.toString().padLeft(4,'0')}-'
             '${kst.month.toString().padLeft(2,'0')}-'
             '${kst.day.toString().padLeft(2,'0')}';
    }
    final s = v.toString().trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return s;
    // 그 외는 가급적 파싱해서 yyyy-MM-dd로
    try {
      final dt = DateTime.parse(s).toUtc().add(const Duration(hours: 9));
      return '${dt.year.toString().padLeft(4,'0')}-'
             '${dt.month.toString().padLeft(2,'0')}-'
             '${dt.day.toString().padLeft(2,'0')}';
    } catch (_) {
      return s;
    }
  }

  String _boolTo01(dynamic v) {
    if (v is bool) return v ? '1' : '0';
    if (v == 1 || v == '1' || v == 'true' || v == 'TRUE') return '1';
    if (v == 0 || v == '0' || v == 'false' || v == 'FALSE') return '0';
    return v?.toString() ?? '';
  }

  // ---- 데이터 정규화 ----
  final normalized = Map<String, dynamic>.from(data);

  // camel ↔ snake 양방향 미러링
  void mirror(String a, String b) {
    final av = normalized[a];
    final bv = normalized[b];
    if ((av == null || (av is String && av.isEmpty)) &&
        (bv != null && (!(bv is String) || bv.isNotEmpty))) {
      normalized[a] = bv;
    }
    if ((bv == null || (bv is String && bv.isEmpty)) &&
        (av != null && (!(av is String) || av.isNotEmpty))) {
      normalized[b] = av;
    }
  }

  // 주요 필드들 미러링
  mirror('start_time', 'startTime');
  mirror('end_time', 'endTime');
  mirror('start_date', 'startDate');
  mirror('end_date', 'endDate');
  mirror('pay_type', 'payType');
  mirror('location_city', 'locationCity');
  mirror('publish_at', 'publishAt');
  mirror('pinned_until', 'pinnedUntil');
  mirror('expires_at', 'expiresAt');
  mirror('is_same_day_pay', 'isSameDayPay');
  mirror('is_certified_company', 'isCertifiedCompany');
  mirror('is_paid', 'isPaid');

  // 시간/날짜/불리언 보정
  if (normalized.containsKey('start_time')) {
    normalized['start_time'] = _toHm(normalized['start_time']);
  }
  if (normalized.containsKey('end_time')) {
    normalized['end_time'] = _toHm(normalized['end_time']);
  }
  if (normalized.containsKey('startTime')) {
    normalized['startTime'] = _toHm(normalized['startTime']);
  }
  if (normalized.containsKey('endTime')) {
    normalized['endTime'] = _toHm(normalized['endTime']);
  }

  if (normalized.containsKey('start_date')) {
    normalized['start_date'] = _toYmd(normalized['start_date']);
  }
  if (normalized.containsKey('end_date')) {
    normalized['end_date'] = _toYmd(normalized['end_date']);
  }
  if (normalized.containsKey('startDate')) {
    normalized['startDate'] = _toYmd(normalized['startDate']);
  }
  if (normalized.containsKey('endDate')) {
    normalized['endDate'] = _toYmd(normalized['endDate']);
  }

  // 불리언류는 1/0 로
  for (final key in ['is_paid','isPaid','is_same_day_pay','isSameDayPay','is_certified_company','isCertifiedCompany']) {
    if (normalized.containsKey(key)) {
      normalized[key] = _boolTo01(normalized[key]);
    }
  }

  // 빈 문자열은 필드 자체를 보내지 않아 기존 값 훼손 방지
  normalized.removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));

  // 최종 필드 채우기
  normalized.forEach((k, v) => req.fields[k] = v.toString());

  // 삭제할 기존 이미지 URL 배열
  for (final url in deleteImageUrls) {
    if (url.trim().isEmpty) continue;
    req.fields.putIfAbsent('delete_image_urls[]', () => url);
    // 동일 키 다중 전송이 필요하면 아래처럼 add 해도 됨:
    // req.fields['delete_image_urls[]'] = url;
  }

  // 새로 추가할 이미지
  for (final f in newImages) {
    req.files.add(await http.MultipartFile.fromPath('images[]', f.path));
  }

  // 전송
  final streamed = await req.send();
  final resBody = await streamed.stream.bytesToString();

  if (streamed.statusCode != 200) {
    throw Exception('공고 수정 실패 (${streamed.statusCode}) | $resBody');
  }
}


  static Future<List<Job>> fetchBookmarkedJobs(int userId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/bookmark/list?userId=$userId'));

    if (response.statusCode == 200) {
      final List<dynamic> jsonData = jsonDecode(response.body);
      return jsonData.map((json) => Job.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load bookmarked jobs');
    }
  }
  // 🔹 알림 클릭 시 공고 상세 조회 (토큰 포함)
  static Future<Job?> fetchJobByIdWithToken(int jobId, String token) async {
    try {
      final uri = Uri.parse('$baseUrl/api/job/$jobId');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Job.fromJson(data);
      } else {
        print('❌ 공고 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 예외 발생: $e');
    }
    return null;
  }
static Future<void> publishNow(int jobId) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken') ?? '';

  final uri = Uri.parse('$baseUrl/api/job/$jobId/publish-now');
  final resp = await http.post(uri, headers: {
    'Authorization': 'Bearer $token',
  });

  if (resp.statusCode != 200) {
    throw Exception('즉시 게시 실패: ${resp.body}');
  }
}
  }

