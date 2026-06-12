// lib/presentation/screens/subscription_plans_screen.dart
//
// 알바일주 구독 플랜 선택 화면 (라이트/스탠다드/프로)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_theme.dart';
import '../../config/constants.dart';
import 'potrone_screen.dart';

// ── IAP 상품 ID ──────────────────────────────────────
const _kIosLite     = 'kr.co.iljujob.sub.lite';
const _kIosStandard = 'kr.co.iljujob.sub.standard';
const _kIosPro      = 'kr.co.iljujob.sub.pro';
const _kAndLite     = 'sub-lite';
const _kAndStandard = 'sub-standard';
const _kAndPro      = 'sub-pro';

// ── 플랜 정의 ─────────────────────────────────────────
class _Plan {
  final String key;
  final String name;
  final int    price;
  final int    instantCredits;
  final int    urgentCredits;
  final int    maxRecipients;
  final bool   attendanceCare;
  final bool   priorityCs;
  final bool   recommended;
  final String iosId;
  final String androidId;
  const _Plan({
    required this.key, required this.name, required this.price,
    required this.instantCredits, required this.urgentCredits,
    required this.maxRecipients,
    required this.attendanceCare, required this.priorityCs,
    required this.iosId, required this.androidId,
    this.recommended = false,
  });
}

const _plans = [
  _Plan(key: 'lite',     name: '라이트',   price: 9900,  instantCredits: 3, urgentCredits: 1, maxRecipients: 10, attendanceCare: false, priorityCs: false, iosId: _kIosLite,     androidId: _kAndLite),
  _Plan(key: 'standard', name: '스탠다드', price: 19900, instantCredits: 3, urgentCredits: 3, maxRecipients: 15, attendanceCare: true,  priorityCs: false, iosId: _kIosStandard, androidId: _kAndStandard, recommended: true),
  _Plan(key: 'pro',      name: '프로',     price: 39900, instantCredits: 5, urgentCredits: 5, maxRecipients: 20, attendanceCare: true,  priorityCs: true,  iosId: _kIosPro,      androidId: _kAndPro),
];

class SubscriptionPlansScreen extends StatefulWidget {
  const SubscriptionPlansScreen({super.key});
  @override
  State<SubscriptionPlansScreen> createState() => _SubscriptionPlansScreenState();
}

class _SubscriptionPlansScreenState extends State<SubscriptionPlansScreen> {
  String  _selectedPlan = 'standard';
  bool    _processing   = false;
  int?    _userId;
  String? _authToken;
  String? _companyName;
  String? _companyPhone;

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  final Set<String> _handledIds = {};

