// job_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/job.dart';
import 'package:iljujob/config/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

// ════════════════════════════════════════════════════════
//  날짜/시간 유틸 (static 클래스 외부에 top-level로 정의)
// ════════════════════════════════════════════════════════

final _reHm = RegExp(r'^(\d{1,2}):(\d{1,2})$');
final _reYmd = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// "HH:mm" 형식으로 정규화
/// "9:5" / "09:5" / "9:05" → "09:05"
String _toHm(dynamic v) {
  if (v == null) return '';
  final s = v.toString().trim();
  if (s.isEmpty) return '';
  final m = _reHm.firstMatch(s);
  if (m == null) return s;
  final h = int.tryParse(m.group(1)!) ?? 0;
  final n = int.tryParse(m.group(2)!) ?? 0;
  return '${h.toString().padLeft(2, '0')}:${n.toString().padLeft(2, '0')}';
}

/// "YYYY-MM-DD" 형식으로 정규화
/// ✅ FIX: 로컬 날짜 기준으로 변환 (UTC 변환 후 자르기 제거)
///         자정 근처에 KST와 UTC 날짜가 달라지는 버그 방지
String _toYmd(dynamic v) {
  if (v == null) return '';
  if (v is DateTime) {
    // ✅ toLocal()로 변환 후 날짜 추출 (UTC → KST 날짜 불일치 방지)
    final local = v.isUtc ? v.toLocal() : v;
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
  final s = v.toString().trim();
  // 이미 YYYY-MM-DD 형식이면 그대로
  if (_reYmd.hasMatch(s)) return s;
  // 그 외: 파싱해서 로컬 기준 YYYY-MM-DD로
  try {
    final dt = DateTime.parse(s);
    final local = dt.isUtc ? dt.toLocal() : dt;
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return s;
  }
}

/// bool → '1' / '0'
String _boolTo01(dynamic v) {
  if (v is bool) return v ? '1' : '0';
  if (v == 1 || v == '1' || v == 'true' || v == 'TRUE') return '1';
  if (v == 0 || v == '0' || v == 'false' || v == 'FALSE') return '0';
  return v?.toString() ?? '';
}

// ════════════════════════════════════════════════════════
//  JobService
// ════════════════════════════════════════════════════════
class JobService {
  // ✅ FIX: _parseDateToLocal 제거
  //    - 원래 인스턴스 메서드로 정의되어 static 클래스 내에서 호출 불가
  //    - job.dart의 _parseServerDateTimeUtc / _parseDateOnlyUtcFromKST 로 일원화됨
  //    - 이 클래스에서 날짜 파싱이 필요한 경우 top-level 유틸(_toYmd) 사용

  // ─── 1. 공고 리스트 조회 ─────────────────────────────
  static Future<List<Job>> fetchJobs({int? clientId}) async {
    final String base = (clientId != null)
        ? '$baseUrl/api/client/jobs'
        : '$baseUrl/api/job/jobs';

    final qp = <String, String>{
      if (clientId != null) 'clientId': '$clientId',
      'page': '1',
      'size': '50',
      'order': 'publish_at_desc_id_desc',
      '_ts': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    final uri = Uri.parse(base).replace(queryParameters: qp);

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
    } catch (_) {}

    if (kDebugMode) debugPrint('[API/jobs] GET $uri');
    final sw = Stopwatch()..start();
    http.Response response;
    try {
      response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
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

    final jobs = <Job>[];
    for (final m in jsonList.whereType<Map<String, dynamic>>()) {
      try {
        jobs.add(Job.fromJson(m));
      } catch (e) {
        if (kDebugMode) debugPrint('[JobService] Job.fromJson 실패: $e');
      }
    }

    // ✅ 안전 정렬: publishAt(없으면 createdAt) DESC → id DESC
    jobs.sort((a, b) {
      final ap = a.publishAt ??
          a.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final bp = b.publishAt ??
          b.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final c1 = bp.compareTo(ap);
      if (c1 != 0) return c1;

      int ai, bi;
      try { ai = (a.id is int) ? a.id as int : int.parse(a.id.toString()); }
      catch (_) { ai = 0; }
      try { bi = (b.id is int) ? b.id as int : int.parse(b.id.toString()); }
      catch (_) { bi = 0; }

      return bi.compareTo(ai);
    });

    return jobs;
  }

  // ─── 2. 공고 등록 (이미지 + 요일 + 위치 위경도 포함) ──
  static Future<Map<String, dynamic>> postJobWithImages({
    required String title,
    required String category,
    String? categoryMajor,
    String? categorySub,
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
    String? publishAt,   // ✅ UTC ISO 문자열 (post_job_form에서 toUtc().toIso8601String()으로 전달)
    bool isSameDayPay = false,
    required bool isPaid,
    bool isAgency = false,
    String? agencyPhone,
    String? agencyEmail,
    String? agencyNote,
    // 장기 공고 전용
    String jobType = 'short',
    bool isAlwaysOpen = false,
    int? workDaysPerWeek,
    String? requiredCerts,
    String? welfare,
  }) async {
    final uri = Uri.parse('$baseUrl/api/job/post_job');

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
        if (categoryMajor != null && categoryMajor.isNotEmpty)
          'category_major': categoryMajor.trim(),
        if (categorySub != null && categorySub.isNotEmpty)
          'category_sub': categorySub.trim(),
        'location': location.trim(),
        'location_city': locationCity.trim(),
        'start_date': startDate,   // ✅ 이미 YYYY-MM-DD 로컬 기준
        'end_date': endDate,       // ✅ 이미 YYYY-MM-DD 로컬 기준
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
        'is_agency': isAgency ? '1' : '0',
        // 장기 공고 전용
        'job_type': jobType,
        if (jobType == 'long') 'is_always_open': isAlwaysOpen ? '1' : '0',
        if (jobType == 'long' && workDaysPerWeek != null)
          'work_days_per_week': workDaysPerWeek.toString(),
        if (jobType == 'long' && requiredCerts != null && requiredCerts.isNotEmpty)
          'required_certs': requiredCerts,
        if (jobType == 'long' && welfare != null && welfare.isNotEmpty)
          'welfare': welfare,
        if (agencyPhone != null && agencyPhone.trim().isNotEmpty)
          'agency_phone': agencyPhone.trim(),
        if (agencyEmail != null && agencyEmail.trim().isNotEmpty)
          'agency_email': agencyEmail.trim(),
        if (agencyNote != null && agencyNote.trim().isNotEmpty)
          'agency_note': agencyNote.trim(),
      });

    // ✅ FIX: 예약 공개 시각은 UTC ISO 문자열로 전달 (서버에서 파싱)
    if (publishAt != null && publishAt.isNotEmpty) {
      request.fields['publish_at'] = publishAt;
      if (kDebugMode) debugPrint('[JobService] 예약 공개 시각(UTC): $publishAt');
    }

    request.fields['is_paid'] = isPaid ? '1' : '0';

    for (final f in images) {
      request.files.add(await http.MultipartFile.fromPath('images[]', f.path));
    }

    final resp = await request.send();
    final body = await resp.stream.bytesToString();

    if (resp.statusCode != 200) {
      debugPrint('❌ POST /post_job 실패: ${resp.statusCode} | $body');
      throw Exception('HTTP_${resp.statusCode}: $body');
    }

    if (kDebugMode) debugPrint('[JobService] 공고 등록 성공: $body');
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // ─── 3. 공고 상세 조회 (ID로) ─────────────────────────
  static Future<Job> fetchJobById(String id) async {
    final uri = Uri.parse('$baseUrl/api/job/$id');
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      return Job.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('공고 정보를 불러오지 못했습니다');
    }
  }

  // ─── 4. 공고 수정 (단순 JSON) ─────────────────────────
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

  // ─── 5. 공고 삭제 ─────────────────────────────────────
  static Future<void> deleteJob(String jobId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    final uri = Uri.parse('$baseUrl/api/job/delete/$jobId');
    final response = await http.delete(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception('공고 삭제 실패');
    }
  }

  // ─── 6. 공고 수정 (이미지 포함) ───────────────────────
  static Future<void> updateJobWithImages({
    required String id,
    required Map<String, dynamic> data,
    List<File> newImages = const [],
    List<String> deleteImageUrls = const [],
  }) async {
    final uri = Uri.parse('$baseUrl/api/job/update/$id');

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';
    if (token.isEmpty) {
      throw Exception('로그인이 필요합니다(토큰 없음)');
    }

    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';

    // ── 데이터 정규화 ────────────────────────────────────
    final normalized = Map<String, dynamic>.from(data);

    // camelCase ↔ snake_case 미러링
    void mirror(String a, String b) {
      final av = normalized[a];
      final bv = normalized[b];
      if ((av == null || (av is String && av.isEmpty)) &&
          (bv != null && (bv is! String || bv.isNotEmpty))) {
        normalized[a] = bv;
      }
      if ((bv == null || (bv is String && bv.isEmpty)) &&
          (av != null && (av is! String || av.isNotEmpty))) {
        normalized[b] = av;
      }
    }

    mirror('start_time',          'startTime');
    mirror('end_time',            'endTime');
    mirror('start_date',          'startDate');
    mirror('end_date',            'endDate');
    mirror('pay_type',            'payType');
    mirror('location_city',       'locationCity');
    mirror('publish_at',          'publishAt');
    mirror('pinned_until',        'pinnedUntil');
    mirror('expires_at',          'expiresAt');
    mirror('is_same_day_pay',     'isSameDayPay');
    mirror('is_certified_company','isCertifiedCompany');
    mirror('is_paid',             'isPaid');

    // 시간 정규화 ("HH:mm")
    for (final key in ['start_time', 'end_time', 'startTime', 'endTime']) {
      if (normalized.containsKey(key)) {
        normalized[key] = _toHm(normalized[key]);
      }
    }

    // ✅ FIX: 날짜 정규화 — 로컬 기준 YYYY-MM-DD
    for (final key in ['start_date', 'end_date', 'startDate', 'endDate']) {
      if (normalized.containsKey(key)) {
        normalized[key] = _toYmd(normalized[key]);
      }
    }

    // bool → 1/0
    for (final key in [
      'is_paid', 'isPaid',
      'is_same_day_pay', 'isSameDayPay',
      'is_certified_company', 'isCertifiedCompany',
    ]) {
      if (normalized.containsKey(key)) {
        normalized[key] = _boolTo01(normalized[key]);
      }
    }

    // ✅ FIX: publish_at / publishAt은 UTC ISO 문자열 그대로 전달
    //         (이미 toUtc().toIso8601String()으로 변환된 값)
    //         별도 변환 없이 서버로 그대로 전송

    // 빈 값은 제거 (기존 값 훼손 방지)
    normalized.removeWhere(
        (k, v) => v == null || (v is String && v.trim().isEmpty));

    // 필드 채우기
    normalized.forEach((k, v) => req.fields[k] = v.toString());

    // 삭제할 기존 이미지 URL
    for (final url in deleteImageUrls) {
      if (url.trim().isEmpty) continue;
      req.fields['delete_image_urls[]'] = url;
    }

    // 새 이미지
    for (final f in newImages) {
      req.files.add(await http.MultipartFile.fromPath('images[]', f.path));
    }

    final streamed = await req.send();
    final resBody  = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('공고 수정 실패 (${streamed.statusCode}) | $resBody');
    }
  }

  // ─── 7. 북마크된 공고 목록 ────────────────────────────
  static Future<List<Job>> fetchBookmarkedJobs(int userId) async {
    final response = await http.get(
        Uri.parse('$baseUrl/api/bookmark/list?userId=$userId'));

    if (response.statusCode == 200) {
      final List<dynamic> jsonData = jsonDecode(response.body);
      return jsonData.map((json) => Job.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load bookmarked jobs');
    }
  }

  // ─── 8. 알림 클릭 시 공고 상세 조회 (토큰 포함) ───────
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
        return Job.fromJson(jsonDecode(response.body));
      } else {
        debugPrint('❌ 공고 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ 예외 발생: $e');
    }
    return null;
  }

  // ─── 9. 즉시 게시 ─────────────────────────────────────
  static Future<void> publishNow(int jobId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';

    final uri  = Uri.parse('$baseUrl/api/job/$jobId/publish-now');
    final resp = await http.post(uri, headers: {'Authorization': 'Bearer $token'});

    if (resp.statusCode != 200) {
      throw Exception('즉시 게시 실패: ${resp.body}');
    }
  }

  // ─── Phase 2: 결제 전 가능 구직자 수 ─────────────────────
  static Future<int> fetchAvailableWorkersCount({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async {
    final uri = Uri.parse('$baseUrl/api/job/available-workers-count')
        .replace(queryParameters: {
      'lat': lat.toString(),
      'lng': lng.toString(),
      'radius': radiusM.toString(),
    });
    final resp = await http.get(uri).timeout(const Duration(seconds: 5));
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body)['count'] as num).toInt();
    }
    return 0;
  }

  // ─── 내부 헬퍼 (공통 fetch) ───────────────────────────
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
}