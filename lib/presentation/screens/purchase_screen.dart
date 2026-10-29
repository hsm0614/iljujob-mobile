// File: lib/presentation/screens/purchase_pass_screen.dart
import 'dart:async';
import 'package:iljujob/widget/app_ui.dart';
import 'package:iljujob/widget/app_motion.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../../config/constants.dart';
import '../../data/models/pass_product_config.dart';
import '../../data/services/commerce_catalog_service.dart';
import '../../data/services/authenticated_http_client.dart';
import 'potrone_screen.dart';

// ── 디자인 토큰 ──
// 긴급호출 색(2026-10 빨강→주황). 이름은 호환 때문에 유지

// ── iOS 상품 ID ──
const _kIosInstant = {
  1: 'com.iljujob.pass1',
  3: 'com.iljujob.pass10',
  5: 'com.iljujob.pass20',
  10: 'com.iljujob.pass30',
};
const _kIosUrgent1 = 'com.iljujob.urgent1';
const _kIosInstant7 = 'com.iljujob.pass7d1';

bool _isPassProduct(String id) =>
    _kIosInstant.values.contains(id) ||
    id == _kIosUrgent1 ||
    id == _kIosInstant7;

class _StoreVerifyFailure implements Exception {
  final String message;
  // 400: 다시 보내도 안 되는 거래(번들·상품 불일치 등). 그 외는 재시도 대상.
  final bool permanent;
  const _StoreVerifyFailure(this.message, {required this.permanent});
  @override
  String toString() => message;
}

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
  int remainingInstant7 = 0;
  int remainingUrgent = 0;
  List<Map<String, dynamic>> _instantOptions = const [];
  bool _catalogReady = false;

  String companyName = '';
  String companyPhone = '';

  final formatter = NumberFormat('#,###');

  // IAP
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  Completer<PurchaseDetails>? _purchaseCompleter;
  bool _isPurchasing = false;
  String? _pendingPassType; // 결제 중인 패스 타입
  final Set<String> _handledPurchaseIds = {};

  String formatPrice(int n) => '${formatter.format(n)}원';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _refreshPassCount();
    _loadCatalog();
    _loadUserInfo();
    // 끝나지 않은 거래는 아래 리스너가 서버 검증 후에 완료한다.
    // 예전엔 화면 진입 시 검증 없이 전부 강제 종료해서, 검증이 실패했던 결제는 이용권 없이 사라졌다.
    if (Platform.isIOS) {
      _purchaseSub = _iap.purchaseStream.listen(
        _onPurchaseUpdated,
        onDone: () => _purchaseSub?.cancel(),
        onError: (e) {
          if (mounted) _showErrorDialog('결제 오류: $e');
        },
      );
    }
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

  Future<void> _refreshPassCount() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;
    final res = await AuthenticatedHttpClient.get(
      Uri.parse('$baseUrl/api/pass/remain?clientId=$clientId'),
    );
    if (res.statusCode == 200 && mounted) {
      final data = jsonDecode(res.body);
      setState(() {
        remainingInstant =
            int.tryParse('${data['instant'] ?? data['remaining'] ?? 0}') ?? 0;
        remainingUrgent = int.tryParse('${data['urgent'] ?? 0}') ?? 0;
        remainingInstant7 = int.tryParse('${data['instant7'] ?? 0}') ?? 0;
      });
    }
  }

  Future<void> _loadCatalog() async {
    try {
      final products = await const CommerceCatalogService().fetchProducts();
      final options = instantOptionsForCatalog(products);
      if (mounted) {
        setState(() {
          _instantOptions = options;
          _catalogReady = options.isNotEmpty;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _catalogReady = false);
    }
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      companyName = prefs.getString('companyName') ?? '';
      companyPhone =
          prefs.getString('companyPhone') ?? prefs.getString('userPhone') ?? '';
    });
  }

  // ─── 에러 다이얼로그 ──────────────────────────────────
  void _showErrorDialog(String msg) {
    if (!mounted) return;
    showAppSheet(context, title: '진행하지 못했어요', message: msg);
  }

  // ─── iOS JWS 서버 검증 ────────────────────────────────
  Future<void> _verifyIosOnServer({
    required String productId,
    required String transactionId,
    required String jwsTransaction,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;
    final res = await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/pass/verify-ios'),
      headers: {'Accept': 'application/json'},
      body: {
        'clientId': clientId,
        'productId': productId,
        'transactionId': transactionId,
        'jwsTransaction': jwsTransaction,
      },
    );
    if (res.statusCode != 200) {
      String msg = '검증 실패';
      try {
        msg = jsonDecode(res.body)['message'] ?? msg;
      } catch (_) {}
      throw _StoreVerifyFailure(msg, permanent: res.statusCode == 400);
    }
  }

  // ─── iOS IAP 구매 ─────────────────────────────────────
  Future<void> _buyWithIAP(String productId, String passType) async {
    if (!mounted) return;
    if (_isPurchasing ||
        (_purchaseCompleter != null && !_purchaseCompleter!.isCompleted)) {
      return;
    }

    setState(() => _isPurchasing = true);
    _handledPurchaseIds.clear();
    _pendingPassType = passType;
    _purchaseCompleter = Completer<PurchaseDetails>();

    try {
      final available = await _iap.isAvailable();
      if (!available) {
        throw Exception('IAP 서비스를 사용할 수 없습니다 (isAvailable=false)');
      }

      final resp = await _iap.queryProductDetails({productId});

      // 디버그: 콘솔에서 확인
      debugPrint('🛒 IAP query [$productId]');
      debugPrint('  found: ${resp.productDetails.map((p) => p.id).toList()}');
      debugPrint('  notFound: ${resp.notFoundIDs}');
      debugPrint('  error: ${resp.error}');

      if (resp.productDetails.isEmpty) {
        final detail =
            resp.notFoundIDs.isNotEmpty
                ? '스토어에 상품 ID가 없음: ${resp.notFoundIDs}'
                : resp.error != null
                ? '스토어 오류: ${resp.error?.message}'
                : '알 수 없는 오류';
        throw Exception('상품 조회 실패\n$detail');
      }

      await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: resp.productDetails.first),
        // 서버 검증과 이용권 지급이 끝난 뒤에만 consume한다.
        // 먼저 consume하면 검증 실패 시 구매를 다시 전달받을 수 없다.
        autoConsume: false,
      );

      await _purchaseCompleter!.future.timeout(const Duration(minutes: 5));
      if (mounted) await _refreshPassCount();
    } catch (e) {
      if (mounted) _showErrorDialog('결제 처리 중 오류: $e');
    } finally {
      _pendingPassType = null;
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

      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        // 이 화면은 이용권 상품만 처리한다. 구독 거래는 구독 화면이 검증·완료한다.
        if (!_isPassProduct(p.productID)) continue;
        final purchaseKey =
            p.purchaseID ?? '${p.productID}-${p.transactionDate ?? ''}';
        if (_handledPurchaseIds.contains(purchaseKey)) {
          // 같은 거래 이벤트가 서버 검증 중 다시 올 수 있다. 첫 이벤트가 검증을
          // 끝내기 전에 여기서 완료하면 결제만 끝나고 이용권이 유실될 수 있다.
          continue;
        }
        _handledPurchaseIds.add(purchaseKey);

        try {
          if (Platform.isIOS) {
            final jws = p.verificationData.serverVerificationData;
            if (jws.isEmpty) throw Exception('JWS 트랜잭션이 없습니다.');
            await _verifyIosOnServer(
              productId: p.productID,
              transactionId: p.purchaseID ?? '',
              jwsTransaction: jws,
            );
            if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          }
          if (!_purchaseCompleterIsDone) _purchaseCompleter?.complete(p);

          if (mounted) {
            final isUrgent =
                p.productID == _kIosUrgent1 || _pendingPassType == 'urgent';
            await _refreshPassCount();
            if (widget.fromPostJob) {
              await Future.delayed(const Duration(milliseconds: 600));
              if (mounted) Navigator.pop(context, {'success': true});
            } else {
              await _showBought(
                isUrgent
                    ? 'urgent'
                    : p.productID == _kIosInstant7
                    ? 'instant_7d'
                    : 'instant',
              );
            }
          }
        } catch (e) {
          _handledPurchaseIds.remove(purchaseKey);
          // 영구 실패만 거래를 끝낸다. 네트워크·서버 오류는 끝내지 않아야
          // StoreKit 이 다음에 다시 전달해 이용권을 받을 수 있다.
          if (e is _StoreVerifyFailure &&
              e.permanent &&
              Platform.isIOS &&
              p.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(p);
            } catch (_) {}
          }
          if (!_purchaseCompleterIsDone) _purchaseCompleter?.completeError(e);
          if (mounted) _showErrorDialog('서버 검증 실패: $e');
        }
        continue;
      }

      if (p.status == PurchaseStatus.error ||
          p.status == PurchaseStatus.canceled) {
        if (!_purchaseCompleterIsDone) _purchaseCompleter?.completeError('취소됨');
        if (mounted) setState(() => _isPurchasing = false);
      }
    }
  }

  // ─── Android 결제 검증 ────────────────────────────────
  Future<void> _purchaseWithPortOne({
    required int count,
    required int amount,
    required String passType,
    String? productName,
  }) async {
    if (!mounted || _isPurchasing) return;
    setState(() => _isPurchasing = true);
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => PortonePaymentScreen(
                count: count,
                companyName: companyName,
                companyPhone: companyPhone,
                amount: amount,
                productName: productName,
              ),
        ),
      );
      if (!mounted) return;
      if (result is Map &&
          result['success'] == true &&
          result['imp_uid'] != null) {
        await _verifyAndroidOnServer(
          impUid: result['imp_uid'].toString(),
          count: count,
          passType: passType,
        );
      }
    } catch (_) {
      if (mounted) _showErrorDialog('결제 화면을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  Future<void> _verifyAndroidOnServer({
    required String impUid,
    required int count,
    required String passType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;
    try {
      final res = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/pass/verify'),
        body: {
          'impUid': impUid,
          'clientId': clientId,
          'platform': 'android',
          'count': count,
          'passType': passType,
        },
      );
      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(res.body);
      } catch (_) {}

      if (res.statusCode == 200 && data['ok'] == true) {
        if (!mounted) return;
        await _refreshPassCount();
        if (widget.fromPostJob) {
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) Navigator.pop(context, {'success': true});
        } else {
          await _showBought(passType);
        }
      } else {
        final message = data['message'] ?? '이용권 지급에 실패했습니다.';
        if (mounted) {
          _showErrorDialog('결제는 완료됐으나 지급 오류입니다.\n고객센터에 문의해주세요.\n\n($message)');
        }
      }
    } catch (_) {
      if (mounted) _showErrorDialog('네트워크 오류입니다. 잠시 후 다시 시도해주세요.');
    }
  }

  // ─── 긴급 결제 후 구독 넛지 ──────────────────────────
  // 결제 뒤: 스낵바 한 줄(즉시 게시) / 주황 아이콘 상자·'지급 완료!'·파란 구독 상자 시트(긴급)
  // → 공용 완료 화면 하나. 다음 할 일은 공고 올리기 (긴급 직후 구독을 권하던 것은 뺐다)
  Future<void> _showBought(String passType) async {
    if (!mounted) return;
    final urgent = passType == 'urgent';
    final sevenDay = passType == 'instant_7d';
    final r = await showAppSuccess(
      context,
      title:
          urgent
              ? '긴급 호출 이용권을 받았어요'
              : sevenDay
              ? '즉시 게시 7일권을 받았어요'
              : '즉시 게시 이용권을 받았어요',
      message:
          urgent ? '공고를 올린 뒤 근처 알바생에게 바로 연락할 수 있어요' : '공고를 올릴 때 바로 공개할 수 있어요',
      facts: [
        (
          urgent
              ? '보유 긴급 호출'
              : sevenDay
              ? '보유 7일권'
              : '보유 즉시 게시',
          '${urgent
              ? remainingUrgent
              : sevenDay
              ? remainingInstant7
              : remainingInstant}개',
        ),
      ],
      primaryLabel: '공고 올리기',
      secondaryLabel: '닫기',
    );
    if (r == 'primary' && mounted) Navigator.pushNamed(context, '/post_job');
  }

  // ─── 즉시 게시 구매 확인 시트 ────────────────────────
  // 고르고 '구매하기' → 확인 시트 → '결제하기'로 같은 결정을 두 번 받던 것을 한 번으로 (2026-10).
  // 금액은 하단 버튼 글자('8,900원 결제하기')가 말한다. 스토어·PortOne 결제창이 마지막 확인이다.
  Future<void> _payInstant(Map<String, dynamic> option) async {
    if (_isPurchasing) return;
    final count = option['count'] as int;
    final price = option['price'] as int;
    final passType = option['passType'] as String;
    if (Platform.isIOS) {
      final productId =
          passType == 'instant_7d' ? _kIosInstant7 : _kIosInstant[count];
      if (productId != null) await _buyWithIAP(productId, passType);
    } else {
      await _purchaseWithPortOne(
        count: count,
        amount: price,
        passType: passType,
        productName:
            passType == 'instant_7d'
                ? '알바일주 즉시게시 7일 이용권'
                : option['days'] == 3
                ? '알바일주 즉시게시 3일 이용권 $count회'
                : null,
      );
    }
  }

  Future<void> _payUrgent() async {
    if (_isPurchasing) return;
    if (Platform.isIOS) {
      await _buyWithIAP(_kIosUrgent1, 'urgent');
    } else {
      await _purchaseWithPortOne(
        count: 1,
        amount: 13900,
        passType: 'urgent',
        productName: '알바일주 긴급 호출 이용권',
      );
    }
  }

  // ─── Build ────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AppBar(
        title: const Text('이용권 구매'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textTertiary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 2,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: AppFontSize.button,
          ),
          tabs: const [Tab(text: '즉시 게시'), Tab(text: '긴급 호출')],
        ),
      ),
      body: Column(
        children: [
          // ── TabBarView ──
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                if (!_catalogReady)
                  Center(
                    child: TextButton(
                      onPressed: _loadCatalog,
                      child: const Text('상품 정보를 불러오지 못했어요 · 다시 시도'),
                    ),
                  )
                else
                  _InstantTab(
                    remainingCount: remainingInstant,
                    remainingSevenDay: remainingInstant7,
                    options: _instantOptions,
                    isPurchasing: _isPurchasing,
                    onSelect: _payInstant,
                    formatPrice: formatPrice,
                  ),
                _UrgentTab(
                  remainingCount: remainingUrgent,
                  isPurchasing: _isPurchasing,
                  onBuy: _payUrgent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// 즉시 게시 탭
// ════════════════════════════════════════════════════════
// 큰 파란 '보유 0개' 상자·숫자 타일·가격 알약·오른쪽 아래 라디오 → 보유 한 줄 + 공고 올리기 등록 방식과 같은 선택 행.
// 처음부터 1회가 골라져 있다 — 공고 올리기에서 '결제하고 바로 올리기'로 넘어온 사장님이 대부분이다.
class _InstantTab extends StatefulWidget {
  final int remainingCount;
  final int remainingSevenDay;
  final List<Map<String, dynamic>> options;
  final bool isPurchasing;
  final void Function(Map<String, dynamic> option) onSelect;
  final String Function(int) formatPrice;
  const _InstantTab({
    required this.remainingCount,
    required this.remainingSevenDay,
    required this.options,
    required this.isPurchasing,
    required this.onSelect,
    required this.formatPrice,
  });
  @override
  State<_InstantTab> createState() => _InstantTabState();
}

class _InstantTabState extends State<_InstantTab> {
  late String _selectedId = widget.options.first['id'] as String;

  @override
  Widget build(BuildContext context) {
    final opt = widget.options.firstWhere(
      (o) => o['id'] == _selectedId,
      orElse: () => widget.options.first,
    );
    final price = opt['price'] as int;
    final durationPolicy = widget.options.any(
      (o) => o['passType'] == 'instant_7d',
    );
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              _OwnedLine(
                label: durationPolicy ? '보유 즉시 게시 3일권' : '보유 즉시 게시 이용권',
                count: widget.remainingCount,
              ),
              if (durationPolicy) ...[
                const SizedBox(height: 8),
                _OwnedLine(
                  label: '보유 즉시 게시 7일권',
                  count: widget.remainingSevenDay,
                ),
              ],
              const SizedBox(height: 20),
              Text(
                durationPolicy ? '기간과 횟수를 고르세요' : '몇 개 살까요?',
                style: AppTextStyles.h2,
              ),
              const SizedBox(height: 4),
              const Text('남은 이용권은 만료 없이 다음 공고에 써요', style: AppTextStyles.body2),
              const SizedBox(height: 16),
              for (final o in widget.options)
                _OptionRow(
                  title: '${o['days']}일 · ${o['count']}회',
                  sub:
                      o['count'] == 1
                          ? '공고 1건을 바로 공개 · 알바생 알림 2회'
                          : '회당 ${widget.formatPrice(((o['price'] as int) / (o['count'] as int)).floor())}'
                              '${_discount(o) > 0 ? ' · ${_discount(o)}% 할인' : ''}',
                  price: widget.formatPrice(o['price'] as int),
                  tag: o['tag'] as String?,
                  selected: _selectedId == o['id'],
                  onTap: () => setState(() => _selectedId = o['id'] as String),
                ),
            ],
          ),
        ),
        AppBottomBar(
          child: AppPrimaryButton(
            label: '${widget.formatPrice(price)} 결제하기',
            loading: widget.isPurchasing,
            onPressed: () => widget.onSelect(opt),
          ),
        ),
      ],
    );
  }

  int _discount(Map<String, dynamic> o) {
    final c = o['count'] as int;
    final full = 8900 * c;
    return c == 1 || o['passType'] == 'instant_7d'
        ? 0
        : (((full - (o['price'] as int)) / full) * 100).round();
  }
}

