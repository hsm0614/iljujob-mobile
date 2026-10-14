import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/utils/publish_timing.dart';

void main() {
  test('오후 3시 무료 등록 → 내일 새벽 3시 공개, 알림 내일 오전 9시', () {
    final now = DateTime.utc(2026, 10, 14, 15);
    final pub = freePublishAt(now);
    expect(kstWhenLabel(pub, now), '내일 오전 3시');
    expect(kstWhenLabel(freeFirstPushAt(pub), now), '내일 오전 9시');
  });

  test('밤 10시 30분 무료 등록 → 내일 오전 10시 30분 공개, 알림 모레 9시', () {
    final now = DateTime.utc(2026, 10, 14, 22, 30);
    final pub = freePublishAt(now);
    expect(kstWhenLabel(pub, now), '내일 오전 10시 30분');
    expect(kstWhenLabel(freeFirstPushAt(pub), now), '10월 16일 오전 9시');
  });

  test('정오 공개는 오후 12시, 자정 넘김·연말 리셋', () {
    final now = DateTime.utc(2026, 12, 31, 0);
    expect(kstWhenLabel(freePublishAt(now), now), '오늘 오후 12시');
    expect(nextFreeResetAt(now), DateTime.utc(2027, 1, 1));
  });

  test('유료 알림은 08~20시만 즉시', () {
    expect(paidPushesNow(DateTime.utc(2026, 10, 14, 8)), isTrue);
    expect(paidPushesNow(DateTime.utc(2026, 10, 14, 20, 59)), isTrue);
    expect(paidPushesNow(DateTime.utc(2026, 10, 14, 21)), isFalse);
    expect(paidPushesNow(DateTime.utc(2026, 10, 14, 7)), isFalse);
  });

  test('표 칸 짧은 형태', () {
    final now = DateTime.utc(2026, 10, 14, 15, 5);
    expect(kstWhenShort(freePublishAt(now), now), '내일 03:05');
  });
}
