// lib/models/job.dart
import 'package:intl/intl.dart';

// ---------- 파서들: 모두 UTC 반환 ----------
DateTime? _parseToUtcAssumingKST(dynamic v) {
  if (v == null) return null;
  final s0 = v.toString().trim();
  if (s0.isEmpty) return null;

  // epoch
  if (RegExp(r'^\d+$').hasMatch(s0)) {
    final n = int.parse(s0);
    return (s0.length >= 13)
        ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
  }

  // 이미 TZ 있음
  if (RegExp(r'(?:[zZ]|[+\-]\d{2}:\d{2})$').hasMatch(s0)) {
    return DateTime.tryParse(s0)?.toUtc();
  }

  // TZ 없음 → KST로 가정(+09:00) → UTC
  final s = s0.contains('T') ? s0 : s0.replaceFirst(' ', 'T');
  return DateTime.tryParse('$s+09:00')?.toUtc();
}

DateTime? _parseServerDateTimeUtc(dynamic v) {
  if (v == null) return null;
  final s0 = v.toString().trim();
  if (s0.isEmpty) return null;

  // epoch
  if (RegExp(r'^\d+$').hasMatch(s0)) {
    final n = int.parse(s0);
    return (s0.length >= 13)
        ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
  }

  // TZ 있음
  if (RegExp(r'(?:[zZ]|[+\-]\d{2}:\d{2})$').hasMatch(s0)) {
    return DateTime.tryParse(s0)?.toUtc();
  }

  // TZ 없음 → UTC 간주(Z 붙임)
  final s = s0.contains('T') ? s0 : s0.replaceFirst(' ', 'T');
  return DateTime.tryParse('${s}Z')?.toUtc();
}

/// 날짜만 있는 값(YYYY-MM-DD): "KST 자정"을 의미 → UTC로 변환(전날 15:00 UTC)
DateTime? _parseDateOnlyUtcFromKST(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;

  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) {
    // 날짜만이 아니면 KST 가정 파서로 폴백
    return _parseToUtcAssumingKST(s);
  }
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  // KST 00:00 == UTC 전날 15:00
  return DateTime.utc(y, mo, d).subtract(const Duration(hours: 9));
}

/// 레퍼런스 시각에 더 가까운 해석(UTC/KST)을 고르는 보정 파서(둘 다 UTC 반환)
DateTime? _parseWithReferenceUtc(dynamic raw, {DateTime? refUtc}) {
  if (raw == null) return null;
  final s0 = raw.toString().trim();
  if (s0.isEmpty) return null;

  if (RegExp(r'(?:[zZ]|[+\-]\d{2}:\d{2})$').hasMatch(s0)) {
    return DateTime.tryParse(s0)?.toUtc();
  }

  final base = s0.contains('T') ? s0 : s0.replaceFirst(' ', 'T');
  final utcVer = DateTime.tryParse('${base}Z')?.toUtc();
  final kstVer = DateTime.tryParse('${base}+09:00')?.toUtc();

  if (utcVer != null && kstVer != null && refUtc != null) {
    final diffUtc = (utcVer.difference(refUtc)).abs();
    final diffKst = (kstVer.difference(refUtc)).abs();
    return diffUtc <= diffKst ? utcVer : kstVer;
  }
  return kstVer ?? utcVer;
}

/// ✅ 이미지 URL만 따로 모아서 List<String> 으로 만들어주는 헬퍼
List<String> _parseImageUrlsFromJson(Map<String, dynamic> json) {
  final List<String> result = [];

  // 1) 배열 필드들
  final raw1 = json['image_urls'];
  final raw2 = json['imageUrls'];

  if (raw1 is List) {
    result.addAll(raw1.map((e) => e.toString()));
  }
  if (raw2 is List) {
    result.addAll(raw2.map((e) => e.toString()));
  }

  // 2) 단일 URL 필드들(있으면 추가)
  final single = json['image_url'] ??
      json['imageUrl'] ??
      json['thumbnail_url'] ??
      json['thumbUrl'];

  if (single != null && single.toString().trim().isNotEmpty) {
    result.add(single.toString());
  }

  // 3) 중복 제거
  return result.toSet().toList();
}

// ---------- 모델 ----------
class Job {
  final String id;
  final String? userNumber;
  final String title;
  final String location;
  final String locationCity;
  final String pay;
  final String payType;
  final String startTime;
  final String endTime;
  final String category;
  final String? description;
  final String? company;

  // ✅ 모두 UTC로 보관
  final DateTime? createdAt;     // UTC
  final DateTime? startDate;     // UTC (KST 자정 의미)
  final DateTime? endDate;       // UTC (KST 자정 의미)
  final DateTime? publishAt;     // UTC (UI 노출/예약)
  final DateTime? pinnedUntil;   // UTC (고정 종료)
  final DateTime? expiresAt;     // UTC (노출 만료)

  final String? weekdays;
  final double lat;
  final double lng;
  final List<String> imageUrls;
  final String status;
  final int? chatRoomId;
  final int? clientId;
  final int workerId;
  final bool isSameDayPay;
  final bool isCertifiedCompany;
  final bool isPaid;

