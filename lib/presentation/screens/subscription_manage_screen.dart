// lib/screens/payment/subscription_manage_screen.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/constants.dart';
import '../../data/services/ai_api.dart';
import '../widgets/albailju_common.dart';

const _kProductId = 'subscribe';
const _kAndroidPackage = 'kr.co.iljujob';

// ─── 플랜별 혜택 정의 ────────────────────────────────────────────
const _planBenefits = {
  'lite': [
    _Benefit(Icons.flash_on_rounded, '즉시게시 3회/월', Color(0xFF3B8AFF)),
    _Benefit(Icons.auto_awesome_rounded, 'AI 기능 무제한 (맞춤인재·인사이트·임금리포트)', Color(0xFF6C5CE7)),
    _Benefit(Icons.verified_rounded, '구독 배지 표시', Color(0xFF3B8AFF)),
  ],
  'standard': [
    _Benefit(Icons.flash_on_rounded, '즉시게시 무제한', Color(0xFF3B8AFF)),
    _Benefit(Icons.auto_awesome_rounded, 'AI 기능 무제한 (맞춤인재·인사이트·임금리포트)', Color(0xFF6C5CE7)),
    _Benefit(Icons.verified_user_rounded, '출근 안심 포함', Color(0xFF10B981)),
    _Benefit(Icons.verified_rounded, '구독 배지 표시', Color(0xFF3B8AFF)),
  ],
  'pro': [
    _Benefit(Icons.flash_on_rounded, '즉시게시 무제한', Color(0xFF3B8AFF)),
    _Benefit(Icons.bolt_rounded, '긴급호출 무제한 (반경 5km, 10명)', Color(0xFFEF4444)),
    _Benefit(Icons.auto_awesome_rounded, 'AI 기능 무제한 (맞춤인재·인사이트·임금리포트)', Color(0xFF6C5CE7)),
    _Benefit(Icons.verified_user_rounded, '출근 안심 포함', Color(0xFF10B981)),
    _Benefit(Icons.headset_mic_rounded, '우선 CS 지원', Color(0xFFFFB300)),
    _Benefit(Icons.verified_rounded, '구독 배지 표시', Color(0xFF3B8AFF)),
  ],
};

const _defaultBenefits = [
  _Benefit(Icons.flash_on_rounded, '즉시게시 이용권 (라이트 3회 / 스탠다드·프로 무제한)', Color(0xFF3B8AFF)),
  _Benefit(Icons.bolt_rounded, '긴급호출 무제한 (프로 전용)', Color(0xFFEF4444)),
  _Benefit(Icons.auto_awesome_rounded, 'AI 기능 무제한 (맞춤인재·인사이트·임금리포트)', Color(0xFF6C5CE7)),
  _Benefit(Icons.verified_rounded, '구독 배지 표시', Color(0xFF3B8AFF)),
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
  DateTime? _expiresAt;
  bool? _isTrial;

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

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final api = AiApi(baseUrl);
      final s = await api.fetchMySubscription();
      if (!mounted) return;
      setState(() {
        _active = s.active;
        _plan = s.plan;
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
      url = Uri.parse(
        'https://play.google.com/store/account/subscriptions'
        '?sku=$_kProductId&package=$_kAndroidPackage',
      );
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
    try {
      await InAppPurchase.instance.restorePurchases();
      _toast('복원을 요청했어요. 잠시 후 새로고침해 주세요.');
    } catch (e) {
      _toast('복원 실패: $e');
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
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AlbailjuAppBar(
        title: '구독 관리',
        brand: true,
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body:
          _loading
              ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF3B8AFF)),
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
                      isTrial: _isTrial,
                      expiresText: _expiresText(),
                      remainText: _remainText(),
                    ),

                    const SizedBox(height: 16),

                    // ── 혜택
                    _BenefitSection(plan: _plan, active: _active),

                    const SizedBox(height: 16),

                    // ── 구독 관리 / 복원
                    _ManageSection(
                      onOpenStore: _openStore,
                      onRestore: _restore,
                    ),

                    const SizedBox(height: 16),

                    // ── 정책
                    _PolicySection(onOpenStore: _openStore),

                    const SizedBox(height: 24),

                    // ── 미구독 CTA
                    if (!_active)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF3B8AFF),
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
  final bool? isTrial;
  final String expiresText;
  final String remainText;

  const _StatusCard({
    required this.active,
    required this.plan,
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
                  ? [const Color(0xFF3B8AFF), const Color(0xFF1A6FFF)]
                  : [const Color(0xFF9CA3AF), const Color(0xFF6B7280)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (active ? const Color(0xFF3B8AFF) : const Color(0xFF9CA3AF))
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
  final bool active;
  const _BenefitSection({required this.plan, required this.active});

  @override
  Widget build(BuildContext context) {
    final benefits = _planBenefits[plan?.toLowerCase()] ?? _defaultBenefits;
    final label = _planLabel(plan);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E8EB)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFF3B8AFF),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                active && label.isNotEmpty ? '$label 플랜 혜택' : '구독 혜택',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF191F28),
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
              color: Color(0xFF374151),
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          const Icon(Icons.check_rounded, size: 16, color: Color(0xFF10B981)),
        ],
      ),
    );
  }
}

// ─── 관리 버튼 섹션 ──────────────────────────────────────────────
class _ManageSection extends StatelessWidget {
  final VoidCallback onOpenStore;
  final VoidCallback onRestore;
  const _ManageSection({required this.onOpenStore, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E8EB)),
      ),
      child: Column(
        children: [
          _tile(
            icon: Icons.manage_accounts_rounded,
            title: '구독 관리',
            subtitle: '스토어에서 변경 · 해지',
            onTap: onOpenStore,
            showDivider: true,
          ),
          _tile(
            icon: Icons.history_rounded,
            title: '구매 복원',
            subtitle: '이전 결제 내역 복원',
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
            child: Icon(icon, color: const Color(0xFF3B8AFF), size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF9CA3AF),
          ),
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 64, color: Color(0xFFF4F6FA)),
      ],
    );
  }
}

// ─── 정책 섹션 ───────────────────────────────────────────────────
class _PolicySection extends StatelessWidget {
  final VoidCallback onOpenStore;
  const _PolicySection({required this.onOpenStore});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E8EB)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6FA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: Color(0xFF6B7280),
              size: 20,
            ),
          ),
          title: const Text(
            '해지 · 환불 · 문의',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Text(
              '• 구독 해지는 각 스토어 구독 관리 페이지에서 직접 처리됩니다.\n'
              '• 환불 규정은 Apple App Store / Google Play 정책을 따릅니다.\n'
              '• 결제 영수증은 스토어 구매 내역에서 확인하세요.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
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
                  label: const Text('구독 관리 열기'),
                  onPressed: onOpenStore,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3B8AFF),
                    side: const BorderSide(color: Color(0xFF3B8AFF)),
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
                    foregroundColor: const Color(0xFF6B7280),
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
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
