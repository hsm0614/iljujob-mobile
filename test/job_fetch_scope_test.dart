import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/utils/job_fetch_scope.dart';

void main() {
  test('전국 보기에서는 서버 요청의 위치 제한을 제거한다', () {
    final scope = JobFetchScope.fromSelection(
      latitude: 37.5665,
      longitude: 126.9780,
      radiusKm: 30,
      nationwide: true,
    );

    expect(scope.latitude, isNull);
    expect(scope.longitude, isNull);
    expect(scope.radiusKm, isNull);
  });

  test('거리 보기에서는 선택한 위치와 반경을 서버 요청에 사용한다', () {
    final scope = JobFetchScope.fromSelection(
      latitude: 37.5665,
      longitude: 126.9780,
      radiusKm: 10,
      nationwide: false,
    );

    expect(scope.latitude, 37.5665);
    expect(scope.longitude, 126.9780);
    expect(scope.radiusKm, 10);
  });
}
