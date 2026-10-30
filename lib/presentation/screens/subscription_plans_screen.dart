// lib/presentation/screens/subscription_plans_screen.dart
//
// 알바일주 구독 플랜 선택 화면 (베이직/무제한 — 내부 키는 lite/pro)
import 'dart:async';
import 'package:iljujob/widget/app_ui.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../data/services/iap_platform.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_theme.dart';
import '../../config/constants.dart';
import '../../config/messages.dart';
import '../../data/models/subscription_product_config.dart';
import '../../data/services/authenticated_http_client.dart';
import '../../data/services/client_tracking_service.dart';
import 'potrone_screen.dart';

typedef _Plan = SubscriptionProductConfig;
const _plans = subscriptionProductConfigs;

class SubscriptionPlansScreen extends StatefulWidget {
  const SubscriptionPlansScreen({super.key});
  @override
  State<SubscriptionPlansScreen> createState() =>
      _SubscriptionPlansScreenState();
}

class _SubscriptionPlansScreenState extends State<SubscriptionPlansScreen> {
  String _selectedPlan = 'lite';
  bool _processing = false;
  int? _userId;
  String? _companyName;
  String? _companyPhone;
  final InAppPurchasePlatform _iap = iap;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  final Set<String> _handledIds = {};
  final Map<String, String> _storePrices = {};

