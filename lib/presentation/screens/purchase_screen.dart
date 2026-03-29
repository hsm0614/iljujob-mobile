// File: lib/presentation/screens/purchase_pass_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import '../../config/constants.dart';
import 'package:iljujob/presentation/screens/potrone_screen.dart';

class PurchasePassScreen extends StatefulWidget {
  const PurchasePassScreen({super.key});

  @override
  State<PurchasePassScreen> createState() => _PurchasePassScreenState();
}

class _PurchasePassScreenState extends State<PurchasePassScreen> {
  // ===== UI state =====
  int? _selectedCount;
  int remainingCount = 0;
  String managerName = '';
  String companyName = '';
  final formatter = NumberFormat('#,###');

  String formatPrice(int number) => '${formatter.format(number)}원';

  // ===== Coupon state =====
  final TextEditingController _couponCtrl = TextEditingController();
  bool _couponLoading = false;
  String? _couponMessage;

  String? _appliedCoupon; // 적용된 쿠폰 코드
  int _discountPercent = 0; // Android 할인율 (ex: 50)
  bool _couponValid = false;
  String? _couponCampaign; // ex) "barogo50"
 bool get _isBarogo50 {
  final c = (_couponCampaign ?? '').toLowerCase().trim();
  if (c == 'barogo50') return true;

  final code = (_appliedCoupon ?? '').toLowerCase().trim();
  return code == 'barogo50';
}
  // ===== IAP state =====
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  Completer<PurchaseDetails>? _purchaseCompleter;
  bool _isPurchasing = false;
  DateTime? _buyStartedAt;
  String? _expectedProductId;
  final Set<String> _handledPurchaseIds = {};

  // ✅ iOS 정가 SKU
  final Map<int, String> _iosProductIds = {
    1: 'com.iljujob.pass1',
    10: 'com.iljujob.pass10',
    20: 'com.iljujob.pass20',
    30: 'com.iljujob.pass30',
  };

  // ✅ iOS 바로고 50% 할인 SKU
  final Map<int, String> _iosDiscountProductIdsBarogo50 = {
    1: 'com.iljujob.pass1_barogo50',
    10: 'com.iljujob.pass10_barogo50',
    20: 'com.iljujob.pass20_barogo50',
    30: 'com.iljujob.pass30_barogo50',
  };

  // ===== Options (표시용 가격: Android PG 기준 / iOS는 실제 금액은 StoreKit이 결정) =====
  final List<Map<String, dynamic>> _passOptions = const [
    {'count': 1, 'price': 8800, 'label': '알바일주 1회 이용권'},
    {'count': 10, 'price': 77000, 'label': '알바일주 10회 이용권  · 약 12% 할인'},
    {'count': 20, 'price': 148000, 'label': '🔥 추천! 20회 이용권  · 약 16% 할인'},
    {'count': 30, 'price': 184000, 'label': '🎁 30회 이용권  · 약 30% 할인'},
  ];

