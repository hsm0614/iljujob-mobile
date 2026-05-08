// lib/screens/payment/subscription_manage_screen.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/constants.dart';
import '../../data/services/ai_api.dart';

const _kProductId       = 'subscribe';
const _kAndroidPackage  = 'kr.co.iljujob';
const _brandBlue        = Color(0xFF3B8AFF);

class SubscriptionManageScreen extends StatefulWidget {
  const SubscriptionManageScreen({super.key});
  @override
  State<SubscriptionManageScreen> createState() => _SubscriptionManageScreenState();
}

class _SubscriptionManageScreenState extends State<SubscriptionManageScreen> {
  bool      _loading   = true;
  bool      _active    = false;
  String?   _plan;
  DateTime? _expiresAt;
  bool?     _isTrial;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 결제 화면에서 돌아온 뒤 지연 새로고침 (스토어/서버 전파 지연 대비)
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _refreshStatus();
    });
  }

  Future<void> _refreshStatus() async {
    setState(() => _loading = true);
    try {
      final api = AiApi(baseUrl);
      final s   = await api.fetchMySubscription();
      if (!mounted) return;
      setState(() {
        _active    = s.active;
        _plan      = s.plan;
        _expiresAt = s.expiresAt;
        _isTrial   = s.isTrial; // fetchMySubscription이 isTrial을 내려주는 경우
        _loading   = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('구독 상태를 불러오지 못했어요.');
    }
  }

  Future<void> _openStoreManage() async {
    final Uri url;
    if (Platform.isAndroid) {
      url = Uri.parse(
        'https://play.google.com/store/account/subscriptions'
        '?sku=$_kProductId&package=$_kAndroidPackage',
      );
    } else if (Platform.isIOS) {
      url = Uri.parse('itms-apps://apps.apple.com/account/subscriptions');
    } else {
      _toast('이 플랫폼에서는 구독 관리 페이지를 열 수 없어요.');
      return;
    }

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _toast('구독 관리 페이지를 열 수 없어요.');
    }
  }

  Future<void> _restore() async {
    try {
      await InAppPurchase.instance.restorePurchases();
      _toast('구매 복원을 요청했어요. 잠시 후 새로고침해 주세요.');
    } catch (e) {
      _toast('복원 실패: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 헬퍼
  // ─────────────────────────────────────────────
  String _remainText() {
    final ex = _expiresAt;
    if (ex == null) return '-';
    final diff = ex.difference(DateTime.now());
    if (diff.isNegative) return '만료됨';
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final m = diff.inMinutes % 60;
    if (d > 0) return '$d일 $h시간 남음';
    if (h > 0) return '$h시간 $m분 남음';
    return '$m분 남음';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final isDark  = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('구독 관리'),
        actions: [
          IconButton(onPressed: _refreshStatus, icon: const Icon(Icons.refresh)),
        ],
      ),
      backgroundColor: surface,
      body: RefreshIndicator(
        onRefresh: _refreshStatus,
        child: CustomScrollView(
          slivers: [
            // ── 상단 히어로 ─────────────────────
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _active
                        ? [_brandBlue, const Color(0xFF6FB3FF)]
                        : [Colors.grey.shade600, Colors.grey.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
                    child: _HeaderCard(
                      active:     _active,
                      plan:       _plan,
                      expiresAt:  _expiresAt,
                      remainText: _remainText(),
                      isTrial:    _isTrial,
                    ),
                  ),
                ),
              ),
            ),

            // ── 본문 ─────────────────────────────
            if (_loading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _SkeletonColumn(isDark: isDark),
                ),
              )
            else
              SliverList(
                delegate: SliverChildListDelegate.fixed([
                  // 플랫폼 메타
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _SubscriptionMeta(
                      platformLabel: Platform.isAndroid
                          ? 'Google Play'
                          : (Platform.isIOS ? 'App Store' : null),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 구독 관리 / 복원
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _ActionCard(
                      onOpenStore: _openStoreManage,
                      onRestore:   _restore,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 혜택
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _BenefitCard(),
                  ),

                  const SizedBox(height: 16),

                  // 정책/영수증
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _PolicyTile(),
                  ),

                  const SizedBox(height: 12),

                  // 문제 해결
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _TroubleshootTile(
                      onOpenStore: _openStoreManage,
                      onRestore:   _restore,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 미구독 CTA
                  if (!_active)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _brandBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () async {
                            final result =
                                await Navigator.pushNamed(context, '/subscribe');
                            if (!mounted) return;
                            if (result == true) {
                              await _refreshStatus();
                              _toast('구독이 활성화되었어요.');
                            }
                          },
                          icon: const Icon(Icons.workspace_premium),
                          label: const Text('구독하기',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 서브 위젯
// ─────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final bool      active;
  final String?   plan;
  final DateTime? expiresAt;
  final String    remainText;
  final bool?     isTrial;

  const _HeaderCard({
    required this.active,
    required this.plan,
    required this.expiresAt,
    required this.remainText,
    this.isTrial,
  });

  static String _fmt(DateTime? dt) {
    if (dt == null) return '-';
    final d = dt.toLocal();
    return '${d.year}.${_p(d.month)}.${_p(d.day)} ${_p(d.hour)}:${_p(d.minute)}';
  }
  static String _p(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:  Colors.white.withOpacity(.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.14)),
      ),
      padding: const EdgeInsets.all(16),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(active ? Icons.verified : Icons.hourglass_bottom,
                    color: Colors.white),
                const SizedBox(width: 8),
                Text(active ? '구독 활성' : '구독 없음',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                // 플랜 뱃지
                if (plan != null && plan!.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(plan!.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                // 트라이얼 뱃지
                if (isTrial == true) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('체험 중',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: Colors.orange)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _row('만료일',    _fmt(expiresAt)),
            _row('남은 기간', remainText),
            if (!active) ...[
              const SizedBox(height: 8),
              const Text('AI 맞춤 인재 보기는 구독자 전용 기능입니다.',
                  style: TextStyle(color: Colors.white70)),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
              width: 74,
              child: Text(k, style: const TextStyle(color: Colors.white70))),
          Expanded(
              child: Text(v,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final VoidCallback onOpenStore;
  final VoidCallback onRestore;
  const _ActionCard({required this.onOpenStore, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _row(Icons.manage_accounts, '구독 관리', '스토어로 이동',
                Icons.open_in_new, onOpenStore),
            const Divider(),
            _row(Icons.history, '구매 복원', '복원 실행',
                Icons.restore, onRestore),
          ],
        ),
      ),
    );
  }

  static Widget _row(IconData leadIcon, String title,
      String btnLabel, IconData btnIcon, VoidCallback onTap) {
    return Row(
      children: [
        Icon(leadIcon, color: _brandBlue),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const Spacer(),
        TextButton.icon(
          onPressed: onTap,
          icon: Icon(btnIcon, size: 18),
          label: Text(btnLabel),
        ),
      ],
    );
  }
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.workspace_premium, title: '구독 혜택'),
            SizedBox(height: 10),
            _BenefitRow(icon: Icons.flash_on,             text: '매달 유료 이용권 5개 지급'),
            SizedBox(height: 8),
            _BenefitRow(icon: Icons.chat_bubble_outline,  text: '지원 즉시 채팅 연결'),
            SizedBox(height: 8),
            _BenefitRow(icon: Icons.verified_user_outlined, text: 'AI 맞춤 인재 보기'),
          ],
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String   text;
  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle_outline, size: 18, color: _brandBlue),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    );
  }
}

class _PolicyTile extends StatelessWidget {
  const _PolicyTile();

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme.bodyMedium;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        leading: const Icon(Icons.description_outlined),
        title: const Text('해지·환불·영수증 안내',
            style: TextStyle(fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text('• 구독 해지는 스토어에서 직접 관리합니다(계정 귀속).', style: ts),
          const SizedBox(height: 6),
          Text('• 환불 규정은 각 스토어 정책을 따릅니다.', style: ts),
          const SizedBox(height: 6),
          Text('• 영수증/구매내역은 스토어 결제 내역에서 확인할 수 있습니다.', style: ts),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('구독 관리 열기'),
                onPressed: () {
                  final url = Platform.isAndroid
                      ? Uri.parse(
                          'https://play.google.com/store/account/subscriptions'
                          '?sku=$_kProductId&package=$_kAndroidPackage')
                      : Uri.parse(
                          'itms-apps://apps.apple.com/account/subscriptions');
                  launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.mail_outline, size: 18),
                label: const Text('문의하기'),
                onPressed: () {
                  // Uri 생성자가 자동 인코딩 — encodeQueryComponent 중복 적용 제거
                  final uri = Uri(
                    scheme: 'mailto',
                    path:   'support@iljujob.kr',
                    queryParameters: {
                      'subject': '[알바일주] 구독 문의',
                      'body':    '문의 내용을 적어주세요.',
                    },
                  );
                  launchUrl(uri);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TroubleshootTile extends StatelessWidget {
  final VoidCallback onOpenStore;
  final VoidCallback onRestore;
  const _TroubleshootTile({required this.onOpenStore, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme.bodyMedium;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        leading: const Icon(Icons.help_outline),
        title: const Text('문제 해결 가이드',
            style: TextStyle(fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text('• 구매했는데 활성화가 안 되면 "구매 복원"을 눌러주세요.', style: ts),
          const SizedBox(height: 6),
          Text('• 스토어 계정이 바뀐 경우, 스토어의 구독 관리에서 상태를 확인하세요.', style: ts),
          const SizedBox(height: 6),
          Text('• 네트워크 불안정 시 앱을 재실행 후 다시 시도하세요.', style: ts),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.restore),
                label: const Text('구매 복원'),
                onPressed: onRestore,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('구독 관리'),
                onPressed: onOpenStore,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubscriptionMeta extends StatelessWidget {
  final String? platformLabel;
  const _SubscriptionMeta({this.platformLabel});

  @override
  Widget build(BuildContext context) {
    if (platformLabel == null) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(Icons.store_mall_directory, size: 18, color: Theme.of(context).hintColor),
        const SizedBox(width: 6),
        Text(platformLabel!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SkeletonColumn extends StatelessWidget {
  final bool isDark;
  const _SkeletonColumn({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final base = isDark ? Colors.white12 : Colors.black12;
    Widget bar([double h = 16]) => Container(
          height: h,
          decoration:
              BoxDecoration(color: base, borderRadius: BorderRadius.circular(8)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar(64), const SizedBox(height: 12),
        bar(120), const SizedBox(height: 12),
        bar(160), const SizedBox(height: 12),
        bar(120),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String   title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _brandBlue),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}