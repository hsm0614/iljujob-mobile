// 홈 공고 리스트에 AI 추천 스트립을 N번째 뒤에 끼워넣을 때
// 공고가 밀리거나 중복/누락되지 않는지 (home_main_screen.dart의 삽입 규칙과 동일)
import 'package:flutter_test/flutter_test.dart';

const _aiStripAfter = 4;

/// index → 표시할 것. null이면 스트립, 아니면 filteredJobs의 인덱스.
({int itemCount, List<int?> mapping}) layout(int visibleCount) {
  final stripAt = visibleCount > _aiStripAfter ? _aiStripAfter : -1;
  final itemCount = visibleCount + (stripAt >= 0 ? 1 : 0);
  final mapping = <int?>[];
  for (var index = 0; index < itemCount; index++) {
    if (stripAt >= 0 && index == stripAt) {
      mapping.add(null);
    } else {
      mapping.add((stripAt >= 0 && index > stripAt) ? index - 1 : index);
    }
  }
  return (itemCount: itemCount, mapping: mapping);
}

void main() {
  test('공고 5개 — 4번째 뒤에 스트립, 공고는 0..4 그대로', () {
    final r = layout(5);
    expect(r.itemCount, 6);
    expect(r.mapping, [0, 1, 2, 3, null, 4]);
  });

  test('공고가 4개 이하면 스트립을 넣지 않는다', () {
    expect(layout(4).mapping, [0, 1, 2, 3]);
    expect(layout(1).mapping, [0]);
    expect(layout(0).mapping, isEmpty);
  });

  test('공고 인덱스가 빠짐없이 정확히 한 번씩 나온다', () {
    for (final n in [5, 6, 10, 23]) {
      final jobIndexes = layout(n).mapping.whereType<int>().toList();
      expect(jobIndexes, List.generate(n, (i) => i), reason: 'visibleCount=$n');
    }
  });
}
