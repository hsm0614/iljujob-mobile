/// 고용노동부 고시 제2025-47호·제2026-60호. 근무일의 한국 날짜에 적용한다.
const minimumHourlyWage2026 = 10320;
const minimumHourlyWage2027 = 10700;
const monthlyMinimumWageHours = 209;

DateTime currentKstDate([DateTime? now]) {
  final kst = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  return DateTime.utc(kst.year, kst.month, kst.day);
}

/// DateTime의 연·월·일은 이미 사용자가 고른 근무지 달력 날짜다.
int minimumHourlyWageForDate(DateTime? workDate, {DateTime? now}) {
  final date = workDate ?? currentKstDate(now);
  return date.year >= 2027 ? minimumHourlyWage2027 : minimumHourlyWage2026;
}

/// 기간이 새해를 가로지르면 기간 안의 높은 기준으로 안내한다.
int minimumHourlyWageForRange(DateTime? start, DateTime? end, {DateTime? now}) {
  final first = minimumHourlyWageForDate(start, now: now);
  final last = minimumHourlyWageForDate(end, now: now);
  return first > last ? first : last;
}

/// 서버의 근무일은 시간대 변환 대상이 아닌 YYYY-MM-DD 벽시계 날짜다.
int minimumHourlyWageForYmd(String? ymd, {DateTime? now}) {
  final year = ymd == null ? null : int.tryParse(ymd.split('-').first);
  if (year == null) return minimumHourlyWageForDate(null, now: now);
  return year >= 2027 ? minimumHourlyWage2027 : minimumHourlyWage2026;
}
