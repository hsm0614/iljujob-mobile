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

// ── 디자인 토큰 ──
const _blue      = AppColors.primary;
const _blueDark  = AppColors.primaryDark;
const _blueLight = AppColors.primaryLight;
const _red       = Color(0xFFEF4444);
const _redLight  = Color(0xFFFFF0F0);
const _green     = Color(0xFF00C48C);
const _orange    = Color(0xFFFF6B35);
const _bg        = AppColors.bgPage;
const _white     = Colors.white;
const _text      = AppColors.textPrimary;
const _sub       = AppColors.textSecondary;
const _label     = AppColors.textTertiary;
const _border    = AppColors.border;

// ── iOS 상품 ID ──
const _kIosInstant = {
  1:  'com.iljujob.pass1',
  3:  'com.iljujob.pass10',
  5:  'com.iljujob.pass20',
  10: 'com.iljujob.pass30',
};
const _kIosUrgent1 = 'com.iljujob.urgent1';

// ── 즉시 게시 패스 옵션 (단건 ₩4,900 기준) ──
const _instantOptions = [
  {'count': 1,  'price': 4900,  'tag': null,         'tagColor': null,     'desc': '가볍게 한 번 써보기'},
  {'count': 3,  'price': 13900, 'tag': null,         'tagColor': null,     'desc': '3회 묶음 · 회당 ₩4,633'},
  {'count': 5,  'price': 22000, 'tag': '가장 많이 선택', 'tagColor': 'green',  'desc': '5회 묶음 · 회당 ₩4,400'},
  {'count': 10, 'price': 39900, 'tag': '최대 19% 할인', 'tagColor': 'orange', 'desc': '10회 묶음 · 회당 ₩3,990'},
];

class PurchasePassScreen extends StatefulWidget {
  final bool fromPostJob;
  const PurchasePassScreen({super.key, this.fromPostJob = false});
  @override
  State<PurchasePassScreen> createState() => _PurchasePassScreenState();
}

