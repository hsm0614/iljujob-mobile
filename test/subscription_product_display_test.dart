import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/data/models/subscription_product_config.dart';

void main() {
  test('신규 앱은 두 개의 v3 상품과 기간 제공량을 사용한다', () {
    expect(
      subscriptionProductConfigs.map((p) => p.iosId),
      contains('kr.co.iljujob.sub.v3.pro'),
    );
    expect(
      subscriptionProductConfigs.map((p) => p.androidId),
      contains('sub-v3-pro'),
    );
    expect(
      subscriptionProductConfigs.map(
        (p) => [
          p.key,
          p.price,
          p.instantCredits,
          p.directMonthly,
          p.pushMonthly,
        ],
      ),
      [
        ['lite', 29000, 3, 10, 2],
        ['pro', 95000, 0, 50, 8],
      ],
    );
    expect(subscriptionProductConfigs.last.unlimitedInstant, isTrue);
  });

  test('관리 화면은 기존 프로 권리와 신규 프로 권리를 구분한다', () {
    expect(subscriptionBenefitLabels('pro', 'legacy_v1').first, '즉시게시 무제한');
    expect(subscriptionBenefitLabels('pro', 'legacy_v1')[1], contains('5회'));
    expect(subscriptionBenefitLabels('pro', 'v2').first, '즉시게시 10회/월');
    expect(subscriptionBenefitLabels('pro', 'v2')[1], contains('2회'));
    expect(subscriptionBenefitLabels('pro', 'v3').first, '즉시게시 무제한');
    expect(
      subscriptionBenefitLabels('pro', 'v3').join(' '),
      contains('먼저 연락 50명'),
    );
    expect(
      subscriptionBenefitLabels('standard', 'v2').join(' '),
      isNot(contains('출근 안심')),
    );
  });

  test('라이트는 공고 AI 월 3회를 명시하고 프로만 공고 AI 무제한을 표시한다', () {
    expect(
      subscriptionBenefitLabels('lite', 'v3').join(' '),
      contains('AI 공고문 월 3회'),
    );
    expect(
      subscriptionBenefitLabels('pro', 'v3').join(' '),
      contains('AI 공고문 무제한'),
    );
  });

  test('복원 시 구독 상품만 서버 검증 대상으로 분류한다', () {
    expect(isSubscriptionProductId('kr.co.iljujob.sub.pro'), isTrue);
    expect(isSubscriptionProductId('sub-pro'), isTrue);
    expect(isSubscriptionProductId('kr.co.iljujob.sub.v3.pro'), isTrue);
    expect(isSubscriptionProductId('subscribe'), isTrue);
    expect(isSubscriptionProductId('instant_10'), isFalse);
    expect(isSubscriptionProductId('com.iljujob.pass30'), isFalse);
  });

  test('iOS만 App Store를 쓰고 그 외 플랫폼은 PortOne을 사용한다', () {
    expect(checkoutProviderForPlatform(isIos: true), CheckoutProvider.appStore);
    expect(checkoutProviderForPlatform(isIos: false), CheckoutProvider.portOne);
  });
}
