// File: lib/presentation/screens/purchase_pass_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';
import 'pass_payment_webview.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart'; // ← 반드시 있어야 함
import 'package:iljujob/presentation/screens/potrone_screen.dart'; // ← 포트원 결제 화면 임포트
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:async';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

class PurchasePassScreen extends StatefulWidget {
  const PurchasePassScreen({super.key});

  @override
  State<PurchasePassScreen> createState() => _PurchasePassScreenState();
}

class _PurchasePassScreenState extends State<PurchasePassScreen> {
  int? _selectedCount;
  int remainingCount = 0;
  String managerName = '';
  String companyName = '';
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  final formatter = NumberFormat('#,###');

  String formatPrice(int number) {
    return '${formatter.format(number)}원';
  }
  // 파일 상단/State 안에 추가
Completer<PurchaseDetails>? _purchaseCompleter;
final Map<int, String> _iosProductIds = {
  1:  'com.iljujob.pass1',
  10: 'com.iljujob.pass10',
  20: 'com.iljujob.pass20',
  30: 'com.iljujob.pass30',
};
  
  
final List<Map<String, dynamic>> _passOptions = [
  {
    'count': 1,
    'price': 8800,
    'label': '알바일주 1회 이용권',
  },
  {
    'count': 10,
    'price': 77000,
    'label': '알바일주 10회 이용권  · 약 12% 할인',
  },
  {
    'count': 20,
    'price': 148000,
    'label': '🔥 추천! 20회 이용권  · 약 16% 할인', // ✅ "회당 최저가" 제거
  },
  {
    'count': 30,
    'price': 184000,
    'label': '🎁 30회 이용권  · 약 30% 할인',
  },
];

Future<String?> _getAppReceiptBase64() async {
  try {
    final receipt = await SKReceiptManager.retrieveReceiptData();
    // refreshReceipt가 없으니 여기서 끝. receipt가 없으면 서버 검증을 스킵/에러로 처리
    if (receipt == null || receipt.isEmpty) return null;
    return receipt;
  } catch (e) {
    print('❌ getAppReceipt error: $e');
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
    } catch (e) {
      print('❌ [IAP] finish error: $e');
    }
  }
}
DateTime? _buyStartedAt;
String? _attemptingProductId;

bool _isWithinCurrentSession(PurchaseDetails p) {
  if (_buyStartedAt == null) return false;
  final ts = p.transactionDate;
  if (ts == null) return false;
  try {
    final n = num.parse(ts);
    final eventTime = DateTime.fromMillisecondsSinceEpoch(n > 1e12 ? n.toInt() : n.toInt() * 1000);
    return eventTime.isAfter(_buyStartedAt!.subtract(const Duration(minutes: 2)));
  } catch (_) {
    return false;
  }
}

// ✅ 이번 결제에서 기대하는 productId (세션 추적용)
String? _expectedProductId;

final Set<String> _handledPurchaseIds = {};
bool _isPurchasing = false;

bool _isFreshForCurrentAttempt(PurchaseDetails p) {
  if (_expectedProductId == null || _buyStartedAt == null) return false;
  if (p.productID != _expectedProductId) return false;

  final ts = p.transactionDate;
  if (ts == null) return false;

  final n = num.tryParse(ts);
  if (n == null) return false;

  final eventTime = DateTime.fromMillisecondsSinceEpoch(n > 1e12 ? n.toInt() : n.toInt() * 1000);

  final ok = eventTime.isAfter(_buyStartedAt!.subtract(const Duration(minutes: 2)));


  return ok;
}
@override
void initState() {
  super.initState();
  _refreshPassCount();
  _loadUserInfo();

  // ✅ 앱 시작 시 1회 큐 비우기
  _forceFinishAllIosTransactions();

  final iap = InAppPurchase.instance;
  _purchaseSub = iap.purchaseStream.listen(_onPurchaseUpdated, onDone: () {
    _purchaseSub?.cancel();
  }, onError: (e) {
    if (!mounted) return;
    _showErrorDialog('결제 스트림 오류: $e');
  });
}
@override
void dispose() {
  _purchaseSub?.cancel();
  super.dispose();
}

