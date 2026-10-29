import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/utils/apply_stage.dart';

void main() {
  test('답장 대기 24시간 경과 · 답장 속도 문구', () {
    final now = DateTime(2026, 10, 27, 12);
    ApplyStage at(int h) => applyStageOf(
      jobStatus: 'active',
      appliedAt: now.subtract(Duration(hours: h)),
      now: now,
    );
    expect(at(3), ApplyStage.waiting);
    expect(at(25), ApplyStage.waitingLong);
    expect(at(25).group, 'waiting');
    expect(
      applyStageOf(jobStatus: 'active', clientReplied: true, appliedAt: now.subtract(const Duration(hours: 30)), now: now).next,
      '채팅 확인하기',
    );
    expect(replySpeedLabel(2, 2, 2), isNull);
    expect(replySpeedLabel(10, 5, 8), '보통 1시간 안에 답장해요');
    expect(replySpeedLabel(10, 2, 6), '보통 하루 안에 답장해요');
    expect(replySpeedLabel(10, 1, 3), isNull);
  });
}
