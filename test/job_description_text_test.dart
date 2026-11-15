import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/widget/job_description_text.dart';

// 실기기에서 본 공고(11-15) 모양 그대로: 대괄호 소제목 · 짧은 소제목 + 목록 · 빈 줄 여러 개
void main() {
  test('소제목·목록·문단을 나누고 글자는 바꾸지 않는다', () {
    const raw = '오프라인 현장 응대를 해주시는 역할입니다.\n\n\n[활동관련 안내]\n• 활동요일: 주 5일\n• 활동시간: 오전 9시 ~ 오후 6시\n\n보상안내\n- 시간 당 12000\n- 주 단위로 지급됩니다\n\n이런 분이면 잘 맞아요\n1. 기본적인 소통이 가능하신 분\n';
    final b = parseDescription(raw);
    String k(DescKind x) => x.name;
    expect(b.map((e) => '${k(e.kind)}:${e.text}').toList(), [
      'para:오프라인 현장 응대를 해주시는 역할입니다.',
      'gap:',
      'heading:활동관련 안내',
      'bullet:활동요일: 주 5일',
      'bullet:활동시간: 오전 9시 ~ 오후 6시',
      'gap:',
      'heading:보상안내',
      'bullet:시간 당 12000',
      'bullet:주 단위로 지급됩니다',
      'gap:',
      'heading:이런 분이면 잘 맞아요',
      'bullet:기본적인 소통이 가능하신 분',
    ]);
  });

  test('짧아도 마침표로 끝나면 소제목이 아니다', () {
    final b = parseDescription('처음이어도 괜찮아요.\n- 교육 있음');
    expect(b.first.kind, DescKind.para);
  });
}
