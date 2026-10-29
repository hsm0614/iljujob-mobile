import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/utils/pay_display.dart';

void main() {
  test('formats negotiable pay without showing zero won', () {
    expect(formatJobPay('0', '협의'), '급여 협의');
    expect(formatJobPay('', '협의'), '급여 협의');
  });

  test('formats fixed pay with number and optional pay type', () {
    expect(formatJobPay('120000', '일급'), '120,000원');
    expect(formatJobPay('120000', '일급', includeType: true), '일급 120,000원');
  });

  test('요일·지원 조건·게시 시각 표기', () {
    expect(formatWeekdays('월,화,수,목,금,토'), '월~토');
    expect(formatWeekdays('월,화,수,목,금'), '평일');
    expect(formatWeekdays('월,수'), '월·수');
    expect(formatRequirements('기초안전보건교육 이수증,배치전검진'), '기초안전보건교육 이수증 · 배치전검진');
    expect(formatRequirements('초보가능,'), '초보가능');
    expect(formatRequirements('없음'), isNull);
    expect(formatRequirements(null), isNull);
    final now = DateTime(2026, 10, 27, 15, 10);
    expect(formatPostedAgo(DateTime(2026, 10, 27, 15, 5).toUtc(), now: now), '5분 전');
    expect(formatPostedAgo(DateTime(2026, 10, 27, 9).toUtc(), now: now), '6시간 전');
    expect(formatPostedAgo(DateTime(2026, 10, 26, 20).toUtc(), now: now), '어제');
    expect(formatPostedAgo(DateTime(2026, 10, 10).toUtc(), now: now), '10월 10일');
  });

  test('근무일 표기 (사장님 내 공고 카드)', () {
    // KST 자정 = 전날 15:00Z — 앱이 들고 있는 형태
    DateTime kst(int m, int d) => DateTime.utc(2026, m, d).subtract(const Duration(hours: 9));
    expect(formatWorkDays(kst(11, 7), kst(11, 7), null), '11월 7일(토)');
    expect(formatWorkDays(kst(11, 7), kst(11, 8), null), '11월 7일(토) ~ 8일(일)');
    expect(formatWorkDays(kst(11, 30), kst(12, 2), null), '11월 30일(월) ~ 12월 2일(수)');
    expect(formatWorkDays(null, null, '토,일'), '주말');
    expect(formatWorkDays(null, null, null), isNull);
  });

  test('급여 단위 의심 — 서버 기준과 같다', () {
    expect(payUnitSuspect('시급', 12000), isNull);
    expect(payUnitSuspect('시급', 150000), contains('일급 금액'));
    expect(payUnitSuspect('일급', 1000000), isNull); // 경계는 통과
    expect(payUnitSuspect('일급', 3000000), contains('월급 금액'));
    expect(payUnitSuspect('월급', 300000), contains('시급이나 일급'));
    expect(payUnitSuspect('협의', 0), isNull);
  });
}
