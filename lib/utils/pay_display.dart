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

/// 일급 ÷ 근무시간 → '11,250원' (레퍼런스의 '시급 13,000원'). 계산 못 하면 null.
/// 휴게시간은 모른다 — 공고에 없어서 단순 나눗셈. 야간(22:00~06:00)은 자정을 넘겨 계산.
String? hourlyFromDaily(String pay, String payType, String workingHours) {
  if (payType != '일급') return null;
  final n = int.tryParse(pay.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  final m = RegExp(
    r'(\d{1,2}):(\d{2})\s*~\s*(\d{1,2}):(\d{2})',
  ).firstMatch(workingHours);
  if (n <= 0 || m == null) return null;
  final start = int.parse(m[1]!) * 60 + int.parse(m[2]!);
  var end = int.parse(m[3]!) * 60 + int.parse(m[4]!);
  if (end <= start) end += 24 * 60;
  final hours = (end - start) / 60;
  if (hours < 1) return null;
  final hourly = (n / hours / 10).round() * 10;
  return '${NumberFormat('#,###').format(hourly)}원';
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
