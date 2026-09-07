// lib/models/job.dart
import 'dart:convert'; // jsonDecode용
import 'dart:math' as math;

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
  final kstVer = DateTime.tryParse('$base+09:00')?.toUtc();

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
  final single =
      json['image_url'] ??
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

/// 공고의 추가 근무지. 한 공고가 여러 지역에서 사람을 뽑는 경우
/// (예: 스타필드 고양·수원·제주) 서버가 job_locations로 내려준다.
class JobLocation {
  final String address;
  final String? locationCity;
  final double lat;
  final double lng;

  const JobLocation({
    required this.address,
    this.locationCity,
    required this.lat,
    required this.lng,
  });

  static double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  factory JobLocation.fromJson(Map<String, dynamic> j) => JobLocation(
    address: j['address']?.toString() ?? '',
    locationCity: j['location_city']?.toString(),
    lat: _toDouble(j['lat']),
    lng: _toDouble(j['lng']),
  );

  Map<String, dynamic> toJson() => {
    'address': address,
    'location_city': locationCity,
    'lat': lat,
    'lng': lng,
  };

  bool get hasGeo => lat != 0.0 && lng != 0.0;
}

/// 하버사인 거리(km). 화면마다 따로 갖고 있던 계산을 여기로 모은다 —
/// 목록 필터와 카드 표시가 다른 식을 쓰면 "3km인데 목록에 없다"가 생긴다.
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180.0;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) *
          math.sin(dLng / 2) * math.sin(dLng / 2);
  return r * 2 * math.asin(math.min(1.0, math.sqrt(a)));
}

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
  final DateTime? createdAt; // UTC
  final DateTime? startDate; // UTC (KST 자정 의미)
  final DateTime? endDate; // UTC (KST 자정 의미)
  final DateTime? publishAt; // UTC (UI 노출/예약)
  final DateTime? pinnedUntil; // UTC (고정 종료)
  final DateTime? expiresAt; // UTC (노출 만료)

  final String? weekdays;
  final double lat;
  final double lng;

  /// 추가 근무지. 비어 있으면 lat/lng 하나짜리 기존 공고다.
  final List<JobLocation> locations;

  /// 전국 공고 — 거리 필터를 통과시킨다.
  final bool isNationwide;
  final List<String> imageUrls;
  final String status;
  final int? chatRoomId;
  final int? clientId;
  final int workerId;
  final bool isSameDayPay;
  final bool isCertifiedCompany;
  final bool isPaid;
  final bool isUrgent;
  final bool isAgency;
  final String? agencyPhone;
  final String? agencyEmail;
  final String? agencyNote;
  final bool externalApplyEnabled;
  final String? externalApplyUrl;
  final String? externalApplyLabel;
  final double? matchScore; // 매칭 점수 0~1
  final List<String> matchReasons; // ["가까움", "시간대겹침", "시급상위"]
  final bool zeroApplicantRefunded; // 지원자 0명 이용권 자동 환급 여부

  // 장기 공고 전용
  final String jobType; // 'short' | 'long'
  final bool isAlwaysOpen; // 상시모집
  final int? workDaysPerWeek; // 주 N일
  final String? requiredCerts; // 자격요건
  final String? welfare; // 복리후생

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
    this.locations = const [],
    this.isNationwide = false,
    this.imageUrls = const [],
    required this.status,
    this.chatRoomId,
    this.clientId,
    this.workerId = 0,
    required this.isSameDayPay,
    required this.isCertifiedCompany,
    this.isPaid = true,
    this.isUrgent = false,
    this.isAgency = false,
    this.agencyPhone,
    this.agencyEmail,
    this.agencyNote,
    this.externalApplyEnabled = false,
    this.externalApplyUrl,
    this.externalApplyLabel,
    this.matchScore,
    this.matchReasons = const [],
    this.zeroApplicantRefunded = false,
    this.jobType = 'short',
    this.isAlwaysOpen = false,
    this.workDaysPerWeek,
    this.requiredCerts,
    this.welfare,
  });

  String get workingHours => '$startTime ~ $endTime';

  // Job 클래스 내부에 추가 (UTC 가정)
  DateTime? get postedAtUtc => publishAt ?? createdAt;
  bool get isScheduled =>
      publishAt != null && publishAt!.isAfter(DateTime.now().toUtc());
  bool get hasExternalApply =>
      isPaid &&
      externalApplyEnabled &&
      (externalApplyUrl?.trim().isNotEmpty ?? false);

  factory Job.fromJson(Map<String, dynamic> json) {
    T? pick<T>(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v != null) return v as T;
      }
      return null;
    }

    // 정책: 서버 스탬프(created/updated 등)는 UTC, 노출/스케줄(publish/start/end)은 KST 의미
    final publishAtUtc = _parseServerDateTimeUtc(
      json['publish_at'] ?? json['publishAt'],
    );
    final createdAtUtc = _parseServerDateTimeUtc(
      json['created_at'] ?? json['createdAt'],
    );
    final expiresAtUtc = _parseServerDateTimeUtc(
      json['expires_at'] ?? json['expiresAt'],
    );
    final pinnedUntilUtc = _parseServerDateTimeUtc(
      json['pinned_until'] ?? json['pinnedUntil'],
    );

    return Job(
      id: json['id']?.toString() ?? '',
      userNumber:
          json['userNumber']?.toString() ?? json['user_number']?.toString(),
      title: json['title'] ?? '',
      location: json['location'] ?? '',
      locationCity: pick<String>(['location_city', 'locationCity']) ?? '',
      pay: json['pay']?.toString() ?? '',
      payType: pick<String>(['pay_type', 'payType']) ?? '일급',
      startTime: pick<String>(['start_time', 'startTime'])?.toString() ?? '',
      endTime: pick<String>(['end_time', 'endTime'])?.toString() ?? '',
      category: json['category'] ?? '기타',
      description: json['description'],
      company: json['company'],

      // ✅ UTC 보관
      publishAt: publishAtUtc,
      createdAt: createdAtUtc,
      expiresAt: expiresAtUtc,
      pinnedUntil: pinnedUntilUtc,

      // 날짜만: KST 자정 의미 → UTC 보관
      startDate: _parseDateOnlyUtcFromKST(pick(['start_date', 'startDate'])),
      endDate: _parseDateOnlyUtcFromKST(pick(['end_date', 'endDate'])),

      weekdays: json['weekdays'],
      lat:
          (() {
            final v = json['lat'];
            if (v is double) return v;
            if (v is int) return v.toDouble();
            if (v is String) return double.tryParse(v) ?? 0.0;
            return 0.0;
          })(),
      lng:
          (() {
            final v = json['lng'];
            if (v is double) return v;
            if (v is int) return v.toDouble();
            if (v is String) return double.tryParse(v) ?? 0.0;
            return 0.0;
          })(),
      locations:
          (json['locations'] as List?)
              ?.whereType<Map>()
              .map((e) => JobLocation.fromJson(Map<String, dynamic>.from(e)))
              .where((l) => l.hasGeo)
              .toList() ??
          const [],
      isNationwide:
          json['is_nationwide'] == 1 ||
          json['is_nationwide'] == true ||
          json['is_nationwide'] == '1',

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
      isCertifiedCompany:
          json['is_certified_company'] == 1 ||
          json['is_certified_company'] == true,
      isPaid:
          json['is_paid'] == null
              ? true
              : (json['is_paid'] == 1 || json['is_paid'] == true),
      isUrgent: json['is_urgent'] == 1 || json['is_urgent'] == true,
      isAgency:
          json['is_agency'] == 1 ||
          json['is_agency'] == true ||
          json['isAgency'] == 1 ||
          json['isAgency'] == true,

      agencyPhone: (json['agency_phone'] ?? json['agencyPhone'])?.toString(),
      agencyEmail: (json['agency_email'] ?? json['agencyEmail'])?.toString(),
      agencyNote: (json['agency_note'] ?? json['agencyNote'])?.toString(),
      externalApplyEnabled:
          json['external_apply_enabled'] == 1 ||
          json['external_apply_enabled'] == true ||
          json['externalApplyEnabled'] == 1 ||
          json['externalApplyEnabled'] == true,
      externalApplyUrl:
          (json['external_apply_url'] ?? json['externalApplyUrl'])?.toString(),
      externalApplyLabel:
          (json['external_apply_label'] ?? json['externalApplyLabel'])
              ?.toString(),

      matchScore: () {
        final v = json['score'] ?? json['matchScore'];
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v);
        return null;
      }(),
      matchReasons: () {
        final v = json['reasons'] ?? json['matchReasons'];
        if (v is List) return v.map((e) => e.toString()).toList();
        if (v is String) {
          try {
            final parsed = jsonDecode(v);
            if (parsed is List) return parsed.map((e) => e.toString()).toList();
          } catch (_) {}
        }
        return <String>[];
      }(),
      zeroApplicantRefunded:
          json['zero_applicant_refunded'] == 1 ||
          json['zero_applicant_refunded'] == true,
      jobType: (json['job_type'] ?? 'short').toString(),
      isAlwaysOpen:
          json['is_always_open'] == 1 || json['is_always_open'] == true,
      workDaysPerWeek:
          json['work_days_per_week'] != null
              ? int.tryParse(json['work_days_per_week'].toString())
              : null,
      requiredCerts: json['required_certs']?.toString(),
      welfare: json['welfare']?.toString(),
    );
  }
  // Job 클래스 안에 추가 (toJson 위에)
  /// 대표 좌표 + 추가 근무지 전부. 좌표 없는 건 뺀다.
  List<JobLocation> get geoPoints => [
    if (lat != 0.0 && lng != 0.0)
      JobLocation(address: location, locationCity: locationCity, lat: lat, lng: lng),
    ...locations.where((l) => l.hasGeo),
  ];

  /// 가장 가까운 근무지. 좌표가 하나도 없으면 null.
  JobLocation? nearestFrom(double fromLat, double fromLng) {
    JobLocation? best;
    double bestD = double.infinity;
    for (final p in geoPoints) {
      final d = haversineKm(fromLat, fromLng, p.lat, p.lng);
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }

  /// 근무지 중 가장 가까운 거리(km). 좌표가 하나도 없으면 null.
  double? distanceKmFrom(double fromLat, double fromLng) {
    final nearest = nearestFrom(fromLat, fromLng);
    if (nearest == null) return null;
    return haversineKm(fromLat, fromLng, nearest.lat, nearest.lng);
  }

  /// 목록 거리 필터. 근무지가 여러 곳이면 하나만 반경 안에 있어도 통과다.
  ///
  /// 전국 공고와 좌표 없는 공고는 거르지 않는다 — 여기서 버리면 사장님이
  /// 올린 공고가 아무에게도 안 보인다.
  bool withinRadiusKm(double fromLat, double fromLng, double radiusKm) {
    if (isNationwide) return true;
    final d = distanceKmFrom(fromLat, fromLng);
    if (d == null) return true;
    return d <= radiusKm;
  }

  /// 근무지 지역 라벨. 여러 곳이면 '고양 · 수원 · 제주'.
  String get regionLabel {
    if (isNationwide) return '전국';
    final cities = <String>[];
    for (final c in [locationCity, ...locations.map((l) => l.locationCity ?? '')]) {
      final v = c.trim();
      if (v.isNotEmpty && !cities.contains(v)) cities.add(v);
    }
    if (cities.isEmpty) return locationCity;
    return cities.join(' · ');
  }

  Job copyWith({double? matchScore, List<String>? matchReasons}) {
    return Job(
      id: id,
      userNumber: userNumber,
      title: title,
      location: location,
      locationCity: locationCity,
      pay: pay,
      payType: payType,
      startTime: startTime,
      endTime: endTime,
      category: category,
      description: description,
      company: company,
      createdAt: createdAt,
      startDate: startDate,
      endDate: endDate,
      publishAt: publishAt,
      pinnedUntil: pinnedUntil,
      expiresAt: expiresAt,
      weekdays: weekdays,
      lat: lat,
      lng: lng,
      locations: locations,
      isNationwide: isNationwide,
      imageUrls: imageUrls,
      status: status,
      chatRoomId: chatRoomId,
      clientId: clientId,
      workerId: workerId,
      isSameDayPay: isSameDayPay,
      isCertifiedCompany: isCertifiedCompany,
      isPaid: isPaid,
      isUrgent: isUrgent,
      isAgency: isAgency,
      agencyPhone: agencyPhone,
      agencyEmail: agencyEmail,
      agencyNote: agencyNote,
      externalApplyEnabled: externalApplyEnabled,
      externalApplyUrl: externalApplyUrl,
      externalApplyLabel: externalApplyLabel,
      matchScore: matchScore ?? this.matchScore,
      matchReasons: matchReasons ?? this.matchReasons,
      zeroApplicantRefunded: zeroApplicantRefunded,
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
      'locations': locations.map((l) => l.toJson()).toList(),
      'is_nationwide': isNationwide ? 1 : 0,
      'image_urls': imageUrls,
      'status': status,
      'chat_room_id': chatRoomId,
      'client_id': clientId,
      'worker_id': workerId,
      'is_same_day_pay': isSameDayPay,
      'is_certified_company': isCertifiedCompany ? 1 : 0,
      'is_paid': isPaid ? 1 : 0,
      'is_agency': isAgency ? 1 : 0,
      'agency_phone': agencyPhone,
      'agency_email': agencyEmail,
      'agency_note': agencyNote,
      'external_apply_enabled': externalApplyEnabled ? 1 : 0,
      'external_apply_url': externalApplyUrl,
      'external_apply_label': externalApplyLabel,
      'score': matchScore,
      'reasons': matchReasons,
      'zero_applicant_refunded': zeroApplicantRefunded ? 1 : 0,
    };
  }
}