class _PurchasePassScreenState extends State<PurchasePassScreen>
    with TickerProviderStateMixin {
  late final TabController _tabCtrl;

  // 잔여
  int remainingInstant = 0;
  int remainingUrgent  = 0;

  // 사용자 정보
  String managerName = '';
  String companyName = '';
  final formatter = NumberFormat('#,###');

  // 즉시 게시 선택
  int? _selectedInstantCount;

  // IAP
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  Completer<PurchaseDetails>? _purchaseCompleter;
  bool    _isPurchasing    = false;
  String? _expectedProductId;
  String? _pendingPassType; // 결제 중인 패스 타입
  final Set<String> _handledPurchaseIds = {};

  String formatPrice(int n) => '${formatter.format(n)}원';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
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
    _tabCtrl.dispose();
    _purchaseSub?.cancel();
    super.dispose();
  }

  bool get _purchaseCompleterIsDone =>
      _purchaseCompleter == null || _purchaseCompleter!.isCompleted;

  // ─── 잔여 조회 ───────────────────────────────────────
  int _nearbyCount = 0;

  Future<void> _refreshPassCount() async {
    final prefs    = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;
    final res = await http.get(Uri.parse('$baseUrl/api/pass/remain?clientId=$clientId'));
    if (res.statusCode == 200 && mounted) {
      final data = jsonDecode(res.body);
      setState(() {
        remainingInstant = int.tryParse('${data['instant'] ?? data['remaining'] ?? 0}') ?? 0;
        remainingUrgent  = int.tryParse('${data['urgent']  ?? 0}') ?? 0;
      });
    }
    _fetchNearbyCount();
  }

  Future<void> _fetchNearbyCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? '';
      final res = await http.get(
        Uri.parse('$baseUrl/api/direct-message/nearby-count'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _nearbyCount = (data['count'] as num?)?.toInt() ?? 0);
      }
    } catch (_) {}
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      managerName = prefs.getString('userName')    ?? '';
      companyName = prefs.getString('companyName') ?? '';
    });
  }

  Future<void> _forceFinishAllIosTransactions() async {
    if (!Platform.isIOS) return;
    final q = SKPaymentQueueWrapper();
    for (final t in await q.transactions()) {
      try { await q.finishTransaction(t); } catch (_) {}
    }
  }

  // ─── 에러 다이얼로그 ──────────────────────────────────
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

  // ─── iOS JWS 서버 검증 ────────────────────────────────
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

  // ─── iOS IAP 구매 ─────────────────────────────────────
  Future<void> _buyWithIAP(String productId, String passType) async {
    if (!mounted) return;
    if (_isPurchasing || (_purchaseCompleter != null && !_purchaseCompleter!.isCompleted)) return;

    setState(() => _isPurchasing = true);
    _handledPurchaseIds.clear();
    _expectedProductId = productId;
    _pendingPassType   = passType;
    _purchaseCompleter = Completer<PurchaseDetails>();

    try {
      final available = await _iap.isAvailable();
      if (!available) throw Exception('IAP 서비스를 사용할 수 없습니다 (isAvailable=false)');

      final resp = await _iap.queryProductDetails({productId});

      // 디버그: 콘솔에서 확인
      print('🛒 IAP query [$productId]');
      print('  found: ${resp.productDetails.map((p) => p.id).toList()}');
      print('  notFound: ${resp.notFoundIDs}');
      print('  error: ${resp.error}');

      if (resp.productDetails.isEmpty) {
        final detail = resp.notFoundIDs.isNotEmpty
            ? 'App Store에 상품 ID가 없음: ${resp.notFoundIDs}'
            : resp.error != null
                ? 'StoreKit 오류: ${resp.error?.message}'
                : '알 수 없는 오류';
        throw Exception('상품 조회 실패\n$detail');
      }

      final isConsumable = passType == 'instant';
      if (isConsumable) {
        await _iap.buyConsumable(
          purchaseParam: PurchaseParam(productDetails: resp.productDetails.first),
          autoConsume: true,
        );
      } else {
        await _iap.buyConsumable(
          purchaseParam: PurchaseParam(productDetails: resp.productDetails.first),
          autoConsume: true,
        );
      }

      await _purchaseCompleter!.future.timeout(const Duration(minutes: 5));
      if (mounted) await _refreshPassCount();
    } catch (e) {
      if (mounted) _showErrorDialog('결제 처리 중 오류: $e');
    } finally {
      _expectedProductId = null;
      _pendingPassType   = null;
      _purchaseCompleter = null;
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  // ─── IAP 이벤트 처리 ─────────────────────────────────
  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.pending) {
        if (mounted && !_isPurchasing) setState(() => _isPurchasing = true);
        continue;
      }

      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
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
            final isUrgent = p.productID == _kIosUrgent1 || _pendingPassType == 'urgent';
            await _refreshPassCount();
            if (widget.fromPostJob) {
              await Future.delayed(const Duration(milliseconds: 600));
              if (mounted) Navigator.pop(context, {'success': true});
            } else if (isUrgent) {
              _showUrgentSuccessAndNudge();
            } else {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('이용권이 지급되었습니다!')));
            }
          }
        } catch (e) {
          _handledPurchaseIds.remove(purchaseKey);
          _purchaseCompleter?.completeError(e);
          if (mounted) _showErrorDialog('서버 검증 실패: $e');
        }
        continue;
      }

      if (p.status == PurchaseStatus.error || p.status == PurchaseStatus.canceled) {
        if (!_purchaseCompleterIsDone) _purchaseCompleter?.completeError('취소됨');
        if (mounted) setState(() => _isPurchasing = false);
      }
    }
  }

  // ─── Android 결제 검증 ────────────────────────────────
  Future<void> _verifyAndroidOnServer({
    required String impUid,
    required int    count,
    required String passType,
  }) async {
    final prefs    = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/pass/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'impUid':    impUid,
          'clientId':  clientId,
          'platform':  'android',
          'count':     count,
          'passType':  passType,
        }),
      );
      Map<String, dynamic> data = {};
      try { data = jsonDecode(res.body); } catch (_) {}

      if (res.statusCode == 200 && data['ok'] == true) {
        if (!mounted) return;
        await _refreshPassCount();
        if (widget.fromPostJob) {
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) Navigator.pop(context, {'success': true});
        } else if (passType == 'urgent') {
          _showUrgentSuccessAndNudge();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('이용권이 지급되었습니다!')));
          }
        }
      } else {
        final msg = data['message'] ?? '이용권 지급에 실패했습니다.';
        if (mounted) _showErrorDialog('결제는 완료됐으나 지급 오류.\n고객센터 문의 바랍니다.\n\n($msg)');
      }
    } catch (_) {
      if (mounted) _showErrorDialog('네트워크 오류. 잠시 후 다시 시도해주세요.');
    }
  }

  // ─── 긴급 결제 후 구독 넛지 ──────────────────────────
  void _showUrgentSuccessAndNudge() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final pad = MediaQuery.of(ctx).padding.bottom;
        return Container(
          decoration: const BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(24, 8, 24, pad + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEB),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(child: Text('⚡', style: TextStyle(fontSize: 30))),
              ),
              const SizedBox(height: 16),
              const Text(
                '긴급 호출 이용권 지급 완료!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _text),
              ),
              const SizedBox(height: 8),
              const Text(
                '공고 등록 후 긴급 호출을 발송해보세요.',
                style: TextStyle(fontSize: 14, color: _sub),
              ),
              const SizedBox(height: 20),
              // 구독 넛지
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _blue.withOpacity(0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _blue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.workspace_premium_rounded, size: 16, color: _white),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '구독으로 더 저렴하게!',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _blue),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '구독 라이트로 전환하면 이번 달 긴급 호출 1회가 포함돼요 (₩9,900/월)',
                            style: TextStyle(fontSize: 12, color: _sub, height: 1.5),
                          ),
                        ],
                      ),
                    ),
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('나중에'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, '/subscribe');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: _white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('구독 보러가기', style: TextStyle(fontWeight: FontWeight.w700)),
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

  // ─── 즉시 게시 구매 확인 시트 ────────────────────────
  void _showInstantConfirmSheet(int count, int price) {
    final discount = count == 1 ? 0 : (((4900 * count - price) / (4900 * count)) * 100).round();
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final pad = MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 20;
        return Container(
          decoration: const BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(24, 8, 24, pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 24),
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(99)),
                ),
              ),
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
                        Text('즉시 게시 이용권 $count회',
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
                            style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(16)),
                child: const Column(
                  children: [
                    _BenefitRow(icon: Icons.bolt_rounded, iconColor: _blue, text: '즉시 노출 + 상단 고정'),
                    SizedBox(height: 10),
                    _BenefitRow(icon: Icons.shield_outlined, iconColor: _green, text: '지원자 없으면 이용권 자동 환급'),
                    SizedBox(height: 10),
                    _BenefitRow(icon: Icons.calendar_today_outlined, iconColor: _orange, text: '결제일로부터 1년간 유효'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _BuyButton(
                label: '${formatPrice(price)} 결제하기',
                isPurchasing: _isPurchasing,
                gradient: const [_blue, _blueDark],
                onTap: () async {
                  Navigator.pop(ctx);
                  if (Platform.isIOS) {
                    final pid = _kIosInstant[count];
                    if (pid != null) await _buyWithIAP(pid, 'instant');
                  } else {
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
                        await _verifyAndroidOnServer(
                          impUid: result['imp_uid'] as String,
                          count: count,
                          passType: 'instant',
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _isPurchasing = false);
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── 긴급 호출 구매 확인 시트 ────────────────────────
  void _showUrgentConfirmSheet() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final pad = MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 20;
        return Container(
          decoration: const BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(24, 8, 24, pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 24),
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEB),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(child: Text('⚡', style: TextStyle(fontSize: 26))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('긴급 호출 이용권 1회',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _text)),
                        const SizedBox(height: 3),
                        const Text('반경 5km 알바생 최대 10명 발송',
                            style: TextStyle(fontSize: 13, color: _label)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.people_alt_rounded, size: 13, color: _green),
                            const SizedBox(width: 4),
                            Text(
                              _nearbyCount > 0
                                  ? '현재 호출 가능한 알바생 $_nearbyCount명'
                                  : '근처 알바생 수 조회 중...',
                              style: const TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Text('₩7,900',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _red)),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _red.withOpacity(0.15)),
                ),
                child: const Column(
                  children: [
                    _BenefitRow(icon: Icons.bolt_rounded,           iconColor: _red,   text: '즉시 노출 + 활동지수 높은 알바생 직접 선택'),
                    SizedBox(height: 10),
                    _BenefitRow(icon: Icons.people_alt_rounded,     iconColor: _red,   text: '반경 3km 내 최대 10명에게 인앱 메시지 발송'),
                    SizedBox(height: 10),
                    _BenefitRow(icon: Icons.shield_outlined,        iconColor: _green, text: '응답자 0명이면 이용권 100% 자동 반환'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 구독 넛지 인라인
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _blueLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 15, color: _blue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '구독 라이트로 전환하면 이번 달 긴급 호출 1회가 포함돼요 (₩9,900/월)',
                        style: TextStyle(fontSize: 11, color: _blue, fontWeight: FontWeight.w600, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _BuyButton(
                label: '₩7,900 결제하기',
                isPurchasing: _isPurchasing,
                gradient: const [Color(0xFFEF4444), Color(0xFFDC2626)],
                onTap: () async {
                  Navigator.pop(ctx);
                  if (Platform.isIOS) {
                    await _buyWithIAP(_kIosUrgent1, 'urgent');
                  } else {
                    if (mounted) setState(() => _isPurchasing = true);
                    try {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PortonePaymentScreen(
                            count: 1,
                            companyName: companyName,
                            companyPhone: managerName,
                            amount: 7900,
                            productName: '알바일주 긴급 호출 이용권',
                          ),
                        ),
                      );
                      if (!mounted) return;
                      if (result is Map<String, dynamic> &&
                          result['success'] == true &&
                          result['imp_uid'] != null) {
                        await _verifyAndroidOnServer(
                          impUid: result['imp_uid'] as String,
                          count: 1,
                          passType: 'urgent',
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _isPurchasing = false);
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Build ────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('이용권 구매'),
        centerTitle: true,
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: _blue,
          unselectedLabelColor: _label,
          indicatorColor: _blue,
          indicatorWeight: 2,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [
            Tab(text: '즉시 게시'),
            Tab(text: '긴급 호출'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _InstantTab(
            remainingCount: remainingInstant,
            options: _instantOptions,
            isPurchasing: _isPurchasing,
            onSelect: _showInstantConfirmSheet,
            formatPrice: formatPrice,
          ),
          _UrgentTab(
            remainingCount: remainingUrgent,
            isPurchasing: _isPurchasing,
            onBuy: _showUrgentConfirmSheet,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// 즉시 게시 탭
// ════════════════════════════════════════════════════════
class _InstantTab extends StatefulWidget {
  final int remainingCount;
  final List<Map<String, dynamic>> options;
  final bool isPurchasing;
  final void Function(int count, int price) onSelect;
  final String Function(int) formatPrice;
  const _InstantTab({
    required this.remainingCount,
    required this.options,
    required this.isPurchasing,
    required this.onSelect,
    required this.formatPrice,
  });
  @override
  State<_InstantTab> createState() => _InstantTabState();
}

class _InstantTabState extends State<_InstantTab> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 잔여 배너
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_blue, Color(0xFF1E5FC5)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: _blue.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Row(
              children: [
                const Text('🎫', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('보유 즉시 게시 이용권',
                        style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('${widget.remainingCount}개',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _white, height: 1)),
                  ],
                ),
              ],
            ),
          ),
        ),
        // 상품 목록
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: widget.options.length,
            itemBuilder: (ctx, i) {
              final opt      = widget.options[i];
              final count    = opt['count'] as int;
              final price    = opt['price'] as int;
              final tag      = opt['tag'] as String?;
              final tagColorStr = opt['tagColor'] as String?;
              final desc     = opt['desc'] as String;
              final isSelected = _selected == count;
              final isPopular  = tagColorStr == 'green';
              final isOrange   = tagColorStr == 'orange';
              final tagColor   = isPopular ? _green : isOrange ? _orange : _blue;
              final discount   = count == 1 ? 0 : (((4900 * count - price) / (4900 * count)) * 100).round();

              return GestureDetector(
                onTap: () => setState(() => _selected = count),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
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
                        blurRadius: isSelected ? 16 : 8, offset: const Offset(0, 4),
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
                                      child: Text('$count', style: TextStyle(
                                        fontSize: 18, fontWeight: FontWeight.w900,
                                        color: isSelected ? _white : _text,
                                      )),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('회 이용권', style: TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w800,
                                    color: isSelected ? _blue : _text,
                                  )),
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
                                child: Text(tag, style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700, color: tagColor,
                                )),
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
                                  _PriceChip(label: widget.formatPrice(price),
                                      color: isSelected ? _blue : _text,
                                      bgColor: isSelected ? _blue.withOpacity(0.1) : _bg, bold: true),
                                  if (discount > 0)
                                    _PriceChip(label: '$discount% 절약',
                                        color: const Color(0xFFEF4444),
                                        bgColor: const Color(0xFFFFF0F0), bold: true),
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
              );
            },
          ),
        ),
        // 하단 CTA
        _BottomCta(
          isSelected: _selected != null,
          isPurchasing: widget.isPurchasing,
          label: _selected != null
              ? '구매하기'
              : '이용권을 선택해주세요',
          onTap: _selected == null
              ? null
              : () {
                  final opt = widget.options.firstWhere((o) => o['count'] == _selected);
                  widget.onSelect(opt['count'] as int, opt['price'] as int);
                },
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════
// 긴급 호출 탭
// ════════════════════════════════════════════════════════
class _UrgentTab extends StatelessWidget {
  final int remainingCount;
  final bool isPurchasing;
  final VoidCallback onBuy;
  const _UrgentTab({
    required this.remainingCount,
    required this.isPurchasing,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 잔여 배너
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))
                    ],
                  ),
                  child: Row(
                    children: [
                      const Text('⚡', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('보유 긴급 호출 이용권',
                              style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text('$remainingCount개',
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _white, height: 1)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // 상품 카드
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEB),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.bolt_rounded, size: 24, color: Color(0xFFEF4444)),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('긴급 호출 이용권',
                                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _text)),
                                Text('단건 구매 · 1회 사용',
                                    style: TextStyle(fontSize: 12, color: _label)),
                              ],
                            ),
                          ),
                          const Text('₩7,900',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFFEF4444))),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      const _BenefitRow(icon: Icons.bolt_rounded,         iconColor: Color(0xFFEF4444), text: '즉시 노출 + 활동지수 높은 알바생 직접 선택'),
                      const SizedBox(height: 12),
                      const _BenefitRow(icon: Icons.people_alt_rounded,   iconColor: Color(0xFFEF4444), text: '반경 3km 내 최대 10명에게 인앱 메시지 발송'),
                      const SizedBox(height: 12),
                      const _BenefitRow(icon: Icons.shield_outlined,      iconColor: _green,           text: '응답자 0명이면 이용권 100% 자동 반환'),
                      const SizedBox(height: 12),
                      const _BenefitRow(icon: Icons.no_accounts_outlined,  iconColor: _label,           text: '개인정보 비노출 인앱 메시지'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 구독 넛지
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F7FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _blue.withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.workspace_premium_rounded, size: 18, color: _blue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('구독이 더 저렴해요',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _blue)),
                            const SizedBox(height: 4),
                            const Text(
                              '구독 라이트로 전환하면 이번 달 긴급 호출 1회가 포함돼요 (₩9,900/월)',
                              style: TextStyle(fontSize: 12, color: _sub, height: 1.5),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () => Navigator.pushNamed(context, '/subscribe'),
                              child: const Text(
                                '구독 보러가기 →',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _blue),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _BottomCta(
          isSelected: true,
          isPurchasing: isPurchasing,
          label: '₩7,900 긴급 호출 이용권 구매',
          color: const Color(0xFFEF4444),
          onTap: isPurchasing ? null : onBuy,
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════
// 공용 위젯
// ════════════════════════════════════════════════════════
class _BottomCta extends StatelessWidget {
  final bool isSelected;
  final bool isPurchasing;
  final String label;
  final Color? color;
  final VoidCallback? onTap;
  const _BottomCta({
    required this.isSelected,
    required this.isPurchasing,
    required this.label,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = isSelected && !isPurchasing && onTap != null;
    final btnColor = color ?? _blue;
    return Container(
      decoration: BoxDecoration(
        color: _white,
        border: Border(top: BorderSide(color: _border)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 54,
            decoration: BoxDecoration(
              gradient: active
                  ? LinearGradient(colors: [btnColor, btnColor.withOpacity(0.85)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : const LinearGradient(colors: [_border, _border]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: active
                  ? [BoxShadow(color: btnColor.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))]
                  : [],
            ),
            child: Center(
              child: isPurchasing
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: _white, strokeWidth: 2.5))
                  : Text(label, style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800,
                      color: active ? _white : _label,
                    )),
            ),
          ),
        ),
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  final String label;
  final bool isPurchasing;
  final List<Color> gradient;
  final VoidCallback? onTap;
  const _BuyButton({required this.label, required this.isPurchasing, required this.gradient, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: isPurchasing ? null : onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPurchasing ? [_border, _border] : gradient,
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: isPurchasing ? [] : [
          BoxShadow(color: gradient.first.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: Center(
        child: isPurchasing
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: _white, strokeWidth: 2))
            : Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _white)),
      ),
    ),
  );
}

class _PriceChip extends StatelessWidget {
  final String label;
  final Color  color;
  final Color  bgColor;
  final bool   bold;
  const _PriceChip({required this.label, required this.color, required this.bgColor, required this.bold});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(99)),
    child: Text(label, style: TextStyle(
      fontSize: 12, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    )),
  );
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   text;
  const _BenefitRow({required this.icon, required this.iconColor, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: iconColor),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: _sub, fontWeight: FontWeight.w500))),
    ],
  );
}