  @override
  void initState() {
    super.initState();
    _loadUser();
    if (Platform.isIOS) {
      _purchaseSub = _iap.purchaseStream.listen(_onPurchase, onError: (_) {});
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _userId      = p.getInt('userId');
      _authToken   = p.getString('authToken');
      _companyName = p.getString('companyName');
      _companyPhone= p.getString('companyPhone');
    });
  }

  _Plan get _plan => _plans.firstWhere((p) => p.key == _selectedPlan);

  Future<void> _purchase() async {
    if (_processing) return;
    final plan = _plan;

    if (Platform.isIOS) {
      await _purchaseIos(plan);
    } else {
      await _purchaseAndroid(plan);
    }
  }

  // ── iOS: IAP ─────────────────────────────────────────
  Future<void> _purchaseIos(_Plan plan) async {
    setState(() => _processing = true);
    try {
      final available = await _iap.isAvailable();
      if (!available) throw Exception('스토어를 사용할 수 없습니다');

      // 미완료 트랜잭션 정리
      final txns = await SKPaymentQueueWrapper().transactions();
      for (final t in txns) {
        await SKPaymentQueueWrapper().finishTransaction(t);
      }

      final resp = await _iap.queryProductDetails({plan.iosId});
      if (resp.productDetails.isEmpty) {
        throw Exception('상품 정보를 불러올 수 없습니다. (${plan.iosId})');
      }
      await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: resp.productDetails.first));
    } catch (e) {
      setState(() => _processing = false);
      _showError(e.toString());
    }
  }

  void _onPurchase(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (_handledIds.contains(p.purchaseID)) continue;

      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        _handledIds.add(p.purchaseID ?? '');
        await _activateServer(p.verificationData.serverVerificationData);
        await _iap.completePurchase(p);
      } else if (p.status == PurchaseStatus.error) {
        setState(() => _processing = false);
        _showError('결제 중 오류가 발생했어요.');
        await _iap.completePurchase(p);
      } else if (p.status == PurchaseStatus.canceled) {
        setState(() => _processing = false);
      }
    }
  }

  // ── Android: Portone ─────────────────────────────────
  Future<void> _purchaseAndroid(_Plan plan) async {
    final name  = _companyName  ?? '알바일주';
    final phone = _companyPhone ?? '';
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PortonePaymentScreen(
          count: 1,
          companyName: name,
          companyPhone: phone,
          amount: plan.price,
          productName: '알바일주 ${plan.name} 구독',
        ),
      ),
    );
    if (result is Map && result['imp_uid'] != null) {
      await _activateServer(result['imp_uid']);
    }
  }

  Future<void> _activateServer(String? token) async {
    if (token == null) return;
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/subscription/activate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_authToken ?? ''}',
        },
        body: jsonEncode({
          'clientId': _userId,
          'plan': _selectedPlan,
          'impUid': token,
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        _showSuccess();
      } else {
        _showError('구독 활성화에 실패했어요. 고객센터에 문의해주세요.');
      }
    } catch (_) {
      if (mounted) _showError('서버 연결 오류가 발생했어요.');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showError(String msg) {
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
            child: const Text('확인', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(20, 28, 20, 24 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.workspace_premium_rounded, size: 32, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              const Text(
                '구독이 시작되었어요!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFamily: 'Jalnan2TTF', color: Color(0xFF111827)),
              ),
              const SizedBox(height: 8),
              Text(
                '${_plan.name} 플랜 크레딧이\n계정에 지급되었습니다.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('확인', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
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
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.3, color: Color(0xFF111827)),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '미사용 크레딧은 1개월 이월됩니다',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 24),

                    // 플랜 카드들
                    ..._plans.map((plan) => _PlanCard(
                      plan: plan,
                      selected: plan.key == _selectedPlan,
                      onTap: () => setState(() => _selectedPlan = plan.key),
                    )),

                    const SizedBox(height: 20),

                    // 비교표
                    _CompareTable(selectedPlan: _selectedPlan),

                    const SizedBox(height: 20),

                    // 유의사항
                    const _Notice(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // 하단 CTA
            _BottomCta(
              plan: _plan,
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
class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({required this.plan, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _planColor(plan.key);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))] : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 선택 라디오
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? color : Colors.transparent,
                    border: Border.all(color: selected ? color : const Color(0xFFD1D5DB), width: 1.5),
                  ),
                  child: selected ? const Icon(Icons.circle, size: 10, color: Colors.white) : null,
                ),
                const SizedBox(width: 10),
                Text(plan.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: selected ? color : const Color(0xFF111827))),
                if (plan.recommended) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
                    child: const Text('추천', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ],
                const Spacer(),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: NumberFormat('#,###').format(plan.price),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: selected ? color : const Color(0xFF111827)),
                      ),
                      const TextSpan(
                        text: '원/월',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(icon: Icons.flash_on_rounded, label: '즉시 게시 ${plan.instantCredits}회', color: AppColors.primary),
                _Chip(icon: Icons.bolt_rounded, label: '긴급 호출 ${plan.urgentCredits}회 (${plan.maxRecipients}명)', color: const Color(0xFFEF4444)),
                _Chip(icon: Icons.workspace_premium_rounded, label: '구독 배지', color: const Color(0xFFFF9500)),
                if (plan.attendanceCare)
                  _Chip(icon: Icons.verified_user_rounded, label: '출근 안심', color: const Color(0xFF22C55E)),
                if (plan.priorityCs)
                  _Chip(icon: Icons.headset_mic_rounded, label: '우선 CS', color: const Color(0xFF6366F1)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _planColor(String key) {
    if (key == 'pro')      return const Color(0xFFFF9500);
    if (key == 'standard') return AppColors.primary;
    return const Color(0xFF6B7280);
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );
}

// ── 비교표 ────────────────────────────────────────────────
class _CompareTable extends StatelessWidget {
  final String selectedPlan;
  const _CompareTable({required this.selectedPlan});

  static const _rows = [
    ['즉시 게시', '3회', '3회', '5회'],
    ['긴급 호출', '1회', '3회', '5회'],
    ['발송 인원', '10명', '15명', '20명'],
    ['출근 안심', '-',  '포함', '포함'],
    ['구독 배지', '포함', '포함', '포함'],
    ['크레딧 이월', '1개월', '1개월', '1개월'],
    ['우선 CS', '-', '-', '포함'],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.bgMuted,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg - 1)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: SizedBox()),
                Expanded(child: Center(child: Text('라이트', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)))),
                Expanded(child: Center(child: Text('스탠다드', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)))),
                Expanded(child: Center(child: Text('프로', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFF9500))))),
              ],
            ),
          ),
          ..._rows.asMap().entries.map((e) {
            final i = e.key;
            final row = e.value;
            return Container(
              decoration: BoxDecoration(
                border: i < _rows.length - 1
                    ? const Border(bottom: BorderSide(color: AppColors.border, width: 0.5))
                    : null,
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Text(row[0], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                    ),
                  ),
                  ...List.generate(3, (col) {
                    final val = row[col + 1];
                    final isNone = val == '-';
                    return Expanded(
                      child: Center(
                        child: isNone
                            ? const Text('-', style: TextStyle(fontSize: 12, color: AppColors.textDisabled))
                            : Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
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
  const _Notice();
  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.6);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('유의사항', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          SizedBox(height: 6),
          Text('• 구독은 30일 단위로 자동 갱신됩니다.', style: style),
          Text('• 미사용 크레딧은 다음 달로 1개월 이월됩니다.', style: style),
          Text('• 구독 취소 시 만료일까지 혜택이 유지됩니다.', style: style),
          Text('• 결제는 구독 선택 즉시 이루어집니다.', style: style),
        ],
      ),
    );
  }
}

// ── 하단 CTA ─────────────────────────────────────────────
class _BottomCta extends StatelessWidget {
  final _Plan plan;
  final bool processing;
  final VoidCallback onPurchase;
  const _BottomCta({required this.plan, required this.processing, required this.onPurchase});

  @override
  Widget build(BuildContext context) {
    final color = _planColor(plan.key);
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: processing ? null : onPurchase,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.bgMuted,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: processing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(
                  '${plan.name} 구독 시작 (${NumberFormat('#,###').format(plan.price)}원/월)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
        ),
      ),
    );
  }

  Color _planColor(String key) {
    if (key == 'pro')      return const Color(0xFFFF9500);
    if (key == 'standard') return AppColors.primary;
    return const Color(0xFF6B7280);
  }
}