/// 구매 시작
/// 구매 시작
Future<void> _buyWithIAP(int count) async {
  if (!mounted) return;
  _buyStartedAt = DateTime.now();

  // 이미 결제 중이면 막기
  if (_isPurchasing || (_purchaseCompleter != null && !_purchaseCompleter!.isCompleted)) {
    return;
  }

  final iap = InAppPurchase.instance;
  final productId = _iosProductIds[count];
  if (productId == null) {
    _showErrorDialog('상품 ID가 없습니다.');
    return;
  }

  setState(() => _isPurchasing = true);
  _handledPurchaseIds.clear();
  _expectedProductId = productId;                 // 이번 결제 대상
  _purchaseCompleter = Completer<PurchaseDetails>();

  try {

    final available = await iap.isAvailable();
    if (!available) throw Exception('IAP Unavailable');

    final resp = await iap.queryProductDetails({productId});
    if (resp.productDetails.isEmpty) throw Exception('상품 정보를 찾을 수 없습니다: $productId');

    final ok = await iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: resp.productDetails.first),
      autoConsume: true, // iOS엔 영향 없지만 명시
    );
    if (!ok) throw Exception('결제 요청 시작 실패');

    final details = await _purchaseCompleter!.future.timeout(
      const Duration(minutes: 5),
    );
    if (mounted) await _refreshPassCount();
  } catch (e) {
    if (mounted) _showErrorDialog('결제 처리 중 오류: $e');
    print('❌ 결제 처리 오류: $e');
  } finally {
    _expectedProductId = null;
    _purchaseCompleter = null;
    if (mounted) setState(() => _isPurchasing = false);
  }
}

/// 스트림 이벤트 처리
bool get _purchaseCompleterIsDone =>
    _purchaseCompleter == null || _purchaseCompleter!.isCompleted;

/// 스트림 이벤트 처리
Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
  final iap = InAppPurchase.instance;

  for (final p in purchases) {


    // 진행중
    if (p.status == PurchaseStatus.pending) {
      if (mounted && !_isPurchasing) setState(() => _isPurchasing = true);
      continue;
    }

    // 신규 결제 완료
    if (p.status == PurchaseStatus.purchased) {
      try {
        if (Platform.isIOS) {
        final appReceipt = await _getAppReceiptBase64();
if (appReceipt == null) {
  throw Exception('앱 영수증이 없습니다(21002 가능)');
}
await _verifyIosReceiptOnServer(
  productId: p.productID,
transactionId: p.purchaseID ?? '', // ← 이렇게 직접 넘겨
  appReceiptBase64: appReceipt, // ← 앱 영수증 전달
);
        }

        if (p.pendingCompletePurchase) {
          await iap.completePurchase(p);
        }

        // 멱등 보조(굳이 안 써도 되지만 남겨둠)
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

    // 과거 거래 복구 알림(신규 결제 아님)
if (p.status == PurchaseStatus.restored) {
  // 👉 지금 시도 중인 결제와 같은 상품인가?
  final isCurrentAttempt =
      _expectedProductId != null && p.productID == _expectedProductId;

  final pid = p.purchaseID;

  if (isCurrentAttempt && pid != null && !_handledPurchaseIds.contains(pid)) {
    // 🟢 SK2에서 가끔 신규가 restored로 오는 케이스 → 구매로 승격 처리

    try {
      if (Platform.isIOS) {
       final appReceipt = await _getAppReceiptBase64();
if (appReceipt == null) {
  throw Exception('앱 영수증이 없습니다(21002 가능)');
}
await _verifyIosReceiptOnServer(
  productId: p.productID,
  transactionId: p.purchaseID ?? '',
  appReceiptBase64: appReceipt, // ← 앱 영수증 전달
);
      }
      if (p.pendingCompletePurchase) {
        try { await iap.completePurchase(p); } catch (_) {}
      }

      _handledPurchaseIds.add(pid);

      // 🔔 대기 중인 구매 플로우 끝내기
      _purchaseCompleter?.complete(p);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 결제가 완료되었습니다! 이용권이 지급되었습니다.')),
        );
        await _refreshPassCount();
      }
    } catch (e) {
      print('❌ restored-as-purchased 검증 실패: $e');
      _purchaseCompleter?.completeError(e);
      if (mounted) _showErrorDialog('서버 검증 실패: $e');
    } finally {
      if (mounted && _isPurchasing) setState(() => _isPurchasing = false);
      // ⚠️ 한 번 처리 끝났으면 더 이상 현재 시도로 오인하지 않도록 비워줌
      _expectedProductId = null;
    }
  } else {
    // 과거 복구 노이즈 → 무시 (필요 시 완료만)

    if (p.pendingCompletePurchase) {
      try { await iap.completePurchase(p); } catch (_) {}
    }
  }
  continue;
}
  }
}

