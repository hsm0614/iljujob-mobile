// lib/screens/payment/subscription_manage_screen.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/constants.dart';
import '../../data/services/ai_api.dart';
import '../../data/services/authenticated_http_client.dart';
import '../widgets/albailju_common.dart';
import '../../config/app_theme.dart';
import '../../data/models/subscription_product_config.dart';

const _defaultBenefits = [
  _Benefit(Icons.flash_on_rounded, '즉시게시 3~10회/월', AppColors.primary),
  _Benefit(Icons.bolt_rounded, '긴급호출 0~2회/월', AppColors.urgentCall),
  _Benefit(
    Icons.auto_awesome_rounded,
    'AI 기능 무제한 (맞춤인재·인사이트·임금리포트)',
    AppColors.aiAccent,
  ),
  _Benefit(Icons.verified_rounded, '구독 배지 표시', AppColors.primary),
];

class _Benefit {
  final IconData icon;
  final String label;
  final Color color;
  const _Benefit(this.icon, this.label, this.color);
}

// ─── 플랜 레이블 ─────────────────────────────────────────────────
String _planLabel(String? plan) {
  switch (plan?.toLowerCase()) {
    case 'lite':
      return '라이트';
    case 'standard':
      return '스탠다드';
    case 'pro':
      return '프로';
    default:
      return plan?.toUpperCase() ?? '';
  }
}

// ─── 화면 ────────────────────────────────────────────────────────
class SubscriptionManageScreen extends StatefulWidget {
  const SubscriptionManageScreen({super.key});
  @override
  State<SubscriptionManageScreen> createState() =>
      _SubscriptionManageScreenState();
}

class _SubscriptionManageScreenState extends State<SubscriptionManageScreen> {
  bool _loading = true;
  bool _active = false;
  String? _plan;
  String? _entitlementVersion;
  DateTime? _expiresAt;
  bool? _isTrial;
  StreamSubscription<List<PurchaseDetails>>? _restoreSubscription;
  Timer? _restoreTimeout;
  final Set<String> _restoredPurchaseKeys = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _restoreTimeout?.cancel();
    _restoreSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final api = AiApi(baseUrl);
      final s = await api.fetchMySubscription();
      if (!mounted) return;
      setState(() {
        _active = s.active;
        _plan = s.plan;
        _entitlementVersion = s.entitlementVersion;
        _expiresAt = s.expiresAt;
        _isTrial = s.isTrial;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openStore() async {
    final Uri url;
    if (Platform.isAndroid) {
      _toast('Android 구독은 PortOne 30일 결제이며 자동 갱신되지 않아요.');
      return;
    } else if (Platform.isIOS) {
      url = Uri.parse('itms-apps://apps.apple.com/account/subscriptions');
    } else {
      _toast('이 플랫폼에서는 지원하지 않아요.');
      return;
    }
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _toast('스토어를 열 수 없어요.');
    }
  }

  Future<void> _restore() async {
    if (Platform.isAndroid) {
      await _refresh();
      _toast('PortOne 결제 내역을 서버에서 다시 확인했어요.');
      return;
    }
    try {
      await _restoreSubscription?.cancel();
      _restoreTimeout?.cancel();
      _restoredPurchaseKeys.clear();
      _restoreSubscription = InAppPurchase.instance.purchaseStream.listen(
        _handleRestoredPurchases,
        onError: (_) => _toast('복원 결과를 확인하지 못했어요.'),
      );
      _restoreTimeout = Timer(const Duration(seconds: 30), () {
        _restoreSubscription?.cancel();
        _restoreSubscription = null;
      });
      await InAppPurchase.instance.restorePurchases();
      _toast('복원을 요청했어요. 스토어 결과를 확인할게요.');
    } catch (e) {
      _toast('복원 실패: $e');
    }
  }

  Future<void> _handleRestoredPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status != PurchaseStatus.restored &&
          purchase.status != PurchaseStatus.purchased) {
        continue;
      }
      if (!isSubscriptionProductId(purchase.productID)) continue;
      // 안드로이드는 포트원 결제라 스토어 구매가 올라올 일이 없다.
      // 혹시 올라와도 서버가 google_play 를 받지 않으므로 여기서 끊는다.
      if (!Platform.isIOS) continue;
      final key =
          purchase.purchaseID ??
          '${purchase.productID}-${purchase.transactionDate ?? ''}';
      if (!_restoredPurchaseKeys.add(key)) continue;

