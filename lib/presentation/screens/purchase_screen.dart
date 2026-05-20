// File: lib/presentation/screens/purchase_pass_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import '../../config/constants.dart';
import 'package:iljujob/presentation/screens/potrone_screen.dart';

// ── 알바일주 디자인 토큰 ──
const _blue      = AppColors.primary;
const _blueDark  = AppColors.primaryDark;
const _blueLight = AppColors.primaryLight;
const _green     = Color(0xFF00C48C);
const _orange    = Color(0xFFFF6B35);
const _bg        = AppColors.bgPage;
const _white     = Colors.white;
const _text      = AppColors.textPrimary;
const _sub       = AppColors.textSecondary;
const _label     = AppColors.textTertiary;
const _border    = AppColors.border;

class PurchasePassScreen extends StatefulWidget {
  final bool fromPostJob;
  const PurchasePassScreen({super.key, this.fromPostJob = false});
  @override
  State<PurchasePassScreen> createState() => _PurchasePassScreenState();
}

class _PurchasePassScreenState extends State<PurchasePassScreen>
    with TickerProviderStateMixin {
  int? _selectedCount;

  int    remainingCount = 0;
  String managerName    = '';
  String companyName    = '';
  final  formatter      = NumberFormat('#,###');

  // 애니메이션
  late final AnimationController  _headerCtrl;
  late final AnimationController  _listCtrl;
  late final Animation<double>    _headerAnim;

  String formatPrice(int n) => '${formatter.format(n)}원';

  // ── IAP ──
  final InAppPurchase                       _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  Completer<PurchaseDetails>?               _purchaseCompleter;
  bool    _isPurchasing    = false;
  String? _expectedProductId;
  final Set<String> _handledPurchaseIds = {};

  // SKU 매핑 (count → iOS product ID)
  final Map<int, String> _iosProductIds = {
    1:  'com.iljujob.pass1',
    3:  'com.iljujob.pass10',
    5:  'com.iljujob.pass20',
    10: 'com.iljujob.pass30',
  };

  // 패스 옵션
  final List<Map<String, dynamic>> _passOptions = const [
    {'count': 1,  'price': 7000,  'tag': null,         'tagColor': null,     'desc': '가볍게 한 번 써보기'},
    {'count': 3,  'price': 19800, 'tag': null,         'tagColor': null,     'desc': '단기 시즌에 딱 맞는 구성'},
    {'count': 5,  'price': 30000, 'tag': '가장 많이 선택', 'tagColor': 'green',  'desc': '한 달 여유 있게 운영하기'},
    {'count': 10, 'price': 55000, 'tag': '최대 21% 할인', 'tagColor': 'orange', 'desc': '단골 사장님을 위한 실속 구성'},
  ];

  // ─────────────────────────────────────────────
  // 생명주기
  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _headerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _listCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _headerAnim = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutCubic);

    _headerCtrl.forward();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _listCtrl.forward();
    });

    _refreshPassCount();
    _loadUserInfo();
    _forceFinishAllIosTransactions();

    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onDone: () => _purchaseSub?.cancel(),
      onError: (e) { if (mounted) _showErrorDialog('결제 오류: $e'); },
    );
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _listCtrl.dispose();
    _purchaseSub?.cancel();
    super.dispose();
  }

  bool get _purchaseCompleterIsDone =>
      _purchaseCompleter == null || _purchaseCompleter!.isCompleted;

  // ─────────────────────────────────────────────
  // 헬퍼
  // ─────────────────────────────────────────────
  void _showErrorDialog(String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('오류', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인', style: TextStyle(color: _blue, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshPassCount() async {
    final prefs    = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;
    final res = await http.get(Uri.parse('$baseUrl/api/pass/remain?clientId=$clientId'));
    if (res.statusCode == 200 && mounted) {
      final data = jsonDecode(res.body);
      setState(() => remainingCount = int.tryParse(data['remaining'].toString()) ?? 0);
    }
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      managerName = prefs.getString('userName')    ?? '';
      companyName = prefs.getString('companyName') ?? '';
    });
  }

  String? _resolveIosProductId(int count) => _iosProductIds[count];

  Future<void> _forceFinishAllIosTransactions() async {
    if (!Platform.isIOS) return;
    final q = SKPaymentQueueWrapper();
    for (final t in await q.transactions()) {
      try { await q.finishTransaction(t); } catch (_) {}
    }
  }

  // ─────────────────────────────────────────────
  // ✅ JWS 방식 서버 검증 (영수증 방식 제거)
  // ─────────────────────────────────────────────
  Future<void> _verifyIosOnServer({
    required String productId,
    required String transactionId,
    required String jwsTransaction,
  }) async {
    final prefs    = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;

    final res = await http.post(
      Uri.parse('$baseUrl/api/pass/verify-ios'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({
        'clientId':       clientId,
        'productId':      productId,
        'transactionId':  transactionId,
        'jwsTransaction': jwsTransaction,
      }),
    );

    if (res.statusCode != 200) {
      String msg = '검증 실패';
      try { msg = jsonDecode(res.body)['message'] ?? msg; } catch (_) {}
      throw Exception(msg);
    }
  }

  // ─────────────────────────────────────────────
  // 구매 시작
  // ─────────────────────────────────────────────
  Future<void> _buyWithIAP(int count) async {
    if (!mounted) return;
    if (_isPurchasing || (_purchaseCompleter != null && !_purchaseCompleter!.isCompleted)) return;

    final productId = _resolveIosProductId(count);
    if (productId == null) { _showErrorDialog('상품 ID가 없습니다.'); return; }

    setState(() => _isPurchasing = true);
    _handledPurchaseIds.clear();
    _expectedProductId  = productId;
    _purchaseCompleter  = Completer<PurchaseDetails>();

    try {
      final available = await _iap.isAvailable();
      if (!available) throw Exception('IAP Unavailable');

      final resp = await _iap.queryProductDetails({productId});
      if (resp.productDetails.isEmpty) throw Exception('상품을 찾을 수 없습니다: $productId');

      final ok = await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: resp.productDetails.first),
        autoConsume: true,
      );
      if (!ok) throw Exception('결제 요청 실패');

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

  // ─────────────────────────────────────────────
  // 구매 이벤트 처리
  // ─────────────────────────────────────────────
  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {

      // ── pending ──
      if (p.status == PurchaseStatus.pending) {
        if (mounted && !_isPurchasing) setState(() => _isPurchasing = true);
        continue;
      }

      // ── purchased ──
      if (p.status == PurchaseStatus.purchased) {
        final purchaseKey = p.purchaseID ?? '${p.productID}-${p.transactionDate ?? ''}';

        if (_handledPurchaseIds.contains(purchaseKey)) {
          if (p.pendingCompletePurchase) {
            try { await _iap.completePurchase(p); } catch (_) {}
          }
          continue;
        }
        _handledPurchaseIds.add(purchaseKey);

        try {
          if (Platform.isIOS) {
            // ✅ JWS 트랜잭션 사용
            final jws = p.verificationData.serverVerificationData;
            if (jws.isEmpty) throw Exception('JWS 트랜잭션이 없습니다.');
            await _verifyIosOnServer(
              productId:      p.productID,
              transactionId:  p.purchaseID ?? '',
              jwsTransaction: jws,
            );
          }

          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          if (!_purchaseCompleterIsDone) _purchaseCompleter?.complete(p);

          if (mounted) {
            if (widget.fromPostJob) {
              await Future.delayed(const Duration(milliseconds: 600));
              if (mounted) Navigator.pop(context, {'success': true});
            } else {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('🎉 이용권이 지급되었습니다!')));
              await _refreshPassCount();
            }
          }
        } catch (e) {
          _handledPurchaseIds.remove(purchaseKey);
          _purchaseCompleter?.completeError(e);
          if (mounted) _showErrorDialog('서버 검증 실패: $e');
        }
        continue;
      }

      // ── restored ──
      if (p.status == PurchaseStatus.restored) {
        final pid = p.purchaseID;

        if (pid != null && _handledPurchaseIds.contains(pid)) {
          if (p.pendingCompletePurchase) {
            try { await _iap.completePurchase(p); } catch (_) {}
          }
          continue;
        }

        final isCurrentAttempt = _expectedProductId != null && p.productID == _expectedProductId;

        if (isCurrentAttempt && pid != null) {
          try {
            if (Platform.isIOS) {
              // ✅ restored도 JWS 방식
              final jws = p.verificationData.serverVerificationData;
              if (jws.isEmpty) throw Exception('JWS 트랜잭션이 없습니다.');
              await _verifyIosOnServer(
                productId:      p.productID,
                transactionId:  p.purchaseID ?? '',
                jwsTransaction: jws,
              );
            }

            if (p.pendingCompletePurchase) {
              try { await _iap.completePurchase(p); } catch (_) {}
            }
            _handledPurchaseIds.add(pid);
            _purchaseCompleter?.complete(p);

            if (mounted && widget.fromPostJob) {
              Navigator.pop(context, {'success': true});
            }
          } catch (e) {
            _purchaseCompleter?.completeError(e);
            if (mounted) _showErrorDialog('서버 검증 실패: $e');
          } finally {
            if (mounted && _isPurchasing) setState(() => _isPurchasing = false);
            _expectedProductId = null;
          }
        } else {
          if (p.pendingCompletePurchase) {
            try { await _iap.completePurchase(p); } catch (_) {}
          }
        }
        continue;
      }

      // ── error / canceled ──
      if (p.status == PurchaseStatus.error || p.status == PurchaseStatus.canceled) {
        if (!_purchaseCompleterIsDone) _purchaseCompleter?.completeError('결제가 취소되었거나 실패했습니다.');
        if (mounted) setState(() => _isPurchasing = false);
      }
    }
  }

  // ─────────────────────────────────────────────
  // Android 결제 검증
  // ─────────────────────────────────────────────
  Future<void> _verifyAndroidPaymentOnServer({
    required String impUid,
    required int    count,
  }) async {
    final prefs    = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/pass/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'impUid': impUid, 'clientId': clientId, 'platform': 'android', 'count': count}),
      );
      Map<String, dynamic> data = {};
      try { data = jsonDecode(res.body); } catch (_) {}

      if (res.statusCode == 200 && data['ok'] == true) {
        if (!mounted) return;
        await _refreshPassCount();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('✅ 이용권이 정상 지급되었습니다')));
          if (widget.fromPostJob) {
            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) Navigator.pop(context, {'success': true});
          }
        }
      } else {
        final msg = data['message'] ?? '이용권 지급에 실패했습니다.';
        if (mounted) _showErrorDialog('결제는 완료됐으나 지급 오류가 발생했습니다.\n고객센터에 문의해주세요.\n\n($msg)');
      }
    } catch (_) {
      if (mounted) _showErrorDialog('네트워크 오류가 발생했습니다.\n잠시 후 다시 시도해주세요.');
    }
  }

  int _discountPercent(int count, int price) {
    if (count == 1) return 0;
    return (((7000 * count - price) / (7000 * count)) * 100).round();
  }

  // ─────────────────────────────────────────────
  // 구매 확인 바텀시트
  // ─────────────────────────────────────────────
  void _onPurchasePressed() {
    if (_selectedCount == null) return;
    final selected = _passOptions.firstWhere((o) => o['count'] == _selectedCount);
    final count    = selected['count'] as int;
    final price    = selected['price'] as int;
    final discount = _discountPercent(count, price);

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomPad = MediaQuery.of(ctx).viewInsets.bottom +
            MediaQuery.of(ctx).padding.bottom + 20;
        return Container(
          decoration: const BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(24, 8, 24, bottomPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 핸들바
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 24),
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(99)),
                ),
              ),

              // 상품 헤더
              Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_blue, _blueDark],
                          begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(child: Text('🎫', style: TextStyle(fontSize: 26))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('알바일주 이용권 ${count}회',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _text)),
                        const SizedBox(height: 3),
                        Text('회당 ${formatPrice((price / count).floor())}',
                            style: const TextStyle(fontSize: 13, color: _label)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatPrice(price),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _blue)),
                      if (discount > 0)
                        Text('$discount% 할인',
                            style: TextStyle(fontSize: 12, color: Colors.red.shade500, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 혜택
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _BenefitRow(icon: Icons.shield_outlined,       iconColor: _blue,   text: '지원자 없으면 이용권 자동 환급'),
                    const SizedBox(height: 10),
                    _BenefitRow(icon: Icons.bolt_rounded,          iconColor: _orange, text: '72시간 상단 노출 + AI 즉시 매칭 푸시'),
                    const SizedBox(height: 10),
                    _BenefitRow(icon: Icons.calendar_today_outlined, iconColor: _green, text: '결제일로부터 1년간 유효'),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 버튼
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: _bg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _border),
                        ),
                        child: const Center(
                          child: Text('취소',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _sub)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _isPurchasing ? null : () async {
                        Navigator.pop(ctx);

                        if (Platform.isIOS) {
                          await _buyWithIAP(count);
                          return;
                        }

                        if (mounted) setState(() => _isPurchasing = true);
                        try {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PortonePaymentScreen(
                                count: count,
                                companyName: companyName,
                                companyPhone: managerName,
                                amount: price,
                              ),
                            ),
                          );
                          if (!mounted) return;
                          if (result is Map<String, dynamic> &&
                              result['success'] == true &&
                              result['imp_uid'] != null) {
                            await _verifyAndroidPaymentOnServer(
                              impUid: result['imp_uid'] as String,
                              count: count,
                            );
                          } else if (result is Map<String, dynamic> && result['success'] == false) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('❌ 결제 실패: ${result['error_msg'] ?? '알 수 없음'}')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isPurchasing = false);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _isPurchasing ? [_border, _border] : [_blue, _blueDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: _isPurchasing ? [] : [
                            BoxShadow(color: _blue.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Center(
                          child: _isPurchasing
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(color: _white, strokeWidth: 2),
                                )
                              : Text('${formatPrice(price)} 결제하기',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _white)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('이용권 구매',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _text)),
        centerTitle: true,
        backgroundColor: _bg,
        foregroundColor: _text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          // ── 헤더 — 보유 이용권 ──
          FadeTransition(
            opacity: _headerAnim,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, -0.2), end: Offset.zero).animate(_headerAnim),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_blue, Color(0xFF1E5FC5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: _blue.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('보유 이용권',
                          style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('$remainingCount',
                              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: _white, height: 1)),
                          const SizedBox(width: 4),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text('개', style: TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── 상품 리스트 ──
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              itemCount: _passOptions.length,
              itemBuilder: (context, index) {
                final opt         = _passOptions[index];
                final count       = opt['count']    as int;
                final price       = opt['price']    as int;
                final tag         = opt['tag']      as String?;
                final tagColorStr = opt['tagColor'] as String?;
                final desc        = opt['desc']     as String;

                final unitPrice = (price / count).floor();
                final discount  = _discountPercent(count, price);
                final isSelected = _selectedCount == count;
                final isPopular  = tagColorStr == 'green';
                final isOrange   = tagColorStr == 'orange';
                final tagColor   = isPopular ? _green : isOrange ? _orange : _blue;

                return AnimatedBuilder(
                  animation: _listCtrl,
                  builder: (ctx, child) {
                    final delay     = index * 0.12;
                    final animValue = Curves.easeOutCubic.transform(
                      (((_listCtrl.value - delay) / (1 - delay)).clamp(0.0, 1.0)),
                    );
                    return Opacity(
                      opacity: animValue,
                      child: Transform.translate(offset: Offset(0, 24 * (1 - animValue)), child: child),
                    );
                  },
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedCount = count),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? _blueLight : _white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? _blue : isPopular ? _green.withOpacity(0.4) : _border,
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isSelected ? _blue.withOpacity(0.12) : Colors.black.withOpacity(0.04),
                            blurRadius: isSelected ? 16 : 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        width: 40, height: 40,
                                        decoration: BoxDecoration(
                                          color: isSelected ? _blue : _bg,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Center(
                                          child: Text('$count',
                                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                                                  color: isSelected ? _white : _text)),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text('회 이용권',
                                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                                              color: isSelected ? _blue : _text)),
                                    ],
                                  ),
                                ),
                                if (tag != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: tagColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(color: tagColor.withOpacity(0.3)),
                                    ),
                                    child: Text(tag,
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tagColor)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(desc, style: const TextStyle(fontSize: 12, color: _label, height: 1.4)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 6, runSpacing: 6,
                                    children: [
                                      _PriceChip(label: formatPrice(price),
                                          color: isSelected ? _blue : _text,
                                          bgColor: isSelected ? _blue.withOpacity(0.1) : _bg, bold: true),
                                      _PriceChip(label: '회당 ${formatPrice(unitPrice)}',
                                          color: _label, bgColor: _bg, bold: false),
                                      if (discount > 0)
                                        _PriceChip(label: '$discount% 절약',
                                            color: Colors.red.shade600, bgColor: Colors.red.shade50, bold: true),
                                    ],
                                  ),
                                ),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 26, height: 26,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected ? _blue : _white,
                                    border: Border.all(color: isSelected ? _blue : _border, width: 2),
                                    boxShadow: isSelected
                                        ? [BoxShadow(color: _blue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
                                        : [],
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check_rounded, size: 14, color: _white)
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // ── 하단 CTA ──
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _white,
          border: Border(top: BorderSide(color: _border)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _selectedCount != null
                    ? Container(
                        key: ValueKey(_selectedCount),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(color: _blueLight, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            const Icon(Icons.confirmation_number_outlined, size: 16, color: _blue),
                            const SizedBox(width: 8),
                            Text('$_selectedCount회 이용권 선택됨',
                                style: const TextStyle(fontSize: 13, color: _blue, fontWeight: FontWeight.w600)),
                            const Spacer(),
                            Text(
                              formatPrice(_passOptions.firstWhere((o) => o['count'] == _selectedCount)['price'] as int),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _blue),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('empty')),
              ),
              GestureDetector(
                onTap: (_selectedCount == null || _isPurchasing) ? null : _onPurchasePressed,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: (_selectedCount == null || _isPurchasing)
                        ? const LinearGradient(colors: [_border, _border])
                        : const LinearGradient(colors: [_blue, _blueDark],
                            begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: (_selectedCount == null || _isPurchasing)
                        ? []
                        : [BoxShadow(color: _blue.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Center(
                    child: _isPurchasing
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(color: _white, strokeWidth: 2.5),
                          )
                        : Text(
                            _selectedCount == null ? '이용권을 선택해주세요' : '구매하기',
                            style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800,
                              color: _selectedCount == null ? _label : _white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 공통 위젯 ──

class _PriceChip extends StatelessWidget {
  final String label;
  final Color  color;
  final Color  bgColor;
  final bool   bold;
  const _PriceChip({required this.label, required this.color, required this.bgColor, required this.bold});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(99)),
      child: Text(label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   text;
  const _BenefitRow({required this.icon, required this.iconColor, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text,
            style: const TextStyle(fontSize: 13, color: _sub, fontWeight: FontWeight.w500))),
      ],
    );
  }
}