  // =========================
  // Lifecycle
  // =========================
  @override
  void initState() {
    super.initState();
    _refreshPassCount();
    _loadUserInfo();

    // iOS: 앱 시작 시 queue 정리(너가 이미 쓰던 전략 유지)
    _forceFinishAllIosTransactions();

    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onDone: () => _purchaseSub?.cancel(),
      onError: (e) {
        if (!mounted) return;
        _showErrorDialog('결제 스트림 오류: $e');
      },
    );
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _couponCtrl.dispose();
    super.dispose();
  }

  // =========================
  // Helpers
  // =========================
  int _calcDiscountedPrice(int price) {
    if (_discountPercent <= 0) return price;
    final discounted = (price * (100 - _discountPercent) / 100).floor();
    return discounted < 0 ? 0 : discounted;
  }

  bool get _purchaseCompleterIsDone =>
      _purchaseCompleter == null || _purchaseCompleter!.isCompleted;

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('오류'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  // =========================
  // Load / Refresh
  // =========================
  Future<void> _refreshPassCount() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;

    final res = await http.get(Uri.parse('$baseUrl/api/pass/remain?clientId=$clientId'));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (!mounted) return;
      setState(() {
        remainingCount = int.tryParse(data['remaining'].toString()) ?? 0;
      });
    } else {
      // ignore
    }
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      managerName = prefs.getString('userName') ?? '';
      companyName = prefs.getString('companyName') ?? '';
    });
  }

  // =========================
  // Coupon (Server validation)
  // =========================
  Future<void> _applyCouponOnServer({
    required int count,
    required int price,
  }) async {
    final code = _couponCtrl.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _couponLoading = true;
      _couponMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getInt('userId') ?? 0;

      final res = await http.post(
        Uri.parse('$baseUrl/api/pass/coupon/validate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'clientId': clientId,
          'count': count,
          'price': price, // 정가 기준(서버가 판단)
          'platform': Platform.isIOS ? 'ios' : 'android',
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        // 기대 응답 예시:
        // {
        //   success:true,
        //   valid:true,
        //   discountPercent:50,
        //   campaign:"barogo50",
        //   message:"적용 완료"
        // }
        final valid = data['valid'] == true;
        final campaign = (data['campaign'] ?? '').toString();
        final discountPercent = int.tryParse('${data['discountPercent'] ?? 0}') ?? 0;
        final message = data['message']?.toString();

        if (!mounted) return;
        if (!valid) {
          setState(() {
            _appliedCoupon = null;
            _discountPercent = 0;
            _couponValid = false;
            _couponCampaign = null;
            _couponMessage = message ?? '쿠폰이 유효하지 않습니다.';
          });
        } else {
          setState(() {
            _appliedCoupon = code;
            _discountPercent = discountPercent;
            _couponValid = true;
            _couponCampaign = campaign.trim().isEmpty ? null : campaign.toLowerCase().trim();
            _couponMessage = message ?? '쿠폰이 적용되었습니다.';
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _appliedCoupon = null;
          _discountPercent = 0;
          _couponValid = false;
          _couponCampaign = null;
          _couponMessage = '쿠폰 검증 실패 (${res.statusCode})';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _appliedCoupon = null;
        _discountPercent = 0;
        _couponValid = false;
        _couponCampaign = null;
        _couponMessage = '쿠폰 검증 오류: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() => _couponLoading = false);
    }
  }

  // =========================
  // iOS SKU resolve
  // =========================
  String? _resolveIosProductId(int count) {
    // 쿠폰이 유효 + 바로고 캠페인이면 할인 SKU
    if (_couponValid && _isBarogo50) {
      return _iosDiscountProductIdsBarogo50[count];
    }
    return _iosProductIds[count];
  }

  // =========================
  // iOS receipt helpers
  // =========================
  Future<String?> _getAppReceiptBase64() async {
    try {
      final receipt = await SKReceiptManager.retrieveReceiptData();
      if (receipt == null || receipt.isEmpty) return null;
      return receipt;
    } catch (e) {
      return null;
    }
  }

  Future<void> _forceFinishAllIosTransactions() async {
    if (!Platform.isIOS) return;
    final queue = SKPaymentQueueWrapper();
    final txs = await queue.transactions();
    for (final t in txs) {
      try {
        await queue.finishTransaction(t);
      } catch (_) {}
    }
  }

  // =========================
  // iOS verify API
  // =========================
  Future<void> _verifyIosReceiptOnServer({
    required String productId,
    required String transactionId,
    required String appReceiptBase64,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;

    final res = await http.post(
      Uri.parse('$baseUrl/api/pass/verify-ios'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({
        'clientId': clientId,
        'productId': productId,
        'transactionId': transactionId.isEmpty ? '' : transactionId,
        'appReceiptBase64': appReceiptBase64,
        // 쿠폰을 “영수증 검증과 묶어서” 기록하고 싶으면 서버에 optional로 같이 보내도 됨
        // 'couponCode': _appliedCoupon,
        // 'campaign': _couponCampaign,
      }),
    );

    if (res.statusCode != 200) {
      final msg = () {
        try {
          return jsonDecode(res.body)['message'] ?? '검증 실패';
        } catch (_) {
          return '검증 실패';
        }
      }();
      throw Exception(msg);
    }
  }

  // =========================
  // iOS buy
  // =========================
  Future<void> _buyWithIAP(int count) async {
    if (!mounted) return;

    // 결제 중복 방지
    if (_isPurchasing || (_purchaseCompleter != null && !_purchaseCompleter!.isCompleted)) {
      return;
    }

    _buyStartedAt = DateTime.now();

    final productId = _resolveIosProductId(count);
    if (productId == null) {
      _showErrorDialog('상품 ID가 없습니다.');
      return;
    }

    setState(() => _isPurchasing = true);
    _handledPurchaseIds.clear();
    _expectedProductId = productId;
    _purchaseCompleter = Completer<PurchaseDetails>();

    try {
      final available = await _iap.isAvailable();
      if (!available) throw Exception('IAP Unavailable');

      final resp = await _iap.queryProductDetails({productId});
      if (resp.productDetails.isEmpty) {
        throw Exception('상품 정보를 찾을 수 없습니다: $productId');
      }

      final ok = await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: resp.productDetails.first),
        autoConsume: true,
      );
      if (!ok) throw Exception('결제 요청 시작 실패');

      await _purchaseCompleter!.future.timeout(const Duration(minutes: 5));
      if (mounted) await _refreshPassCount();
    } catch (e) {
      if (mounted) _showErrorDialog('결제 처리 중 오류: $e');
    } finally {
      _expectedProductId = null;
      _purchaseCompleter = null;
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  // =========================
  // IAP purchase stream
  // =========================
  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      // pending
      if (p.status == PurchaseStatus.pending) {
        if (mounted && !_isPurchasing) setState(() => _isPurchasing = true);
        continue;
      }

      // purchased
      if (p.status == PurchaseStatus.purchased) {
        try {
          if (Platform.isIOS) {
            final appReceipt = await _getAppReceiptBase64();
            if (appReceipt == null) {
              throw Exception('앱 영수증이 없습니다.');
            }
            await _verifyIosReceiptOnServer(
              productId: p.productID,
              transactionId: p.purchaseID ?? '',
              appReceiptBase64: appReceipt,
            );
          }

          if (p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }

          _handledPurchaseIds.add(p.purchaseID ?? '${p.productID}-${p.transactionDate ?? ''}');

          if (!_purchaseCompleterIsDone) {
            _purchaseCompleter?.complete(p);
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('🎉 결제가 완료되었습니다! 이용권이 지급되었습니다.')),
            );
          }
        } catch (e) {
          _purchaseCompleter?.completeError(e);
          if (mounted) _showErrorDialog('서버 검증 실패: $e');
        }
        continue;
      }

      // restored (SK2에서 신규가 restored로 오는 케이스 포함)
      if (p.status == PurchaseStatus.restored) {
        final isCurrentAttempt = _expectedProductId != null && p.productID == _expectedProductId;
        final pid = p.purchaseID;

        if (isCurrentAttempt && pid != null && !_handledPurchaseIds.contains(pid)) {
          try {
            if (Platform.isIOS) {
              final appReceipt = await _getAppReceiptBase64();
              if (appReceipt == null) throw Exception('앱 영수증이 없습니다.');
              await _verifyIosReceiptOnServer(
                productId: p.productID,
                transactionId: p.purchaseID ?? '',
                appReceiptBase64: appReceipt,
              );
            }

            if (p.pendingCompletePurchase) {
              try {
                await _iap.completePurchase(p);
              } catch (_) {}
            }

            _handledPurchaseIds.add(pid);
            _purchaseCompleter?.complete(p);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🎉 결제가 완료되었습니다! 이용권이 지급되었습니다.')),
              );
              await _refreshPassCount();
            }
          } catch (e) {
            _purchaseCompleter?.completeError(e);
            if (mounted) _showErrorDialog('서버 검증 실패: $e');
          } finally {
            if (mounted && _isPurchasing) setState(() => _isPurchasing = false);
            _expectedProductId = null;
          }
        } else {
          // 과거 복구 노이즈 → 무시(필요 시 complete만)
          if (p.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(p);
            } catch (_) {}
          }
        }
        continue;
      }

      // error/canceled
      if (p.status == PurchaseStatus.error || p.status == PurchaseStatus.canceled) {
        if (!_purchaseCompleterIsDone) {
          _purchaseCompleter?.completeError('결제가 취소되었거나 실패했습니다.');
        }
        if (mounted) setState(() => _isPurchasing = false);
      }
    }
  }

  // =========================
  // Android verify (PortOne)
  // =========================
 Future<void> _verifyAndroidPaymentOnServer({
  required String impUid,
  required int count,
  String? couponCode,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final clientId = prefs.getInt('userId') ?? 0;

  debugPrint('🛰️ ================= VERIFY START =================');
  debugPrint('🛰️ impUid=$impUid');
  debugPrint('🛰️ count=$count');
  debugPrint('🛰️ couponCode=$couponCode');
  debugPrint('🛰️ clientId=$clientId');
  debugPrint('🛰️ baseUrl=$baseUrl');
  debugPrint('🛰️ endpoint=${'$baseUrl/api/pass/verify'}');

  try {
    final res = await http.post(
      Uri.parse('$baseUrl/api/pass/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'impUid': impUid,
        'clientId': clientId,
        'platform': 'android',
        'count': count,
        'couponCode': couponCode,
      }),
    );

    debugPrint('🛰️ [VERIFY RESPONSE] statusCode=${res.statusCode}');
    debugPrint('🛰️ [VERIFY RESPONSE] body=${res.body}');
    debugPrint('🛰️ ================= VERIFY END =================');

    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(res.body);
    } catch (_) {}

    final ok = data['ok'] == true;

    if (res.statusCode == 200 && ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 이용권이 정상 지급되었습니다')),
      );
      await _refreshPassCount();
    } else {
      final msg = data['message']?.toString() ?? '검증 실패';
      _showErrorDialog(msg);
    }
  } catch (e) {
    debugPrint('❌ VERIFY EXCEPTION: $e');
    debugPrint('🛰️ ================= VERIFY ERROR =================');
    _showErrorDialog('네트워크 오류 또는 서버 연결 실패');
  }
}
  // =========================
  // Purchase bottom sheet
  // =========================
  void _onPurchasePressed() {
  if (_selectedCount == null) return;

  final selected = _passOptions.firstWhere((opt) => opt['count'] == _selectedCount);
  final count = selected['count'] as int;
  final price = selected['price'] as int;

  // 바텀시트 열 때 입력칸에 기존 적용 쿠폰 유지
  _couponCtrl.text = _appliedCoupon ?? '';

  const themeBlue = Color(0xFF3B8AFF);

  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final kb = MediaQuery.of(ctx).viewInsets.bottom;
      final pad = MediaQuery.of(ctx).padding.bottom;
      final bottomPad = (kb > 0 ? kb : pad) + 20;

      final isIOS = Platform.isIOS;

      return StatefulBuilder(
        builder: (ctx, setModalState) {
          // ✅ 항상 최신 할인율로 재계산
          final discountedPrice = isIOS ? price : _calcDiscountedPrice(price);

          // ✅ iOS: 쿠폰 상태에 따라 SKU가 달라짐
          final iosSku = isIOS ? _resolveIosProductId(count) : null;
          final iosSkuLabel = (iosSku == null)
              ? '상품 ID 없음'
              : ((_couponValid && _isBarogo50) ? '할인 상품으로 결제' : '정가 상품으로 결제');

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, bottomPad),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shopping_cart_checkout_rounded, size: 48, color: themeBlue),
                  const SizedBox(height: 12),
                  const Text('이용권 구매 확인',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // --- 상품 요약 ---
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7FB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🧾 상품명: 알바일주 이용권 ($count회)',
                            style: const TextStyle(fontSize: 14)),
                        const SizedBox(height: 10),

                        if (!isIOS && _discountPercent > 0) ...[
                          Text('정가: ${formatPrice(price)}',
                              style: const TextStyle(fontSize: 13, color: Colors.black54)),
                          const SizedBox(height: 4),
                          Text('할인가(${_discountPercent}%): ${formatPrice(discountedPrice)}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                        ] else if (!isIOS) ...[
                          Text('💳 결제 금액: ${formatPrice(price)}',
                              style: const TextStyle(fontSize: 14)),
                        ] else ...[
                          const Text(' App Store 결제',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          const Text('쿠폰 적용 시 할인 SKU로 결제됩니다.',
                              style: TextStyle(fontSize: 12, color: Colors.black54)),
                          const SizedBox(height: 6),
                          Text('현재: $iosSkuLabel',
                              style: const TextStyle(fontSize: 13, color: Colors.black87)),
                        ],

                        const SizedBox(height: 12),
                        const Text(
                          '✅ 이 이용권은 공고 등록 시 1건당 1회 차감되며,\n결제일로부터 1년간 유효합니다.',
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- 쿠폰 입력 영역 ---
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('쿠폰 코드',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _couponCtrl,
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _couponLoading
                                  ? null
                                  : () async {
                                      await _applyCouponOnServer(count: count, price: price);

                                      // ✅ 서버가 campaign을 안 주는 경우 대비(바로고 쿠폰이면 강제 캠페인 세팅)
                                      final typed = _couponCtrl.text.trim().toUpperCase();
                                     if (_couponValid && (_couponCampaign == null || _couponCampaign!.isEmpty)) {
  if (typed == 'BAROGO50') {
    setState(() => _couponCampaign = 'barogo50');
  }
}
setModalState(() {}); // 유지

                                      // ✅ 바텀시트 즉시 리빌드(가격/SKU 반영)
                                      setModalState(() {});
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: themeBlue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              child: _couponLoading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('적용'),
                            ),
                          ],
                        ),
                        if (_couponMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _couponMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: (_couponValid) ? const Color(0xFF0F766E) : Colors.redAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            side: const BorderSide(color: Color(0xFFCED5E0)),
                          ),
                          child: const Text('취소',
                              style: TextStyle(color: Colors.black87)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                         onPressed: (_isPurchasing)
    ? null
    : () async {
        final finalIsIOS = Platform.isIOS;
        final finalPrice = finalIsIOS ? price : _calcDiscountedPrice(price);
        final couponCode = _couponValid ? _appliedCoupon : null;

        debugPrint(
          '🧾 [BUY] count=$count price=$price discount=$_discountPercent '
          'finalPrice=$finalPrice coupon=$couponCode valid=$_couponValid campaign=$_couponCampaign',
        );

        // ✅ iOS는 여기서 _isPurchasing 잠그지 말 것!
        if (finalIsIOS) {
          Navigator.pop(ctx);
          await _buyWithIAP(count); // 내부에서 _isPurchasing 처리
          return;
        }

        // ✅ Android만 여기서 잠금
        if (mounted) setState(() => _isPurchasing = true);

        try {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PortonePaymentScreen(
                count: count,
                companyName: companyName,
                companyPhone: managerName,
                amount: finalPrice,
                couponCode: couponCode,
              ),
            ),
          );

          if (!mounted) return;

          if (result is Map<String, dynamic>) {
            if (result['success'] == true && result['imp_uid'] != null) {
              Navigator.pop(ctx);
              await _verifyAndroidPaymentOnServer(
                impUid: result['imp_uid'],
                count: count,
                couponCode: couponCode,
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('❌ 결제 실패: ${result['error_msg'] ?? '알 수 없음'}')),
              );
            }
          } else if (result is String) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('🎉 결제가 완료되었습니다!')),
            );
            await _refreshPassCount();
          }
        } finally {
          if (mounted) setState(() => _isPurchasing = false);
        }
      },

                          style: ElevatedButton.styleFrom(
                            backgroundColor: themeBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('구매하기'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final themeBlue = const Color(0xFF3B8AFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('이용권 구매'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),

          // 상단 프로필 카드
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF2F6FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.receipt_long, color: Color(0xFF1E40AF), size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('👤 담당자명: $managerName',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('🏢 회사명: $companyName',
                                style: const TextStyle(fontSize: 14, color: Colors.black87)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F7EF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '🎫 보유 이용권: $remainingCount개',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF0F766E),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '이용권은 공고 등록 시 1건당 1회 차감돼요. 여러 회차를 한 번에 구매하시면 더 저렴해요!',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 상품 리스트
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _passOptions.length,
              itemBuilder: (context, index) {
                final option = _passOptions[index];
                final count = option['count'] as int;
                final price = option['price'] as int;
                final label = option['label'] as String;

                final unitPrice = (price / count).floor();
                final isSelected = _selectedCount == count;
                final isBest = count == 20;

                final borderColor = isSelected
                    ? themeBlue
                    : (isBest ? Colors.green.shade300 : Colors.grey.shade300);

                return GestureDetector(
                  onTap: () => setState(() => _selectedCount = count),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
                      boxShadow: [
                        if (isSelected)
                          BoxShadow(
                            color: themeBlue.withOpacity(0.12),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        if (!isSelected && isBest)
                          BoxShadow(
                            color: Colors.green.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected
                                      ? themeBlue
                                      : (isBest ? Colors.green.shade700 : Colors.black87),
                                ),
                              ),
                            ),
                            if (isBest)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.12),
                                  border: Border.all(color: Colors.green.shade300),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  '가장 많이 선택',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F6FF),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '총 ${formatPrice(price)}',
                                style: const TextStyle(fontSize: 14, color: Color(0xFF1E40AF)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF6F7F9),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '회당 ${formatPrice(unitPrice)}',
                                style: const TextStyle(fontSize: 13, color: Colors.black87),
                              ),
                            ),
                            const Spacer(),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? themeBlue : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                isSelected ? '선택됨' : '$count회',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected ? Colors.white : Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // 하단 CTA
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ElevatedButton(
          onPressed: (_selectedCount == null || _isPurchasing) ? null : _onPurchasePressed,
          
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: themeBlue,
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            shadowColor: themeBlue.withOpacity(0.3),
          ),
          child: Text(
            _isPurchasing
                ? '결제 진행 중...'
                : (_selectedCount == null ? '이용권 구매하기' : '$_selectedCount회 이용권 구매하기'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
