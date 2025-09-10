import 'package:flutter/material.dart';
import 'package:portone_flutter/iamport_payment.dart';
import 'package:portone_flutter/model/payment_data.dart';
import 'package:flutter/services.dart';

class PortonePaymentScreen extends StatefulWidget {
  final int count;
  final String companyName;
  final String companyPhone;

  const PortonePaymentScreen({
    super.key,
    required this.count,
    required this.companyName,
    required this.companyPhone,
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
  price = getPriceForCount(widget.count);

  platform.setMethodCallHandler((call) async {
    if (call.method == 'onDeepLink' && !_hasHandled) {
      final uri = Uri.tryParse(call.arguments);
      if (uri == null) return;

      final impUid = uri.queryParameters['imp_uid'];
      final merchantUid = uri.queryParameters['merchant_uid'];

      if (impUid != null && merchantUid != null) {
        _hasHandled = true;
        debugPrint('📥 [딥링크] Android 복귀 감지 → imp_uid: $impUid');
        Navigator.pop(context, {
          'success': true,
          'imp_uid': impUid,
          'merchant_uid': merchantUid,
        });
      } else {
        _hasHandled = true;
        debugPrint('❌ [딥링크] imp_uid 없음');
        Navigator.pop(context, {
          'success': false,
          'error_msg': '딥링크로부터 결제 정보 수신 실패',
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
            amount: price,
            buyerName: widget.companyName,
            buyerTel: widget.companyPhone,
            appScheme: 'albailju',
          ),
    callback: (Map<String, String> result) {
  print('📦 [callback] 결제 결과 수신됨: $result');

  if (_hasHandled) {
    print('🚫 [callback] 이미 처리된 상태 → 무시');
    return;
  }

  final impUid = result['imp_uid'];
  final merchantUid = result['merchant_uid'];
  final success = result['imp_success'] == 'true' || result['imp_success'] == true;

  _hasHandled = true; // ✅ 중복 방지

  if (success && impUid != null && merchantUid != null) {
    print('✅ [callback] 결제 성공 → imp_uid: $impUid');
    Navigator.pop(context, {
      'success': true,
      'imp_uid': impUid,
      'merchant_uid': merchantUid,
    });
  } else {
    print('❌ [callback] 결제 실패 → success: $success / imp_uid: $impUid / merchant_uid: $merchantUid');
    Navigator.pop(context, {
      'success': false,
      'error_msg': result['error_msg'] ?? '결제 실패',
    });
  }
}
        ),
      ),
    );
  }

  int getPriceForCount(int count) {
  switch (count) {
    case 1:
      return 8800;
    case 10:
      return 77000; // 약 12.5% 할인
    case 20:
      return 148000; // 약 15% 할인
    case 30:
      return 184000; // 약 30% 할인
    default:
      return 0;
  }
}
}
