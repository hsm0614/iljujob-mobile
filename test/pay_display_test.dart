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
}
