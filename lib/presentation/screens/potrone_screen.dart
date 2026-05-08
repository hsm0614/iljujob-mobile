import 'package:flutter/material.dart';
import 'package:portone_flutter/iamport_payment.dart';
import 'package:portone_flutter/model/payment_data.dart';
import 'package:flutter/services.dart';

class PortonePaymentScreen extends StatefulWidget {
  final int count;
  final String companyName;
  final String companyPhone;

  // ✅ 추가: 할인 적용된 최종 결제 금액 (있으면 이 값으로 결제)
  final int? amount;

  // ✅ 추가: 적용된 쿠폰 코드(서버 검증/로그용)
  final String? couponCode;

  const PortonePaymentScreen({
    super.key,
    required this.count,
    required this.companyName,
    required this.companyPhone,
    this.amount,
    this.couponCode,
  });

  @override
  State<PortonePaymentScreen> createState() => _PortonePaymentScreenState();
}

class _PortonePaymentScreenState extends State<PortonePaymentScreen> {
  static const platform = MethodChannel('deeplink/albailju');

  late final String merchantUid;
  late final int price;

  bool _hasHandled = false;

  @override
  void initState() {
    super.initState();

    merchantUid = 'order_${DateTime.now().millisecondsSinceEpoch}';

    // ✅ 핵심: amount가 있으면 그걸로 결제 (쿠폰 할인 반영)
    price = widget.amount ?? getPriceForCount(widget.count);

    platform.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink' && !_hasHandled) {
        final uri = Uri.tryParse(call.arguments);
        if (uri == null) return;

        final impUid = uri.queryParameters['imp_uid'];
        final merchantUidFromLink = uri.queryParameters['merchant_uid'];

        _hasHandled = true; // ✅ 중복 방지

        if (impUid != null && merchantUidFromLink != null) {
          debugPrint('📥 [딥링크] Android 복귀 감지 → imp_uid: $impUid');
          Navigator.pop(context, {
            'success': true,
            'imp_uid': impUid,
            'merchant_uid': merchantUidFromLink,
            // ✅ 추가: 서버 검증용 참고값
            'amount': price,
            'couponCode': widget.couponCode,
          });
        } else {
          debugPrint('❌ [딥링크] 결제 정보 누락');
          Navigator.pop(context, {
            'success': false,
            'error_msg': '딥링크로부터 결제 정보 수신 실패',
            'amount': price,
            'couponCode': widget.couponCode,
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IamportPayment(
          userCode: 'imp35203770',
          data: PaymentData(
            pg: 'nice',
            payMethod: 'card',
            name: '알바일주 이용권 ${widget.count}회',
            merchantUid: merchantUid,

            // ✅ 핵심: 결제 금액(할인 적용 가능)
            amount: price,

            buyerName: widget.companyName,
            buyerTel: widget.companyPhone,
            appScheme: 'albailju',
          ),
          callback: (Map<String, String> result) {
            debugPrint('📦 [callback] 결제 결과 수신됨: $result');

            if (_hasHandled) {
              debugPrint('🚫 [callback] 이미 처리된 상태 → 무시');
              return;
            }

            final impUid = result['imp_uid'];
            final merchantUidFromCb = result['merchant_uid'];

            final impSuccessStr = result['imp_success'];
            final success = impSuccessStr == 'true';

            _hasHandled = true; // ✅ 중복 방지

            if (success && impUid != null && merchantUidFromCb != null) {
              debugPrint('✅ [callback] 결제 성공 → imp_uid: $impUid');
              Navigator.pop(context, {
                'success': true,
                'imp_uid': impUid,
                'merchant_uid': merchantUidFromCb,
                // ✅ 추가: 서버 검증용 참고값
                'amount': price,
                'couponCode': widget.couponCode,
              });
            } else {
              debugPrint('❌ [callback] 결제 실패 → imp_uid: $impUid / merchant_uid: $merchantUidFromCb');
              Navigator.pop(context, {
                'success': false,
                'error_msg': result['error_msg'] ?? '결제 실패',
                'amount': price,
                'couponCode': widget.couponCode,
              });
            }
          },
        ),
      ),
    );
  }

 int getPriceForCount(int count) {
  switch (count) {
    case 1:
      return 7000;
    case 3:
      return 19800;
    case 5:
      return 30000;
    case 10:
      return 55000;
    default:
      return 0;
  }
}
}
