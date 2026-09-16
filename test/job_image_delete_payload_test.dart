import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/data/services/job_service.dart';

void main() {
  test('여러 이미지 삭제 URL을 하나의 JSON 배열 필드로 보낸다', () {
    expect(
      JobService.encodeDeleteImageUrls([
        '/uploads/a.jpg',
        '',
        '/uploads/b.jpg',
      ]),
      '["/uploads/a.jpg","/uploads/b.jpg"]',
    );
  });
}
