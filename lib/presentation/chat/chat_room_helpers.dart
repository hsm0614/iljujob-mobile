// lib/presentation/chat/chat_room_helpers.dart
//
// 채팅방 화면에서 사용하는 순수 유틸 함수 모음.
// - setState / context / ChangeNotifier 의존 없음
// - 어디서든 import해서 바로 사용 가능

import 'dart:math' as math;
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────
// Bool 변환
// ─────────────────────────────────────────────

/// 숫자(0/1), 문자열("true"/"1"/"yes"), bool 모두 처리
bool asBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes' || s == 'y';
}

// ─────────────────────────────────────────────
// 시각 → 밀리초 변환
// ─────────────────────────────────────────────

/// epoch(초/밀리초/마이크로초), ISO 문자열, "YYYY-MM-DD HH:mm:ss" 등 모두 처리.
/// 파싱 실패 시 0 반환.
int toMs(dynamic v) {
  if (v == null) return 0;

  if (v is int) {
    final len = v.toString().length;
    if (len >= 16) {
      return DateTime.fromMicrosecondsSinceEpoch(v, isUtc: true)
          .millisecondsSinceEpoch;
    }
    if (len >= 13) {
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true)
          .millisecondsSinceEpoch;
    }
    return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true)
        .millisecondsSinceEpoch;
  }

  final s = v.toString().trim();
  if (RegExp(r'^\d+$').hasMatch(s)) return toMs(int.parse(s));

  DateTime? dt =
      DateTime.tryParse(s) ?? DateTime.tryParse(s.replaceFirst(' ', 'T'));

  if (dt == null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
    final p = s.split('-');
    dt = DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  if (dt == null) return 0;
  return (dt.isUtc ? dt : dt.toUtc()).millisecondsSinceEpoch;
}

// ─────────────────────────────────────────────
// 서버 시각 파싱 (로컬 시간 반환)
// ─────────────────────────────────────────────

/// 서버/소켓에서 오는 다양한 시각 표현 → 로컬 DateTime
/// - int epoch (초/밀리초/마이크로초)
/// - ISO8601 (타임존 포함/미포함)
/// - "YYYY-MM-DD HH:mm:ss(.SSS)"
/// 파싱 실패 시 null 반환
DateTime? parseServerTime(dynamic v) {
  if (v == null) return null;

  DateTime toLocal(DateTime dt) => dt.toLocal();

  // A) 정수 epoch
  if (v is int) {
    final len = v.toString().length;
    if (len >= 16) {
      return toLocal(DateTime.fromMicrosecondsSinceEpoch(v, isUtc: true));
    }
    if (len >= 13) {
      return toLocal(DateTime.fromMillisecondsSinceEpoch(v, isUtc: true));
    }
    return toLocal(DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true));
  }

  final s = v.toString().trim();
  if (s.isEmpty) return null;

  // B) 숫자 문자열 epoch
  if (RegExp(r'^\d+$').hasMatch(s)) {
    final n = int.tryParse(s);
    if (n != null) return parseServerTime(n);
  }

  // C) ISO8601 + 타임존 (Z 또는 +hh:mm)
  if (RegExp(r'T.*(Z|[+-]\d{2}:\d{2})$').hasMatch(s)) {
    final dt = DateTime.tryParse(s);
    return dt == null ? null : toLocal(dt);
  }

  // D) ISO8601 타임존 없음 → UTC로 간주
  if (RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$').hasMatch(s)) {
    final dt = DateTime.tryParse('${s}Z');
    return dt == null ? null : toLocal(dt);
  }

  // E) "YYYY-MM-DD HH:mm:ss(.SSS)" → UTC로 간주
  if (RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d+)?$').hasMatch(s)) {
    final iso = s.replaceFirst(' ', 'T');
    final dt = DateTime.tryParse('${iso}Z');
    return dt == null ? null : toLocal(dt);
  }

  // F) 마지막 시도
  final dt = DateTime.tryParse(s);
  return dt == null ? null : toLocal(dt);
}

// ─────────────────────────────────────────────
// 날짜/시간 파싱 (느슨한 버전)
// ─────────────────────────────────────────────

