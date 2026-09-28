import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/data/models/subscription_product_config.dart';

void main() {
  test('신규 앱은 기존 스토어 상품 ID와 v2 혜택을 사용한다', () {
    expect(
      subscriptionProductConfigs.map((p) => p.iosId),
      contains('kr.co.iljujob.sub.pro'),
    );
    expect(
      subscriptionProductConfigs.map((p) => p.androidId),
      contains('sub-pro'),
    );
    expect(
      subscriptionProductConfigs.map(
        (p) => [p.key, p.instantCredits, p.urgentCredits],
      ),
      [
        ['lite', 3, 0],
        ['standard', 5, 1],
        ['pro', 10, 2],
      ],
    );
    expect(subscriptionProductConfigs.any((p) => p.unlimitedInstant), isFalse);
  });

  test('관리 화면은 기존 프로 권리와 신규 프로 권리를 구분한다', () {
    expect(subscriptionBenefitLabels('pro', 'legacy_v1').first, '즉시게시 무제한');
    expect(subscriptionBenefitLabels('pro', 'legacy_v1')[1], contains('5회'));
    expect(subscriptionBenefitLabels('pro', 'v2').first, '즉시게시 10회/월');
    expect(subscriptionBenefitLabels('pro', 'v2')[1], contains('2회'));
    expect(
      subscriptionBenefitLabels('standard', 'v2').join(' '),
      isNot(contains('출근 안심')),
    );
  });

  test('복원 시 구독 상품만 서버 검증 대상으로 분류한다', () {
    expect(isSubscriptionProductId('kr.co.iljujob.sub.pro'), isTrue);
    expect(isSubscriptionProductId('sub-pro'), isTrue);
    expect(isSubscriptionProductId('subscribe'), isTrue);
    expect(isSubscriptionProductId('instant_10'), isFalse);
    expect(isSubscriptionProductId('com.iljujob.pass30'), isFalse);
  });

  test('iOS만 App Store를 쓰고 그 외 플랫폼은 PortOne을 사용한다', () {
    expect(checkoutProviderForPlatform(isIos: true), CheckoutProvider.appStore);
    expect(checkoutProviderForPlatform(isIos: false), CheckoutProvider.portOne);
  });
}