/// 서버 검증 (그대로 사용)
Future<void> _verifyIosReceiptOnServer({
  required String productId,
  required String transactionId,
  required String appReceiptBase64,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final clientId = prefs.getInt('userId') ?? 0;

  // ⬇️ 여기서 보정: null/빈값이면 ''로 고정
  final txForServer = (transactionId.isEmpty) ? '' : transactionId;

  final res = await http.post(
    Uri.parse('$baseUrl/api/pass/verify-ios'),
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    body: jsonEncode({
      'clientId': clientId,
      'productId': productId,
      'transactionId': txForServer,
      'appReceiptBase64': appReceiptBase64,
    }),
  );
  if (res.statusCode != 200) {
    final msg = () { try { return jsonDecode(res.body)['message'] ?? '검증 실패'; } catch (_) { return '검증 실패'; } }();
    throw Exception(msg);
  }
}


Future<void> _refreshPassCount() async {
  final prefs = await SharedPreferences.getInstance();
  final clientId = prefs.getInt('userId') ?? 0;

  final res = await http.get(Uri.parse('$baseUrl/api/pass/remain?clientId=$clientId'));


  if (res.statusCode == 200) {
    final data = jsonDecode(res.body);
    setState(() {
      remainingCount = int.tryParse(data['remaining'].toString()) ?? 0;
    });

  } else {
    print('❌ 이용권 수 조회 실패: ${res.statusCode}');
  }
}
  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      managerName = prefs.getString('userName') ?? '';
      companyName = prefs.getString('companyName') ?? '';
    });
  }

  Future<void> _verifyWithServer(String impUid) async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/pass/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'impUid': impUid,
          'clientId': clientId,
          'platform': Platform.isIOS ? 'ios' : 'android', // ✅ 여기에 추가!
        }),
      );

      if (res.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('✅ 이용권이 정상 지급되었습니다')));
        _refreshPassCount();
      } else {
        final msg = jsonDecode(res.body)['message'] ?? '검증 실패';
        _showErrorDialog(msg);
      }
    } catch (e) {
      _showErrorDialog('서버 오류: $e');
    }
  }

