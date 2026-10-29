import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/data/models/commerce_product.dart';
import 'package:iljujob/data/models/pass_product_config.dart';

void main() {
  test('서버가 7일권을 공개하면 즉시게시 3일과 7일을 구분한다', () {
    const products = [
      CommerceProduct(
        id: 'instant_1',
        kind: 'pass',
        amount: 8900,
        passType: 'instant',
        count: 1,
      ),
      CommerceProduct(
        id: 'instant7_1',
        kind: 'pass',
        amount: 11900,
        passType: 'instant_7d',
        count: 1,
      ),
    ];
    final options = instantOptionsForCatalog(products);
    expect(options.map((o) => o['id']).toList(), ['instant_1', 'instant7_1']);
    expect(options.map((o) => o['days']).toList(), [3, 7]);
    expect(options.map((o) => o['price']).toList(), [8900, 11900]);
  });

  test('출시 전 카탈로그는 기존 7일 안내를 유지한다', () {
    const products = [
      CommerceProduct(
        id: 'instant_1',
        kind: 'pass',
        amount: 8900,
        passType: 'instant',
        count: 1,
      ),
    ];
    final options = instantOptionsForCatalog(products);
    expect(options.single['days'], 7);
  });
}
