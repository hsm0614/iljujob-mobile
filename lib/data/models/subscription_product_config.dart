class SubscriptionProductConfig {
  const SubscriptionProductConfig({
    required this.key,
    required this.name,
    required this.price,
    required this.instantCredits,
    required this.urgentCredits,
    required this.maxRecipients,
    required this.directMonthly,
    required this.directPerJob,
    required this.pushMonthly,
    required this.pushPerJob,
    required this.aiJobMonthly,
    required this.iosId,
    required this.androidId,
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
  final int directMonthly;
  final int directPerJob;
  final int pushMonthly;
  final int pushPerJob;
  final int aiJobMonthly;
  final bool unlimitedInstant;
  final bool priorityCs;
  final bool recommended;
  final String iosId;
  final String androidId;
}

enum CheckoutProvider { appStore, portOne }

CheckoutProvider checkoutProviderForPlatform({required bool isIos}) =>
    isIos ? CheckoutProvider.appStore : CheckoutProvider.portOne;

const subscriptionProductConfigs = [
  SubscriptionProductConfig(
    key: 'lite',
    name: '라이트',
    price: 29000,
    instantCredits: 3,
    urgentCredits: 0,
    maxRecipients: 10,
    directMonthly: 10,
    directPerJob: 10,
    pushMonthly: 2,
    pushPerJob: 1,
    aiJobMonthly: 3,
    iosId: 'kr.co.iljujob.sub.v3.lite',
    androidId: 'sub-v3-lite',
  ),
  SubscriptionProductConfig(
    key: 'pro',
    name: '프로',
    price: 95000,
    instantCredits: 0,
    urgentCredits: 0,
    maxRecipients: 20,
    directMonthly: 50,
    directPerJob: 20,
    pushMonthly: 8,
    pushPerJob: 2,
    aiJobMonthly: -1,
    iosId: 'kr.co.iljujob.sub.v3.pro',
    androidId: 'sub-v3-pro',
    unlimitedInstant: true,
    priorityCs: true,
    recommended: true,
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
        (product) => product.iosId == id || product.androidId == id,
      );
}

List<String> subscriptionBenefitLabels(
  String? plan,
  String? entitlementVersion,
) {
  final isLegacy =
      entitlementVersion == null || entitlementVersion == 'legacy_v1';
  if (entitlementVersion == 'v3') {
    final product = subscriptionProductConfigs.where(
      (item) => item.key == plan,
    );
    if (product.isEmpty) return const [];
    final selected = product.first;
    return [
      selected.unlimitedInstant
          ? '즉시게시 무제한'
          : '즉시게시 ${selected.instantCredits}회/결제기간',
      '먼저 연락 ${selected.directMonthly}명/결제기간 · 공고당 ${selected.directPerJob}명',
      '지도 알림 ${selected.pushMonthly}회/결제기간 · 공고당 ${selected.pushPerJob}회',
      selected.aiJobMonthly < 0
          ? 'AI 공고문 무제한'
          : 'AI 공고문 월 ${selected.aiJobMonthly}회',
      '구독 배지 표시',
    ];
  }
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
