import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/utils/chat_stage.dart';

void main() {
  final now = DateTime(2026, 10, 28, 10);
  String? w(Map<String, dynamic> a) => chatStageOf(
    isWorker: a['worker'] ?? true,
    workStatus: a['work'],
    workDate: a['date'],
    urgentStatus: a['urgent'],
    isUrgent: a['urgent'] != null,
    applicationStatus: a['app'],
    now: now,
  )?.label;

  test('채팅 단계: 긴급호출 수락은 출근 확정이 아니다', () {
    expect(w({'urgent': 'accepted'}), '출근 제안 기다리는 중');
    expect(w({'urgent': 'accepted', 'worker': false}), '출근 제안 보내기');
    expect(w({'urgent': 'sent'}), '긴급호출 응답 필요');
    expect(w({'urgent': 'accepted', 'work': 'proposed', 'date': '2026-10-30'}), '출근 제안 확인 필요');
    expect(w({'work': 'proposed', 'date': '2026-06-12'}), '지난 출근 제안');
    expect(w({'work': 'day_of_confirmed', 'date': '2026-10-28'}), '출근 예정');
    expect(w({'work': 'accepted', 'date': '2026-10-27'}), '근무일 지남');
    expect(w({'app': 'confirmed'}), '채용 확정');
    expect(w({'app': 'applied'}), isNull);
    expect(isWorkDatePast('2026-10-27T15:00:00.000Z', now: now), isTrue);
  });
}