// ════════════════════════════════════════════════════════
// 긴급 호출 탭
// ════════════════════════════════════════════════════════
// 빨강 보유 상자·그림자 카드·아이콘 상자 혜택 4줄·파란 구독 상자 → 즉시 게시 탭과 같은 뼈대.
// 상품이 하나라 선택 행 하나(이미 골라짐) + 무엇을 해 주는지 세 줄.
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
    Widget line(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_rounded,
              size: 16,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t,
              style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              _OwnedLine(label: '보유 긴급 호출 이용권', count: remainingCount),
              const SizedBox(height: 20),
              const Text('갑자기 사람이 빌 때', style: AppTextStyles.h2),
              const SizedBox(height: 4),
              const Text(
                '근무지 5km 안 알바생에게 사장님이 직접 연락해요',
                style: AppTextStyles.body2,
              ),
              const SizedBox(height: 16),
              _OptionRow(
                title: '1회',
                sub: '공고 1건',
                price: '13,900원',
                selected: true,
                onTap: () {},
              ),
              const SizedBox(height: 12),
              line('바로 공개되고 24시간 맨 위에 고정돼요'),
              line('활동 많은 순으로 고른 알바생 최대 10명에게 메시지를 보내요 · 번호는 공개되지 않아요'),
              line('아무도 답하지 않으면 이용권을 돌려드려요'),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '매달 쓴다면 구독이 더 저렴해요',
                      style: AppTextStyles.body2,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/subscribe'),
                    child: const Text('구독 보기'),
                  ),
                ],
              ),
            ],
          ),
        ),
        AppBottomBar(
          child: AppPrimaryButton(
            label: '13,900원 결제하기',
            loading: isPurchasing,
            onPressed: onBuy,
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════
// 공용 위젯
// ════════════════════════════════════════════════════════
class _OwnedLine extends StatelessWidget {
  final String label;
  final int count;
  const _OwnedLine({required this.label, required this.count});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.bgMuted,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      children: [
        Expanded(child: Text(label, style: AppTextStyles.body2)),
        Text(
          '$count개',
          style: AppTextStyles.body1.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    ),
  );
}

/// 큰 선택 = 연파랑 바탕 + 파란 테두리, 라디오는 왼쪽 (공고 올리기 등록 방식과 같은 모양)
class _OptionRow extends StatelessWidget {
  final String title;
  final String sub;
  final String price;
  final String? tag;
  final bool selected;
  final VoidCallback onTap;
  const _OptionRow({
    required this.title,
    required this.sub,
    required this.price,
    this.tag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: selected ? AppColors.primaryLight : AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 22,
                color: selected ? AppColors.primary : AppColors.textDisabled,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.body1.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (tag != null) ...[
                          const SizedBox(width: 6),
                          JobSignalBadge(label: tag!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(sub, style: AppTextStyles.body2),
                  ],
                ),
              ),
              Text(
                price,
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
