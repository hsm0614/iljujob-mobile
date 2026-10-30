// StoreKit 전용 IAP 진입점 — 연합 패키지 in_app_purchase 대체.
//
// in_app_purchase를 의존하면 Flutter가 in_app_purchase_android까지 자동 등록해
// 안드로이드 AAB에 Play Billing 7.1.1이 들어간다. 안드로이드 결제는 PortOne이라
// 그 코드는 한 줄도 실행되지 않는데, Play Console이 "Billing 8.0.0 미만" 경고를 띄웠다.
// InAppPurchase.instance가 해주던 지연 등록만 그대로 옮겨 호출부는 손대지 않는다.
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

export 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart'
    show
        IAPError,
        InAppPurchaseException,
        InAppPurchasePlatform,
        ProductDetails,
        ProductDetailsResponse,
        PurchaseDetails,
        PurchaseParam,
        PurchaseStatus,
        PurchaseVerificationData;

bool _registered = false;

/// 결제 플랫폼. InAppPurchasePlatform.instance 는 late 라서 등록 전에 읽으면
/// 죽는다 — 반드시 이 getter로만 접근한다.
/// 안드로이드에서 불려도 네이티브는 purchaseStream 을 listen 할 때만 깨어나므로 무해.
InAppPurchasePlatform get iap {
  if (!_registered) {
    InAppPurchaseStoreKitPlatform.registerPlatform();
    _registered = true;
  }
  return InAppPurchasePlatform.instance;
}
