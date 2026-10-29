import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/presentation/screens/mypagescreen/event_detail_screen.dart';

void main() {
  test('이벤트 기간: DATE 앞 10자리, 마지막 날까지 진행 중', () {
    final e = {'start_date': '2026-10-01T00:00:00.000Z', 'end_date': '2026-10-27T00:00:00.000Z'};
    expect(eventPeriod(e), '2026.10.01 ~ 2026.10.27');
    expect(eventOngoing(e, now: DateTime(2026, 10, 27, 23, 59)), isTrue);
    expect(eventOngoing(e, now: DateTime(2026, 10, 28)), isFalse);
    expect(eventOngoing(e, now: DateTime(2026, 9, 30)), isFalse);
    expect(eventOngoing({'start_date': null, 'end_date': null}), isTrue);
  });
}