  Job({
    required this.id,
    this.userNumber,
    required this.title,
    required this.location,
    required this.locationCity,
    required this.pay,
    required this.payType,
    required this.startTime,
    required this.endTime,
    required this.category,
    this.description,
    this.company,
    this.createdAt,
    this.startDate,
    this.endDate,
    this.publishAt,
    this.pinnedUntil,
    this.expiresAt,
    this.weekdays,
    required this.lat,
    required this.lng,
    this.imageUrls = const [],
    required this.status,
    this.chatRoomId,
    this.clientId,
    this.workerId = 0,
    required this.isSameDayPay,
    required this.isCertifiedCompany,
    this.isPaid = true,
  });

  String get workingHours => '$startTime ~ $endTime';

  // Job 클래스 내부에 추가 (UTC 가정)
  DateTime? get postedAtUtc => publishAt ?? createdAt;
  bool get isScheduled =>
      publishAt != null && publishAt!.isAfter(DateTime.now().toUtc());

  factory Job.fromJson(Map<String, dynamic> json) {
    T? _pick<T>(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v != null) return v as T;
      }
      return null;
    }

    // 정책: 서버 스탬프(created/updated 등)는 UTC, 노출/스케줄(publish/start/end)은 KST 의미
    final publishAtUtc =
        _parseServerDateTimeUtc(json['publish_at'] ?? json['publishAt']);
    final createdAtUtc =
        _parseServerDateTimeUtc(json['created_at'] ?? json['createdAt']);
    final expiresAtUtc =
        _parseServerDateTimeUtc(json['expires_at'] ?? json['expiresAt']);
    final pinnedUntilUtc =
        _parseServerDateTimeUtc(json['pinned_until'] ?? json['pinnedUntil']);

    return Job(
      id: json['id']?.toString() ?? '',
      userNumber:
          json['userNumber']?.toString() ?? json['user_number']?.toString(),
      title: json['title'] ?? '',
      location: json['location'] ?? '',
      locationCity: _pick<String>(['location_city', 'locationCity']) ?? '',
      pay: json['pay']?.toString() ?? '',
      payType: _pick<String>(['pay_type', 'payType']) ?? '일급',
      startTime: _pick<String>(['start_time', 'startTime'])?.toString() ?? '',
      endTime: _pick<String>(['end_time', 'endTime'])?.toString() ?? '',
      category: json['category'] ?? '기타',
      description: json['description'],
      company: json['company'],

      // ✅ UTC 보관
      publishAt: publishAtUtc,
      createdAt: createdAtUtc,
      expiresAt: expiresAtUtc,
      pinnedUntil: pinnedUntilUtc,

      // 날짜만: KST 자정 의미 → UTC 보관
      startDate: _parseDateOnlyUtcFromKST(_pick(['start_date', 'startDate'])),
      endDate: _parseDateOnlyUtcFromKST(_pick(['end_date', 'endDate'])),

      weekdays: json['weekdays'],
      lat: (() {
        final v = json['lat'];
        if (v is double) return v;
        if (v is int) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0.0;
        return 0.0;
      })(),
      lng: (() {
        final v = json['lng'];
        if (v is double) return v;
        if (v is int) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0.0;
        return 0.0;
      })(),

      // 🔥 여기만 변경됨: 배열 + 단일 URL 모두 처리
      imageUrls: _parseImageUrlsFromJson(json),

      status: json['status'] ?? 'active',
      chatRoomId: () {
        final v = json['chat_room_id'];
        if (v is int) return v;
        if (v is String) return int.tryParse(v);
        return null;
      }(),
      clientId: () {
        final v = json['client_id'];
        if (v is int) return v;
        if (v is String) return int.tryParse(v);
        return null;
      }(),
      workerId: () {
        final v = json['worker_id'];
        if (v is int) return v;
        if (v is String) return int.tryParse(v) ?? 0;
        return 0;
      }(),
      isSameDayPay:
          json['is_same_day_pay'] == 1 || json['is_same_day_pay'] == true,
      isCertifiedCompany: json['is_certified_company'] == 1 ||
          json['is_certified_company'] == true,
      isPaid: json['is_paid'] == null
          ? true
          : (json['is_paid'] == 1 || json['is_paid'] == true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'user_number': userNumber,
      'location': location,
      'location_city': locationCity,
      'pay': pay,
      'pay_type': payType,
      'start_time': startTime,
      'end_time': endTime,
      'category': category,
      'description': description,
      'company': company,
      // ✅ 항상 UTC ISO 저장
      'created_at': createdAt?.toUtc().toIso8601String(),
      'start_date': startDate?.toUtc().toIso8601String(),
      'end_date': endDate?.toUtc().toIso8601String(),
      'publish_at': publishAt?.toUtc().toIso8601String(),
      'pinned_until': pinnedUntil?.toUtc().toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'weekdays': weekdays,
      'lat': lat,
      'lng': lng,
      'image_urls': imageUrls,
      'status': status,
      'chat_room_id': chatRoomId,
      'client_id': clientId,
      'worker_id': workerId,
      'is_same_day_pay': isSameDayPay,
      'is_certified_company': isCertifiedCompany ? 1 : 0,
      'is_paid': isPaid ? 1 : 0,
    };
  }
}
