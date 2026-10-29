// lib/screens/payment/subscription_manage_screen.dart
import 'dart:async';
import 'package:iljujob/widget/app_ui.dart';
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

// ─── 플랜 레이블 ─────────────────────────────────────────────────
String _planLabel(String? plan) {
  switch (plan?.toLowerCase()) {
    case 'lite':
      return '베이직';
    case 'standard':
      return '스탠다드';
    case 'pro':
      return '무제한';
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
  int? _instantRemaining;
  int? _directRemaining;
  int? _pushRemaining;
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
        _instantRemaining = s.instantRemaining;
        _directRemaining = s.directMonthlyRemaining;
        _pushRemaining = s.pushMonthlyRemaining;
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

  // 파란/회색 통 상자(흰 글자)·색색 아이콘 상자 혜택·파란 아이콘 상자 메뉴 → 마이와 같은 흰 블록 문법
  @override
  Widget build(BuildContext context) {
    final label = _planLabel(_plan);
    final remaining = _entitlementVersion == 'v3'
        ? <(String, String)>[
            ('즉시 게시', _instantRemaining == -1 ? '무제한' : '${_instantRemaining ?? 0}회 남음'),
            ('먼저 연락', '${_directRemaining ?? 0}명 남음'),
            ('지도 알림', '${_pushRemaining ?? 0}회 남음'),
          ]
        : const <(String, String)>[];
    final benefits = _active
        ? subscriptionBenefitLabels(_plan?.toLowerCase(), _entitlementVersion)
        : const <String>[];
    final title = !_active
        ? '구독하지 않았어요'
        : label.isEmpty
        ? '구독 중'
        : '$label 구독 중';

    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(child: Text(k, style: AppTextStyles.body2)),
          Text(
            v,
            style: AppTextStyles.body2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AlbailjuAppBar(
        title: '구독 관리',
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
              ? const AppSkeletonList(rows: 4)
              : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Container(
                      color: AppColors.bgCard,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: Text(title, style: AppTextStyles.h2)),
                              if (_isTrial == true) ...[
                                const SizedBox(width: 6),
                                const JobSignalBadge(label: '체험 중'),
                              ],
                              if (_active && _entitlementVersion == 'legacy_v1') ...[
                                const SizedBox(width: 6),
                                const JobSignalBadge(label: '기존 혜택 유지'),
                              ],
                            ],
                          ),
                          if (_active) ...[
                            row('만료일', _expiresText()),
                            row('남은 기간', _remainText()),
                          ] else ...[
                            const SizedBox(height: 4),
                            const Text(
                              '구독하면 즉시 게시와 먼저 연락하기를 매달 쓸 수 있어요',
                              style: AppTextStyles.body2,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (remaining.isNotEmpty || benefits.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        color: AppColors.bgCard,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              remaining.isNotEmpty ? '이번 기간 남은 혜택' : '혜택',
                              style: AppTextStyles.h3,
                            ),
                            for (final (k, v) in remaining) row(k, v),
                            if (remaining.isEmpty)
                              for (final b in benefits)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          b,
                                          style: AppTextStyles.body2.copyWith(
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    AppMenuSection(
                      children: [
                        if (_active || !Platform.isIOS)
                        AppMenuRow(
                          label: Platform.isIOS ? '구독 변경·해지' : '결제 방식 안내',
                          subtitle:
                              Platform.isIOS
                                  ? 'App Store에서 바꾸거나 해지해요'
                                  : '30일 이용 · 자동으로 다시 결제되지 않아요',
                          onTap: _openStore,
                        ),
                        AppMenuRow(
                          label: Platform.isIOS ? '구매 복원' : '결제 상태 다시 확인',
                          onTap: _restore,
                        ),
                        AppMenuRow(
                          label: '구독 문의',
                          subtitle: 'support@albailju.co.kr',
                          onTap:
                              () => launchUrl(
                                Uri(
                                  scheme: 'mailto',
                                  path: 'support@albailju.co.kr',
                                  queryParameters: {
                                    'subject': '[알바일주] 구독 문의',
                                    'body': '문의 내용을 입력해주세요.',
                                  },
                                ),
                              ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Text(
                        Platform.isIOS
                            ? '해지는 App Store 구독 관리에서 하고, 해지해도 기간 끝까지 쓸 수 있어요. 환불은 Apple 정책을 따라요.'
                            : '기간이 끝나면 다시 결제해서 이어 쓸 수 있어요. 환불과 영수증은 고객센터로 문의해 주세요.',
                        style: AppTextStyles.caption,
                      ),
                    ),
                  ],
                ),
              ),
      bottomNavigationBar:
          !_loading && !_active
              ? AppBottomBar(
                child: AppPrimaryButton(
                  label: '구독 플랜 보기',
                  onPressed: () async {
                    final result = await Navigator.pushNamed(context, '/subscribe');
                    if (!mounted) return;
                    if (result == true) {
                      await _refresh();
                      _toast('구독을 시작했어요');
                    }
                  },
                ),
              )
              : null,
    );
  }
}
