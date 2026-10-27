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
}