void _showErrorDialog(String message) {
  if (!mounted) {
    return;
  }
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
  void _onPurchasePressed() {
  final safeContext = context; // ✅ 안전한 context 백업 (모달 바깥)
  _handledPurchaseIds.clear();
  final selected = _passOptions.firstWhere(
    (opt) => opt['count'] == _selectedCount,
  );
  final count = selected['count'];
  final price = selected['price'];

  showModalBottomSheet(
    context: context,
    useSafeArea: true,           // ✅ 하단 안전영역 반영
    isScrollControlled: true,    // ✅ 키보드 대응
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      // ✅ 키보드/제스처바 중 큰 값으로 하단 패딩 보정
      final kb = MediaQuery.of(context).viewInsets.bottom;
      final pad = MediaQuery.of(context).padding.bottom;
      final bottomPad = (kb > 0 ? kb : pad) + 20;

      return Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, bottomPad),
        child: SingleChildScrollView( // ✅ 작은 화면/큰 폰트 대비
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.shopping_cart_checkout_rounded,
                size: 48,
                color: Color(0xFF3B8AFF),
              ),
              const SizedBox(height: 12),
              const Text(
                '이용권 구매 확인',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🧾 상품명: 알바일주 이용권 ($count회)',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '💳 결제 금액: ${formatPrice(price)}원',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '✅ 이 이용권은 공고 등록 시 1건당 1회 차감되며,\n결제일로부터 1년간 유효합니다.',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: const BorderSide(color: Color(0xFFCED5E0)),
                      ),
                      child: const Text(
                        '취소',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (_selectedCount == null) return;

                        final selected = _passOptions.firstWhere(
                          (o) => o['count'] == _selectedCount,
                        );
                        final count = selected['count'];
                        final price = selected['price'];

                        // 공통 확인 바텀시트는 유지
                        if (Platform.isIOS) {
                          // ✅ iOS: 인앱결제
                          Navigator.pop(context); // 바텀시트 닫기
                          await _buyWithIAP(count);
                          return;
                        } else {
                          // ✅ Android: 포트원
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PortonePaymentScreen(
                                count: count,
                                companyName: companyName,
                                companyPhone: managerName,
                              ),
                            ),
                          );

                          if (result is Map<String, dynamic>) {
                            if (result['success'] == true && result['imp_uid'] != null) {
                              Navigator.pop(context);
                              await _verifyWithServer(result['imp_uid']);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('❌ 결제 실패: ${result['error_msg'] ?? '알 수 없음'}')),
                              );
                            }
                          } else if (result is String) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('🎉 결제가 완료되었습니다!')),
                            );
                            _refreshPassCount();
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B8AFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
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
}

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
        // ── 상단 프로필 카드 ─────────────────────────────────────
        const SizedBox(height: 16),
      Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20), // 조금 더 둥글게
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05), // 그림자 조금 진하게
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16), // 패딩 확장
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 이름/회사
        Row(
          children: [
            Container(
              width: 50, height: 50, // 아이콘 더 크게
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
                  Text(
                    '👤 담당자명: $managerName',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '🏢 회사명: $companyName',
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16), // 여백 늘림
        // 보유 이용권 + 안내
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // 조금 더 큼
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
    // ✅ 잘림 제거
    // maxLines: 2,
    // overflow: TextOverflow.ellipsis,
  ),
),

          ],
        ),
      ],
    ),
  ),
),

        const SizedBox(height: 16),
        // ── 상품 리스트 ──────────────────────────────────────────
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
              final isBest = count == 20; // 20회 강조

              // 테두리/그림자/배경
              final borderColor = isSelected
                  ? themeBlue
                  : (isBest ? Colors.green.shade300 : Colors.grey.shade300);

              final shadows = isSelected
                  ? [BoxShadow(color: themeBlue.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4))]
                  : (isBest ? [BoxShadow(color: Colors.green.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3))] : []);

              final gradient = isSelected
                  ? const LinearGradient(
                      colors: [Color(0xFFF7FAFF), Colors.white],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter)
                  : null;

              return GestureDetector(
                onTap: () => setState(() => _selectedCount = count),
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                      decoration: BoxDecoration(
                        color: gradient == null ? Colors.white : null,
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
                        boxShadow: [
    if (isSelected)
      BoxShadow(
        color: const Color(0xFF3B8AFF).withOpacity(0.12),
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
                          // 라벨 + 추천 뱃지
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
                                      color: Colors.green, fontSize: 11, fontWeight: FontWeight.w700),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 가격 칩
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF2F6FF),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('총 ${formatPrice(price)}',
                                    style: const TextStyle(fontSize: 14, color: Color(0xFF1E40AF))),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F7F9),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('회당 ${formatPrice(unitPrice)}',
                                    style: const TextStyle(fontSize: 13, color: Colors.black87)),
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

                    // 상단 리본 (20회)
            
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),

    // ── 하단 CTA ───────────────────────────────────────────────
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ElevatedButton(
        onPressed: _selectedCount == null ? null : _onPurchasePressed,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: themeBlue,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          shadowColor: themeBlue.withOpacity(0.3),
        ),
child: Text(
  _selectedCount == null
      ? '이용권 구매하기'
      : '$_selectedCount회 이용권 구매하기',
  style: const TextStyle(
    color: Colors.white, // ✅ 글씨 색 흰색
    fontWeight: FontWeight.bold, // 선택사항
    fontSize: 16, // 선택사항
  ),
),      ),
    ),
  );
}
}