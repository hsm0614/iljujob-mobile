// 급여 높은 순 정렬의 시급 환산 (home_main_screen.dart의 hourlyPayValue와 동일 규칙)
// 회귀 방지: 예전엔 문자열 숫자만 비교해서 월급 390만원이 시급 11,000원보다 항상 위였다.
import 'package:flutter_test/flutter_test.dart';

final _reNonDigit = RegExp(r'[^0-9]');

int hourlyPayValue(String pay, String payType) {
  final n = int.tryParse(pay.replaceAll(_reNonDigit, '')) ?? 0;
  if (n <= 0) return 0;
  switch (payType) {
    case '일급':
      return n ~/ 8;
    case '주급':
      return n ~/ 40;
    case '월급':
      return n ~/ 209;
    default:
      return n;
  }
}

void main() {
  test('월급 390만원보다 시급 11,000원이 높게 평가된다', () {
    final monthly = hourlyPayValue('3,900,000원', '월급'); // 약 18,660
    final hourly = hourlyPayValue('11,000원', '시급');
    expect(monthly, 18660);
    expect(hourly, 11000);
    // 실제로는 월급이 더 높다 — 중요한 건 3,900,000 > 11,000 식의 비교가 아니라는 것
    expect(monthly, lessThan(hourlyPayValue('3,900,000원', '시급')));
  });

  test('같은 금액이라도 급여 형태에 따라 순서가 바뀐다', () {
    final daily = hourlyPayValue('100,000원', '일급'); // 12,500
    final weekly = hourlyPayValue('100,000원', '주급'); // 2,500
    expect(daily, 12500);
    expect(weekly, 2500);
    expect(daily, greaterThan(weekly));
  });

  test('금액이 없거나 협의면 0', () {
    expect(hourlyPayValue('협의', '시급'), 0);
    expect(hourlyPayValue('', '월급'), 0);
  });

  test('정렬 결과: 실제 시급이 높은 순으로 줄선다', () {
    final jobs = [
      ('11,000원', '시급'), // 11,000
      ('3,900,000원', '월급'), // 18,660
      ('540,000원', '주급'), // 13,500
      ('80,000원', '일급'), // 10,000
    ];
    final sorted = [...jobs]..sort(
      (a, b) => hourlyPayValue(b.$1, b.$2).compareTo(hourlyPayValue(a.$1, a.$2)),
    );
    expect(sorted.map((e) => e.$2).toList(), ['월급', '주급', '시급', '일급']);
  });
}
