class SubscriptionProductConfig {
  const SubscriptionProductConfig({
    required this.key,
    required this.name,
    required this.price,
    required this.instantCredits,
    required this.urgentCredits,
    required this.maxRecipients,
    required this.iosId,
    this.unlimitedInstant = false,
    this.priorityCs = false,
    this.recommended = false,
  });

  final String key;
  final String name;
  final int price;
  final int instantCredits;
  final int urgentCredits;
  final int maxRecipients;
  final bool unlimitedInstant;
  final bool priorityCs;
  final bool recommended;
  final String iosId;
}

enum CheckoutProvider { appStore, portOne }

CheckoutProvider checkoutProviderForPlatform({required bool isIos}) =>
    isIos ? CheckoutProvider.appStore : CheckoutProvider.portOne;

const subscriptionProductConfigs = [
  SubscriptionProductConfig(
    key: 'lite',
    name: '라이트',
    price: 9900,
    instantCredits: 3,
    urgentCredits: 0,
    maxRecipients: 10,
    iosId: 'kr.co.iljujob.sub.lite',
  ),
  SubscriptionProductConfig(
    key: 'standard',
    name: '스탠다드',
    price: 19900,
    instantCredits: 5,
    urgentCredits: 1,
    maxRecipients: 15,
    iosId: 'kr.co.iljujob.sub.standard',
    recommended: true,
  ),
  SubscriptionProductConfig(
    key: 'pro',
    name: '프로',
    price: 39900,
    instantCredits: 10,
    urgentCredits: 2,
    maxRecipients: 20,
    iosId: 'kr.co.iljujob.sub.pro',
    priorityCs: true,
  ),
];

const _legacySubscriptionProductIds = {
  'kr.co.iljujob.sub.lite',
  'kr.co.iljujob.sub.standard',
  'kr.co.iljujob.sub.pro',
  'sub-lite',
  'sub-standard',
  'sub-pro',
  'subscribe',
  'subscribe_1',
  'subscribe_1_month',
  'monthly_pro',
  'yearly_pro',
  'subscribe_12',
  'lite',
  'standard',
  'pro',
};

bool isSubscriptionProductId(String productId) {
  final id = productId.trim();
  return _legacySubscriptionProductIds.contains(id) ||
      subscriptionProductConfigs.any(
        // 스토어 구매는 iOS 뿐이다 — 안드로이드는 포트원으로 결제한다.
        (product) => product.iosId == id,
      );
}

List<String> subscriptionBenefitLabels(
  String? plan,
  String? entitlementVersion,
) {
  final isLegacy =
      entitlementVersion == null || entitlementVersion == 'legacy_v1';
  final values =
      isLegacy
          ? const {
            'lite': (instant: '3회/월', urgent: 1, max: 10, unlimited: false),
            'standard': (instant: '3회/월', urgent: 3, max: 15, unlimited: false),
            'pro': (instant: '무제한', urgent: 5, max: 20, unlimited: true),
          }[plan]
          : const {
            'lite': (instant: '3회/월', urgent: 0, max: 10, unlimited: false),
            'standard': (instant: '5회/월', urgent: 1, max: 15, unlimited: false),
            'pro': (instant: '10회/월', urgent: 2, max: 20, unlimited: false),
          }[plan];
  if (values == null) return const [];
  return [
    '즉시게시 ${values.instant}',
    '긴급호출 ${values.urgent}회/월 (반경 5km, 최대 ${values.max}명)',
    'AI 기능 무제한 (맞춤인재·인사이트·임금리포트)',
    '구독 배지 표시',
    if (plan == 'pro') '우선 CS 지원',
  ];
}