/// YYYY-MM-DD 날짜만 있는 값은 로컬 자정으로 안전 파싱.
/// 그 외는 [parseServerTime]에 위임.
DateTime? parseDateLoose(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;

  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  return parseServerTime(v);
}

/// "09:00", "09:00:30", epoch, ISO 등 느슨하게 파싱 → 로컬 시간
DateTime? parseTimeLoose(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;

  final s = v.toString().trim();
  if (s.isEmpty) return null;

  // 숫자 epoch
  if (RegExp(r'^\d+$').hasMatch(s)) {
    final n = int.parse(s);
    final len = s.length;
    final dtUtc = len >= 16
        ? DateTime.fromMicrosecondsSinceEpoch(n, isUtc: true)
        : len >= 13
            ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true)
            : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
    return dtUtc.toLocal();
  }

  // HH:mm(:ss)
  final m1 = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(s);
  if (m1 != null) {
    final h = int.parse(m1.group(1)!);
    final m = int.parse(m1.group(2)!);
    final sec = m1.group(3) != null ? int.parse(m1.group(3)!) : 0;
    return DateTime(1970, 1, 1, h, m, sec);
  }

  // HHmm (예: "0930")
  final m2 = RegExp(r'^(\d{2})(\d{2})$').firstMatch(s);
  if (m2 != null) {
    return DateTime(1970, 1, 1, int.parse(m2.group(1)!), int.parse(m2.group(2)!));
  }

  final dt = DateTime.tryParse(s) ??
      DateTime.tryParse(s.replaceFirst(' ', 'T')) ??
      DateTime.tryParse('${s}Z');
  return dt?.toLocal();
}

// ─────────────────────────────────────────────
// 포맷 출력
// ─────────────────────────────────────────────

/// "오전 9:00" 형태 (ko_KR)
String formatHm(DateTime d) => DateFormat('a h:mm', 'ko_KR').format(d);

/// "yyyy-MM-dd" 형태
String formatDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// 근무시간: "오전 9:00 ~ 오후 6:00" / 자정 넘기면 "(익일)" 추가
String formatTimeRange(dynamic startRaw, dynamic endRaw) {
  final s = parseTimeLoose(startRaw);
  final e = parseTimeLoose(endRaw);

  if (s == null && e == null) return '시간 미정';
  if (s != null && e == null) return '${formatHm(s)} ~';
  if (s == null && e != null) return '~ ${formatHm(e)}';

  final sSec = secondsOfDay(s!);
  final eSec = secondsOfDay(e!);
  final crossMidnight = eSec <= sSec;

  final base = '${formatHm(s)} ~ ${formatHm(e)}';
  return crossMidnight ? '$base (익일)' : base;
}

/// 근무기간: "yyyy-MM-dd ~ yyyy-MM-dd" / 하루면 날짜 하나만
String formatPeriod(dynamic startRaw, dynamic endRaw) {
  final start = parseDateLoose(startRaw);
  final end = parseDateLoose(endRaw);

  if (start == null && end == null) return '기간 미정';
  if (start != null && end == null) return '${formatDate(start)} ~';
  if (start == null && end != null) return '~ ${formatDate(end)}';

  if (start!.year == end!.year &&
      start.month == end.month &&
      start.day == end.day) {
    return formatDate(start);
  }
  return '${formatDate(start)} ~ ${formatDate(end)}';
}

// ─────────────────────────────────────────────
// 시간 보조
// ─────────────────────────────────────────────

/// 하루 기준 총 초 수 (자정 초과 판별용)
int secondsOfDay(DateTime t) => t.hour * 3600 + t.minute * 60 + t.second;

// ─────────────────────────────────────────────
// GPS 거리 계산
// ─────────────────────────────────────────────

double _toRad(double x) => x * math.pi / 180.0;

/// Haversine 공식으로 두 좌표 간 거리(미터) 계산
int haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const R = 6371000.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return (R * 2 * math.asin(math.sqrt(a))).round();
}

// ─────────────────────────────────────────────
// 숫자 변환
// ─────────────────────────────────────────────

double? asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}