  @override
  void initState() {
    super.initState();
    _loadUser();
    if (Platform.isIOS) {
      _purchaseSub = _iap.purchaseStream.listen(_onPurchase, onError: (_) {});
      _loadStorePrices();
    }
    ClientTrackingService.instance.track('subscription_page_view');
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  _Plan get _plan => _plans.firstWhere((p) => p.key == _selectedPlan);

  Future<void> _loadStorePrices() async {
    try {
      final response = await _iap.queryProductDetails(
        _plans.map((plan) => plan.iosId).toSet(),
      );
      if (!mounted) return;
      setState(() {
        for (final product in response.productDetails) {
          _storePrices[product.id] = product.price;
        }
      });
    } catch (_) {}
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userId = prefs.getInt('userId');
      _companyName = prefs.getString('companyName');
      _companyPhone = prefs.getString('companyPhone');
    });
  }

  Future<void> _purchase() async {
    if (_processing) return;
    final plan = _plan;
    ClientTrackingService.instance.track(
      'subscription_plan_tap',
      properties: {'plan': plan.key},
    );

    try {
      final status = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/subscription/status'),
      );
      if (status.statusCode != 200 ||
          (jsonDecode(status.body)
                  as Map<String, dynamic>)['v3ProductsPublic'] !=
              true) {
        if (mounted) _showError('새 구독 상품을 준비 중입니다. 잠시 뒤 다시 확인해 주세요.');
        return;
      }
    } catch (_) {
      if (mounted) _showError('구독 상품 상태를 확인할 수 없습니다. 잠시 뒤 다시 시도해 주세요.');
      return;
    }
    if (!mounted) return;

    if (checkoutProviderForPlatform(isIos: Platform.isIOS) ==
        CheckoutProvider.appStore) {
      await _purchaseStore(plan);
    } else {
      await _purchaseWithPortOne(plan);
    }
  }

  // iOS는 새 v3 상품 ID로 구매하되 화면의 플랜명은 유지한다.
  Future<void> _purchaseStore(_Plan plan) async {
    setState(() => _processing = true);
    try {
      final available = await _iap.isAvailable();
      if (!available) throw Exception('스토어를 사용할 수 없습니다');

      final productId = plan.iosId;
      final resp = await _iap.queryProductDetails({productId});
      if (resp.productDetails.isEmpty) {
        throw Exception('상품 정보를 불러올 수 없습니다. ($productId)');
      }
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: resp.productDetails.first),
      );
    } catch (e) {
      setState(() => _processing = false);
      _showError(e.toString());
    }
  }

  void _onPurchase(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (!isSubscriptionProductId(p.productID)) continue;
      final purchaseKey =
          p.purchaseID ?? '${p.productID}-${p.transactionDate ?? ''}';
      if (_handledIds.contains(purchaseKey)) continue;

      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        _handledIds.add(purchaseKey);
        final activated = await _activateIosOnServer(p);
        if (activated) {
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        } else {
          _handledIds.remove(purchaseKey);
        }
      } else if (p.status == PurchaseStatus.error) {
        setState(() => _processing = false);
        _showError('결제 중 오류가 발생했어요.');
      } else if (p.status == PurchaseStatus.canceled) {
        setState(() => _processing = false);
      }
    }
  }

  Future<bool> _activateIosOnServer(PurchaseDetails purchase) async {
    final token = purchase.verificationData.serverVerificationData;
    if (token.isEmpty) return false;
    try {
      final resp = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/iap/verify'),
        body: {
          'platform': 'app_store',
          'productId': purchase.productID,
          'purchaseId': purchase.purchaseID,
          'token': token,
          'isReactivation': purchase.status == PurchaseStatus.restored,
        },
      );
      if (!mounted) return resp.statusCode == 200;
      if (resp.statusCode == 200) {
        final isNewProduct = purchase.productID.contains('.v3.');
        ClientTrackingService.instance.track(
          'subscription_success',
          properties: {'product_id': purchase.productID},
        );
        if (isNewProduct) {
          _showSuccess();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('기존 구독이 복원됐어요. 관리 화면에서 혜택을 확인해 주세요.')),
          );
        }
        return true;
      }
      _showError('구독 검증에 실패했어요. 결제는 다시 확인됩니다.');
      return false;
    } catch (_) {
      if (mounted) _showError('서버 연결 오류가 발생했어요. 결제는 다시 확인됩니다.');
      return false;
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _purchaseWithPortOne(_Plan plan) async {
    if (!mounted) return;
    setState(() => _processing = true);
    try {
      final status = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/subscription/status'),
      );
      if (status.statusCode != 200) {
        throw Exception('구독 상태를 확인할 수 없습니다. 잠시 뒤 다시 시도해 주세요.');
      }
      final current = jsonDecode(status.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (current['active'] == true) {
        _showError('현재 구독이 끝난 뒤 새 기간권을 구매해 주세요. 중복 결제를 막기 위해 결제창을 열지 않았어요.');
        return;
      }
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => PortonePaymentScreen(
                count: 1,
                companyName: _companyName ?? '알바일주',
                companyPhone: _companyPhone ?? '',
                amount: plan.price,
                productName: '알바일주 ${plan.name} 구독',
              ),
        ),
      );
      if (result is Map && result['imp_uid'] != null) {
        await _activatePortOneOnServer(result['imp_uid']?.toString());
      }
    } catch (_) {
      if (mounted) _showError(Msg.server);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<bool> _activatePortOneOnServer(String? impUid) async {
    if (impUid == null || impUid.isEmpty) return false;
    try {
      final resp = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/subscription/activate'),
        body: {'clientId': _userId, 'plan': _selectedPlan, 'impUid': impUid},
      );
      if (!mounted) return resp.statusCode == 200;
      if (resp.statusCode == 200) {
        ClientTrackingService.instance.track(
          'subscription_success',
          properties: {'plan': _selectedPlan},
        );
        _showSuccess();
        return true;
      }
      _showError('구독 활성화에 실패했어요. 고객센터에 문의해주세요.');
      return false;
    } catch (_) {
      if (mounted) _showError(Msg.server);
      return false;
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    showAppSheet(context, title: '진행하지 못했어요', message: msg);
  }

  void _showSuccess() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final bottom = MediaQuery.of(context).viewPadding.bottom;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
          ),
          padding: EdgeInsets.fromLTRB(20, 28, 20, 24 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '구독이 시작되었어요!',
                style: TextStyle(
                  fontSize: AppFontSize.h2,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Jalnan2TTF',
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_plan.name} 플랜의 기간 혜택이 시작됐어요.\n즉시게시·먼저 연락·지도 알림 잔여량을 확인해 주세요.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppFontSize.button,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context, true);
                  },
                  child: const Text(
                    '확인'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '뒤로',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('구독 플랜'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 헤더
                    const Text(
                      '알바일주 구독으로\n더 빠르게 채용하세요',
                      style: TextStyle(
                        fontSize: AppFontSize.h2,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '결제 기간 동안 먼저 연락하고 지도에서 알릴 수 있어요',
                      style: TextStyle(
                        fontSize: AppFontSize.body2,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 플랜 카드들
                    ..._plans.map(
                      (plan) => _PlanCard(
                        plan: plan,
                        displayPrice:
                            Platform.isIOS
                                ? (_storePrices[plan.iosId] ?? '가격 확인 중')
                                : null,
                        selected: plan.key == _selectedPlan,
                        onTap: () => setState(() => _selectedPlan = plan.key),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 비교표
                    _CompareTable(selectedPlan: _selectedPlan),

                    const SizedBox(height: 20),

                    // 유의사항
                    _Notice(isStoreBilling: Platform.isIOS),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // 하단 CTA
            _BottomCta(
              plan: _plan,
              displayPrice:
                  Platform.isIOS
                      ? (_storePrices[_plan.iosId] ?? '가격 확인 중')
                      : null,
              processing: _processing,
              onPurchase: _purchase,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 플랜 카드 ─────────────────────────────────────────────
// 플랜별 색(프로 주황·라이트 회색 테두리)·그림자·아이콘 칩 4개 → 큰 선택 규칙(연파랑+파란 테두리) 하나.
// 칩 내용은 아래 비교표와 같아서 카드엔 핵심 세 가지만 한 줄로.
class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final String? displayPrice;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({
    required this.plan,
    required this.displayPrice,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final summary = [
      plan.unlimitedInstant ? '즉시 게시 무제한' : '즉시 게시 ${plan.instantCredits}회',
      '먼저 연락 ${plan.directMonthly}명',
      plan.aiJobMonthly < 0 ? 'AI 공고문 무제한' : 'AI 공고문 ${plan.aiJobMonthly}회',
    ].join(' · ');
    final price = displayPrice ?? '${NumberFormat('#,###').format(plan.price)}원';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppSelectCard(
        selected: selected,
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                          Text(plan.name, style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          if (plan.recommended) ...[const SizedBox(width: 6), const JobSignalBadge(label: '추천')],
                          const Spacer(),
                          Text(
                            displayPrice == '가격 확인 중' ? price : '$price/월',
                            style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(summary, style: AppTextStyles.body2),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }
}

// ── 비교표 ────────────────────────────────────────────────
class _CompareTable extends StatelessWidget {
  final String selectedPlan;
  const _CompareTable({required this.selectedPlan});

  static const _rows = [
    ['즉시게시', '3회/기간', '무제한'],
    ['먼저 연락', '10명/기간', '50명/기간'],
    ['공고당 연락', '10명', '20명'],
    ['지도 알림', '2회/기간', '8회/기간'],
    ['공고당 알림', '1회', '2회'],
    ['AI 공고문', '월 3회', '무제한'],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.bgMuted,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg - 1),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: SizedBox()),
                Expanded(
                  child: Center(
                    child: Text(
                      '베이직',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '무제한',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._rows.asMap().entries.map((e) {
            final i = e.key;
            final row = e.value;
            return Container(
              decoration: BoxDecoration(
                border:
                    i < _rows.length - 1
                        ? const Border(
                          bottom: BorderSide(
                            color: AppColors.border,
                            width: 0.5,
                          ),
                        )
                        : null,
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Text(
                        row[0],
                        style: const TextStyle(
                          fontSize: AppFontSize.meta,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  ...List.generate(2, (col) {
                    final val = row[col + 1];
                    final isNone = val == '-';
                    return Expanded(
                      child: Center(
                        child:
                            isNone
                                ? const Text(
                                  '-',
                                  style: TextStyle(
                                    fontSize: AppFontSize.meta,
                                    color: AppColors.textDisabled,
                                  ),
                                )
                                : Text(
                                  val,
                                  style: const TextStyle(
                                    fontSize: AppFontSize.meta,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── 유의사항 ─────────────────────────────────────────────
class _Notice extends StatelessWidget {
  const _Notice({required this.isStoreBilling});
  final bool isStoreBilling;
  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: AppFontSize.caption,
      color: AppColors.textSecondary,
      height: 1.6,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '유의사항',
            style: TextStyle(
              fontSize: AppFontSize.meta,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isStoreBilling
                ? '• 구독은 App Store에서 자동 갱신됩니다.'
                : '• Android는 PortOne 30일 결제이며 자동 갱신되지 않습니다.',
            style: style,
          ),
          const Text('• 제공량은 결제 기간마다 초기화되며 이월되지 않습니다.', style: style),
          const Text('• 구독 취소 시 만료일까지 혜택이 유지됩니다.', style: style),
          const Text('• 결제는 구독 선택 즉시 이루어집니다.', style: style),
        ],
      ),
    );
  }
}

// ── 하단 CTA ─────────────────────────────────────────────
class _BottomCta extends StatelessWidget {
  final _Plan plan;
  final String? displayPrice;
  final bool processing;
  final VoidCallback onPurchase;
  const _BottomCta({
    required this.plan,
    required this.displayPrice,
    required this.processing,
    required this.onPurchase,
  });

  // 버튼 글자는 행동만, 얼마·어떻게 결제되는지는 버튼 위 한 줄 (공고 올리기 결제 버튼과 같은 규칙)
  @override
  Widget build(BuildContext context) {
    final checking = displayPrice == '가격 확인 중';
    final price = displayPrice ?? '${NumberFormat('#,###').format(plan.price)}원';
    final note =
        checking
            ? 'App Store 가격을 확인하고 있어요'
            : Platform.isIOS
            ? '매월 $price 자동 결제 · 언제든 해지할 수 있어요'
            : '$price · 30일 이용 · 자동으로 다시 결제되지 않아요';
    return AppBottomBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(note, style: AppTextStyles.body2, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          AppPrimaryButton(
            label: '${plan.name} 구독하기',
            loading: processing,
            onPressed: onPurchase,
          ),
        ],
      ),
    );
  }
}