      final token = purchase.verificationData.serverVerificationData;
      if (token.isEmpty) {
        _restoredPurchaseKeys.remove(key);
        continue;
      }
      try {
        final response = await AuthenticatedHttpClient.postJson(
          Uri.parse('$baseUrl/api/iap/verify'),
          body: {
            'platform': 'app_store',
            'productId': purchase.productID,
            'purchaseId': purchase.purchaseID,
            'token': token,
            'isReactivation': true,
          },
        );
        if (response.statusCode != 200) {
          _restoredPurchaseKeys.remove(key);
          if (mounted) _toast('구독 복원 검증에 실패했어요.');
          continue;
        }
        if (purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
        }
        if (mounted) {
          await _refresh();
          _toast('구독 권리를 복원했어요.');
        }
        _restoreTimeout?.cancel();
        await _restoreSubscription?.cancel();
        _restoreSubscription = null;
      } catch (_) {
        _restoredPurchaseKeys.remove(key);
        if (mounted) _toast('서버 연결 오류로 복원을 확인하지 못했어요.');
      }
    }
  }

  String _remainText() {
    final ex = _expiresAt;
    if (ex == null) return '-';
    final diff = ex.difference(DateTime.now());
    if (diff.isNegative) return '만료됨';
    final d = diff.inDays;
    final h = diff.inHours % 24;
    if (d > 0) return 'D-$d';
    if (h > 0) return '$h시간 남음';
    return '${diff.inMinutes % 60}분 남음';
  }

  String _expiresText() {
    final ex = _expiresAt;
    if (ex == null) return '-';
    final d = ex.toLocal();
    return '${d.year}.${_p(d.month)}.${_p(d.day)}';
  }

  static String _p(int n) => n.toString().padLeft(2, '0');

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AlbailjuAppBar(
        title: '구독 관리',
        brand: true,
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body:
          _loading
              ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
              : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  children: [
                    // ── 상태 카드
                    _StatusCard(
                      active: _active,
                      plan: _plan,
                      entitlementVersion: _entitlementVersion,
                      isTrial: _isTrial,
                      expiresText: _expiresText(),
                      remainText: _remainText(),
                    ),

                    const SizedBox(height: 16),

                    // ── 혜택
                    _BenefitSection(
                      plan: _plan,
                      entitlementVersion: _entitlementVersion,
                      active: _active,
                    ),

                    const SizedBox(height: 16),

                    // ── 구독 관리 / 복원
                    _ManageSection(
                      isStoreBilling: Platform.isIOS,
                      onOpenStore: _openStore,
                      onRestore: _restore,
                    ),

                    const SizedBox(height: 16),

                    // ── 정책
                    _PolicySection(
                      isStoreBilling: Platform.isIOS,
                      onOpenStore: _openStore,
                    ),

                    const SizedBox(height: 24),

                    // ── 미구독 CTA
                    if (!_active)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () async {
                            final result = await Navigator.pushNamed(
                              context,
                              '/subscribe',
                            );
                            if (!mounted) return;
                            if (result == true) {
                              await _refresh();
                              _toast('구독이 활성화되었어요!');
                            }
                          },
                          icon: const Icon(Icons.workspace_premium_rounded),
                          label: const Text(
                            '구독 시작하기',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
    );
  }
}

