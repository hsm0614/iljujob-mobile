import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/utils/condition_guard.dart';
import 'package:iljujob/utils/minimum_wage.dart';

void main() {
  test('최저시급·공고 시급·일급(휴게 뺀 시간) 비교', () {
    expect(checkConditions(hourly: 9000, start: '10:00', end: '18:00').first.$1, false);
    final ok = checkConditions(hourly: 16000, start: '10:00', end: '18:00', jobPay: 120000, jobPayType: '일급');
    expect(ok.every((c) => c.$1), true); // 16,000 × 7.5시간 = 120,000
    final low = checkConditions(hourly: 15000, start: '10:00', end: '18:00', jobPay: 120000, jobPayType: '일급');
    expect(low.last.$1, false); // 112,500 < 120,000
    expect(checkConditions(hourly: 12000, start: '09:00', end: '13:00', jobPay: 13000, jobPayType: '시급').last.$1, false);
    expect(checkConditions(hourly: 120000, start: '09:00', end: '18:00'), isEmpty); // 예전 카드(일급이 시급 칸에)
  });

  test('2027-01-01 KST 경계에서 최저시급·월급 기준이 바뀐다', () {
    expect(
      minimumHourlyWageForDate(null, now: DateTime.utc(2026, 12, 31, 14, 59)),
      10320,
    );
    expect(
      minimumHourlyWageForDate(null, now: DateTime.utc(2026, 12, 31, 15)),
      10700,
    );
    expect(minimumHourlyWageForYmd('2026-12-31'), 10320);
    expect(minimumHourlyWageForYmd('2027-01-01'), 10700);
    expect(
      minimumHourlyWageForRange(DateTime(2026, 12, 31), DateTime(2027, 1, 1)),
      10700,
    );
    expect(
      minimumHourlyWageForYmd('2027-01-01') * monthlyMinimumWageHours,
      2236300,
    );
  });

  test('근무일 기준으로 같은 10,320원 제안의 판정이 달라진다', () {
    final before = checkConditions(
      hourly: 10320,
      start: '09:00',
      end: '13:00',
      workDateYmd: '2026-12-31',
    );
    final after = checkConditions(
      hourly: 10320,
      start: '09:00',
      end: '13:00',
      workDateYmd: '2027-01-01',
    );
    expect(before.first.$1, true);
    expect(after.first.$1, false);
    expect(after.first.$2, contains('10,700원'));
  });
}
