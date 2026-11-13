import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/utils/condition_guard.dart';

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
}
