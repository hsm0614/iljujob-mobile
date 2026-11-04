import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/utils/profile_completeness.dart';

void main() {
  test('빈 값·빈 배열 문자열은 안 채운 것으로 센다', () {
    final r = profileCompleteness({'gender': 'male', 'desired_work': '[]', 'strengths': ' ', 'introduction': null});
    expect(r.percent, 17); // 6개 중 성별 하나
    expect(r.next, '가능한 요일'); // 쉬운 순 첫 번째
  });

  test('목록 값도 받고, 다 채우면 100%·다음 없음', () {
    final r = profileCompleteness({
      'available_days': ['월', '화'],
      'desired_work': '["카페"]',
      'strengths': '성실',
      'gender': 'female',
      'introduction': '안녕하세요',
      'profile_image_url': '/uploads/a.jpg',
    });
    expect(r.percent, 100);
    expect(r.next, isNull);
  });

  test('을/를은 받침에 따라', () {
    expect(objectParticle('자기소개'), '를');
    expect(objectParticle('가능한 요일'), '을');
    expect(objectParticle('프로필 사진'), '을');
  });
}
