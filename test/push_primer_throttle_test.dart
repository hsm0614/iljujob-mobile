import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/widget/push_permission.dart';
import 'package:shared_preferences/shared_preferences.dart';

// '나중에' 한 번에 영영 안 묻던 것(11-16) → 3일 간격 최대 5번
void main() {
  test('예전 앱에서 한 번 본 사람도 다시 물을 수 있고, 3일 안엔 안 묻고, 5번 뒤엔 그만', () async {
    SharedPreferences.setMockInitialValues({'push_primer_shown': true});
    final p = await SharedPreferences.getInstance();
    expect(await pushPrimerDue(p), isTrue);
    await markPushPrimerShown(p);
    expect(p.getInt('push_primer_count'), 2);
    expect(await pushPrimerDue(p), isFalse); // 방금 물음
    await p.setInt('push_primer_last_ms', 0);
    await p.setInt('push_primer_count', 5);
    expect(await pushPrimerDue(p), isFalse); // 상한
  });
}
