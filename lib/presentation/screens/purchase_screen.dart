// File: lib/presentation/screens/purchase_pass_screen.dart
import 'dart:async';
import 'package:iljujob/widget/app_ui.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../../config/constants.dart';
import '../../data/models/pass_product_config.dart';
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

bool _isPassProduct(String id) =>
    _kIosInstant.values.contains(id) || id == _kIosUrgent1;

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
  int remainingUrgent = 0;

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
      });
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
            } else if (isUrgent) {
              _showUrgentSuccessAndNudge();
            } else {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('이용권을 지급했어요.')));
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
        } else if (passType == 'urgent') {
          _showUrgentSuccessAndNudge();
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('이용권을 지급했어요.')));
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
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
          ),
          padding: EdgeInsets.fromLTRB(24, 8, 24, pad + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: const Center(
                  child: Icon(
                    Icons.bolt_rounded,
                    size: 30,
                    color: AppColors.badgeUrgent,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '긴급 호출 이용권 지급 완료!',
                style: TextStyle(
                  fontSize: AppFontSize.h2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '공고 등록 후 긴급 호출을 발송해보세요.',
                style: TextStyle(fontSize: AppFontSize.button, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              // 구독 넛지
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '반복 채용은 구독으로',
                            style: TextStyle(
                              fontSize: AppFontSize.body2,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '구독은 즉시게시와 먼저 연락·지도 알림을 제공합니다. 긴급호출은 별도예요.',
                            style: TextStyle(
                              fontSize: AppFontSize.meta,
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
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
                      child: const Text(
                        '구독 보러가기'),
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
  // 고르고 '구매하기' → 확인 시트 → '결제하기'로 같은 결정을 두 번 받던 것을 한 번으로 (2026-10).
  // 금액은 하단 버튼 글자('8,900원 결제하기')가 말한다. 스토어·PortOne 결제창이 마지막 확인이다.
  Future<void> _payInstant(int count, int price) async {
    if (_isPurchasing) return;
    if (Platform.isIOS) {
      final productId = _kIosInstant[count];
      if (productId != null) await _buyWithIAP(productId, 'instant');
    } else {
      await _purchaseWithPortOne(count: count, amount: price, passType: 'instant');
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
                _InstantTab(
                  remainingCount: remainingInstant,
                  options: instantPassOptions,
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
  late int _selected = widget.options.first['count'] as int;

  @override
  Widget build(BuildContext context) {
    final opt = widget.options.firstWhere((o) => o['count'] == _selected);
    final price = opt['price'] as int;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              _OwnedLine(label: '보유 즉시 게시 이용권', count: widget.remainingCount),
              const SizedBox(height: 20),
              const Text('몇 개 살까요?', style: AppTextStyles.h2),
              const SizedBox(height: 4),
              const Text('남은 이용권은 만료 없이 다음 공고에 써요', style: AppTextStyles.body2),
              const SizedBox(height: 16),
              for (final o in widget.options)
                _OptionRow(
                  title: '${o['count']}회',
                  sub:
                      o['count'] == 1
                          ? '공고 1건'
                          : '회당 ${widget.formatPrice(((o['price'] as int) / (o['count'] as int)).floor())}'
                              '${_discount(o) > 0 ? ' · ${_discount(o)}% 할인' : ''}',
                  price: widget.formatPrice(o['price'] as int),
                  tag: o['tag'] as String?,
                  selected: _selected == o['count'],
                  onTap: () => setState(() => _selected = o['count'] as int),
                ),
            ],
          ),
        ),
        AppBottomBar(
          child: AppPrimaryButton(
            label: '${widget.formatPrice(price)} 결제하기',
            loading: widget.isPurchasing,
            onPressed: () => widget.onSelect(_selected, price),
          ),
        ),
      ],
    );
  }

  int _discount(Map<String, dynamic> o) {
    final c = o['count'] as int;
    final full = 8900 * c;
    return c == 1 ? 0 : (((full - (o['price'] as int)) / full) * 100).round();
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
            child: Icon(Icons.check_rounded, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary))),
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
              const Text('근무지 5km 안 알바생에게 사장님이 직접 연락해요', style: AppTextStyles.body2),
              const SizedBox(height: 16),
              _OptionRow(title: '1회', sub: '공고 1건', price: '13,900원', selected: true, onTap: () {}),
              const SizedBox(height: 12),
              line('바로 공개되고 24시간 맨 위에 고정돼요'),
              line('활동 많은 순으로 고른 알바생 최대 10명에게 메시지를 보내요 · 번호는 공개되지 않아요'),
              line('아무도 답하지 않으면 이용권을 돌려드려요'),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: Text('매달 쓴다면 구독이 더 저렴해요', style: AppTextStyles.body2)),
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
          style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
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
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
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
                        Text(title, style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        if (tag != null) ...[const SizedBox(width: 6), JobSignalBadge(label: tag!)],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(sub, style: AppTextStyles.body2),
                  ],
                ),
              ),
              Text(price, style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    ),
  );
}
