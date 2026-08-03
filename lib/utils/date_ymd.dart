/// 근무일(벽시계 날짜)을 'YYYY-MM-DD' 문자열로 변환한다.
///
/// ⚠️ `toIso8601String().split('T')[0]` 을 쓰면 안 된다.
/// 그 함수는 UTC로 변환한 뒤 날짜를 자르기 때문에, KST 자정 근처(21:00 이후)에
/// 로컬 날짜와 UTC 날짜가 달라져 근무일이 하루 앞으로 밀린다.
///
/// 서버의 start_date/end_date는 DATE 컬럼(벽시계 의미)이므로 타임존 변환 없이
/// 사용자가 고른 로컬 날짜를 그대로 보내야 한다. (CLAUDE.md 시간 컨벤션)
String toYmd(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
