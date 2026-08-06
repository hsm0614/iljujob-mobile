// 공고 카드 AI 요약 문구 (home_main_screen.dart의 _buildAiSummary와 동일 규칙)
// 회귀 방지: '의미유사'가 섞이면 "업무가 잘 맞아요 시급이 높고 잘 맞아요"처럼 깨졌었다.
import 'package:flutter_test/flutter_test.dart';

String? aiSummary({double? score, List<String> reasons = const []}) {
  if ((score == null || score < 0.6) && reasons.isEmpty) return null;

  const label = {
    '가까움': '가까움',
    '시간대겹침': '시간대 맞음',
    '시급상위': '시급 높음',
    '당일지급': '당일지급',
    '완료이력좋음': '이력 좋음',
    '의미유사': '업무 적합',
  };
  final parts = [
    for (final r in reasons.take(2))
      if (label.containsKey(r)) label[r]!,
  ];

  final pct = (score != null && score >= 0.7) ? ' ${(score * 100).round()}%' : '';
  final reasonText = parts.isEmpty ? '잘 맞는 공고예요' : parts.join(' · ');
  return 'AI 추천$pct · $reasonText';
}

void main() {
  test("'잘 맞아요'가 두 번 나오지 않는다", () {
    final s = aiSummary(score: 0.52, reasons: ['의미유사', '시급상위'])!;
    expect('잘 맞아요'.allMatches(s).length, lessThanOrEqualTo(1));
    expect(s, 'AI 추천 · 업무 적합 · 시급 높음');
  });

  test('낮은 점수(0.7 미만)는 퍼센트를 노출하지 않는다', () {
    expect(aiSummary(score: 0.52, reasons: ['가까움']), isNot(contains('52%')));
    expect(aiSummary(score: 0.85, reasons: ['가까움']), contains('85%'));
  });

  test('점수도 이유도 없으면 표시하지 않는다', () {
    expect(aiSummary(), isNull);
    expect(aiSummary(score: 0.3), isNull);
  });
}
