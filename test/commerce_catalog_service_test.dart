import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/data/models/commerce_product.dart';
import 'package:iljujob/data/services/commerce_catalog_service.dart';

void main() {
  test('서버 카탈로그의 묶음권과 v2 구독을 정확히 읽는다', () {
    final products = CommerceCatalogService.parseProducts({
      'products': [
        {
          'id': 'instant_3',
          'kind': 'pass',
          'passType': 'instant',
          'count': 3,
          'amount': 13900,
        },
        {
          'id': 'subscription_v2_pro',
          'kind': 'subscription',
          'plan': 'pro',
          'entitlementVersion': 'v2',
          'amount': 39900,
          'instant': 10,
          'urgent': 2,
          'maxRecipients': 20,
        },
      ],
    });

    expect(products, hasLength(2));
    expect(products.first.count, 3);
    expect(products.last.entitlementVersion, 'v2');
    expect(products.last.instant, 10);
    expect(products.last.urgent, 2);
  });

  test('알 수 없는 종류는 구매 후보에서 제외한다', () {
    expect(
      CommerceProduct.fromJson({'id': 'x', 'kind': 'mystery', 'amount': 1}),
      isNull,
    );
  });
}
