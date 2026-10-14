/// 공고 공개·알림 시각 안내용. 서버 규칙을 그대로 옮긴 것이다 — 바뀌면 같이 고칠 것.
///  - 무료 공개: 등록 + 12시간 (`lib/jobPostPolicy.js` FREE_PUBLISH_DELAY_HOURS)
///  - 자동 알림: 08~20시는 즉시, 그 외와 무료 공고는 오전 9시 배치
///    (`utils/aiPush.js` NIGHT_START/END, `schedulers/pushScheduler.js`)
///
/// 시각은 전부 KST 벽시계 값으로 다룬다(기기 타임존 무관).
DateTime kstNow() => DateTime.now().toUtc().add(const Duration(hours: 9));

DateTime freePublishAt(DateTime nowKst) =>
    nowKst.add(const Duration(hours: 12));

/// 공개 시각 이후 첫 오전 9시. 무료 공고의 첫 알림.
DateTime freeFirstPushAt(DateTime publishKst) {
  final nine = DateTime.utc(
    publishKst.year,
    publishKst.month,
    publishKst.day,
    9,
  );
  return publishKst.isAfter(nine) ? nine.add(const Duration(days: 1)) : nine;
}

/// 유료 공고 첫 알림이 지금 나가는지(야간이면 오전 9시로 밀린다).
bool paidPushesNow(DateTime nowKst) => nowKst.hour >= 8 && nowKst.hour < 21;

/// 다음 달 1일. 무료 한도가 다시 채워지는 날.
DateTime nextFreeResetAt(DateTime nowKst) =>
    DateTime.utc(nowKst.year, nowKst.month + 1, 1);

/// '오늘 오후 3시', '내일 오전 2시 30분', '10월 16일 오전 9시'
String kstWhenLabel(DateTime t, DateTime nowKst) {
  final today = DateTime.utc(nowKst.year, nowKst.month, nowKst.day);
  final days = DateTime.utc(t.year, t.month, t.day).difference(today).inDays;
  final day =
      days == 0
          ? '오늘'
          : days == 1
          ? '내일'
          : '${t.month}월 ${t.day}일';
  final ampm = t.hour < 12 ? '오전' : '오후';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final min = t.minute == 0 ? '' : ' ${t.minute}분';
  return '$day $ampm $h시$min';
}

/// 표 칸용 짧은 형태: '오늘 15:00', '내일 03:00', '10/16 09:00'
String kstWhenShort(DateTime t, DateTime nowKst) {
  final today = DateTime.utc(nowKst.year, nowKst.month, nowKst.day);
  final days = DateTime.utc(t.year, t.month, t.day).difference(today).inDays;
  final day =
      days == 0
          ? '오늘'
          : days == 1
          ? '내일'
          : '${t.month}/${t.day}';
  String two(int v) => v.toString().padLeft(2, '0');
  return '$day ${two(t.hour)}:${two(t.minute)}';
}
