import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/data/models/pass_product_config.dart';

void main() {
  test('즉시게시 화면은 단건과 3·5·10회 묶음을 새 결제 금액으로 보여준다', () {
    expect(
      instantPassOptions.map((offer) => [offer['count'], offer['price']]),
      [
        [1, 8900],
        [3, 24900],
        [5, 36900],
        [10, 69900],
      ],
    );
  });
}