// ─── 상태 카드 ───────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final bool active;
  final String? plan;
  final String? entitlementVersion;
  final bool? isTrial;
  final String expiresText;
  final String remainText;

  const _StatusCard({
    required this.active,
    required this.plan,
    required this.entitlementVersion,
    required this.isTrial,
    required this.expiresText,
    required this.remainText,
  });

  @override
  Widget build(BuildContext context) {
    final label = _planLabel(plan);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              active
                  ? [AppColors.primary, const Color(0xFF1A6FFF)]
                  : [AppColors.textTertiary, AppColors.textSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (active ? AppColors.primary : AppColors.textTertiary)
                .withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active
                    ? Icons.verified_rounded
                    : Icons.workspace_premium_outlined,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                active ? '구독 활성' : '구독 없음',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (active && label.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (active && entitlementVersion == 'legacy_v1') ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '기존 권리 유지',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (isTrial == true) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '체험 중',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (active) ...[
            _infoRow('만료일', expiresText),
            const SizedBox(height: 6),
            _infoRow('남은 기간', remainText),
          ] else
            const Text(
              '구독하면 즉시게시·AI 기능을 자유롭게 사용할 수 있어요.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }

  static Widget _infoRow(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            k,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        Text(
          v,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

// ─── 혜택 섹션 ───────────────────────────────────────────────────
class _BenefitSection extends StatelessWidget {
  final String? plan;
  final String? entitlementVersion;
  final bool active;
  const _BenefitSection({
    required this.plan,
    required this.entitlementVersion,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final labels =
        active
            ? subscriptionBenefitLabels(plan?.toLowerCase(), entitlementVersion)
            : const <String>[];
    final benefits =
        labels.isEmpty
            ? _defaultBenefits
            : labels
                .map((label) {
                  if (label.startsWith('즉시게시')) {
                    return _Benefit(
                      Icons.flash_on_rounded,
                      label,
                      AppColors.primary,
                    );
                  }
                  if (label.startsWith('긴급호출')) {
                    return _Benefit(
                      Icons.bolt_rounded,
                      label,
                      AppColors.urgentCall,
                    );
                  }
                  if (label.startsWith('AI')) {
                    return _Benefit(
                      Icons.auto_awesome_rounded,
                      label,
                      AppColors.aiAccent,
                    );
                  }
                  if (label.startsWith('우선')) {
                    return _Benefit(
                      Icons.headset_mic_rounded,
                      label,
                      AppColors.pending,
                    );
                  }
                  return _Benefit(
                    Icons.verified_rounded,
                    label,
                    AppColors.primary,
                  );
                })
                .toList(growable: false);
    final label = _planLabel(plan);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                active && label.isNotEmpty ? '$label 플랜 혜택' : '구독 혜택',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...benefits.map((b) => _BenefitRow(benefit: b)),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final _Benefit benefit;
  const _BenefitRow({required this.benefit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: benefit.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(benefit.icon, color: benefit.color, size: 17),
          ),
          const SizedBox(width: 12),
          Text(
            benefit.label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          const Icon(Icons.check_rounded, size: 16, color: AppColors.success),
        ],
      ),
    );
  }
}

// ─── 관리 버튼 섹션 ──────────────────────────────────────────────
class _ManageSection extends StatelessWidget {
  final bool isStoreBilling;
  final VoidCallback onOpenStore;
  final VoidCallback onRestore;
  const _ManageSection({
    required this.isStoreBilling,
    required this.onOpenStore,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _tile(
            icon: Icons.manage_accounts_rounded,
            title: isStoreBilling ? '구독 관리' : '결제 방식 안내',
            subtitle:
                isStoreBilling ? 'App Store에서 변경 · 해지' : 'PortOne 30일 결제 · 자동 갱신 없음',
            onTap: onOpenStore,
            showDivider: true,
          ),
          _tile(
            icon: Icons.history_rounded,
            title: isStoreBilling ? '구매 복원' : '결제 상태 새로고침',
            subtitle: isStoreBilling ? '이전 결제 내역 복원' : '서버의 이용 기간 다시 확인',
            onTap: onRestore,
            showDivider: false,
          ),
        ],
      ),
    );
  }

  static Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool showDivider,
  }) {
    return Column(
      children: [
        ListTile(
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
          ),
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 64, color: AppColors.bgPage),
      ],
    );
  }
}

// ─── 정책 섹션 ───────────────────────────────────────────────────
class _PolicySection extends StatelessWidget {
  final bool isStoreBilling;
  final VoidCallback onOpenStore;
  const _PolicySection({required this.isStoreBilling, required this.onOpenStore});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.bgPage,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ),
          title: const Text(
            '해지 · 환불 · 문의',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              isStoreBilling
                  ? '• 구독 해지는 App Store 구독 관리 페이지에서 처리됩니다.\n'
                      '• 환불 규정은 Apple App Store 정책을 따릅니다.\n'
                      '• 결제 영수증은 App Store 구매 내역에서 확인하세요.'
                  : '• Android 구독은 PortOne을 통한 30일 이용권 결제입니다.\n'
                      '• 자동 갱신되지 않으며 기간이 끝난 뒤 다시 결제할 수 있습니다.\n'
                      '• 환불과 결제 영수증은 고객센터로 문의해주세요.',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(isStoreBilling ? '구독 관리 열기' : '결제 방식 확인'),
                  onPressed: onOpenStore,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.mail_outline_rounded, size: 16),
                  label: const Text('문의하기'),
                  onPressed: () {
                    final uri = Uri(
                      scheme: 'mailto',
                      path: 'support@albailju.co.kr',
                      queryParameters: {
                        'subject': '[알바일주] 구독 문의',
                        'body': '문의 내용을 입력해주세요.',
                      },
                    );
                    launchUrl(uri);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.textDisabled),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
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
  }
}
