import 'package:intl/intl.dart';

bool isNegotiablePayType(String? payType) {
  return (payType ?? '').trim() == '협의';
}

String formatJobPay(
  String? rawPay,
  String? payType, {
  bool includeType = false,
}) {
  final type = (payType ?? '').trim();
  if (isNegotiablePayType(type)) return '급여 협의';

  final onlyNum = (rawPay ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  final n = int.tryParse(onlyNum) ?? 0;
  final amount = n > 0 ? NumberFormat('#,###').format(n) : '0';
  if (!includeType || type.isEmpty) return '$amount원';
  return '$type $amount원';
}

/// '월,화,수,목,금' → '평일', 7일 → '매일', '협의: 주 3회 이상' → '주 3회 이상'. 없으면 null
String? formatWeekdays(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return null;
  if (v.startsWith('협의')) {
    final t = v.replaceFirst(RegExp(r'^협의\s*:?\s*'), '').trim();
    return t.isEmpty ? '요일 협의' : t;
  }
  const order = '월화수목금토일';
  final days =
      v.split(',').map((e) => e.trim()).where(order.contains).toSet().toList()
        ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
  final joined = days.join();
  if (joined == '월화수목금') return '평일';
  if (joined == order) return '매일';
  if (joined == '토일') return '주말';
  if (days.length >= 3 && order.contains(joined)) {
    return '${days.first}~${days.last}';
  }
  return days.join('·');
}

/// 공고 '지원 조건'(사장님이 등록한 required_certs). '없음'·빈 값·끝 쉼표는 정리, 쉼표 구분은 ' · '로.
/// 설명 본문에서 뽑지 않는다 — 등록 데이터만 쓴다.
String? formatRequirements(String? raw) {
  final parts =
      (raw ?? '')
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && e != '없음')
          .toList();
  return parts.isEmpty ? null : parts.join(' · ');
}

/// 게시 시각 → '방금 전' · 'N분 전' · 'N시간 전' · '어제' · 'N일 전' · 'M월 D일'
String formatPostedAgo(DateTime postedUtc, {DateTime? now}) {
  final local = postedUtc.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final diff = n.difference(local);
  if (diff.isNegative) return '${local.month}월 ${local.day}일';
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  final days = DateTime(n.year, n.month, n.day)
      .difference(DateTime(local.year, local.month, local.day))
      .inDays;
  if (days == 0) return '${diff.inHours}시간 전';
  if (days == 1) return '어제';
  if (days < 7) return '$days일 전';
  return '${local.month}월 ${local.day}일';
}

/// 근무일 → '11월 7일(토)' · '11월 7일(토) ~ 8일(일)' · '11월 30일(일) ~ 12월 2일(화)'.
/// 날짜가 없으면 요일('주말'), 그것도 없으면 null. DATE는 KST 자정을 UTC로 들고 있어 toLocal로 되돌린다.
String? formatWorkDays(DateTime? start, DateTime? end, String? weekdays) {
  const wd = ['월', '화', '수', '목', '금', '토', '일'];
  String md(DateTime d, {bool month = true}) =>
      '${month ? '${d.month}월 ' : ''}${d.day}일(${wd[d.weekday - 1]})';
  if (start == null) return formatWeekdays(weekdays);
  final s = start.toLocal();
  final e = (end ?? start).toLocal();
  if (s.year == e.year && s.month == e.month && s.day == e.day) return md(s);
  return '${md(s)} ~ ${md(e, month: e.month != s.month)}';
}
