import 'dart:async'; // TimeoutException
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../config/constants.dart'; // baseUrl
import '../../../data/services/ai_api.dart'; // fetchMySubscription()
import '../../../data/services/authenticated_http_client.dart';
import '../../../data/services/screen_analytics_service.dart';
import '../../../config/app_theme.dart';
import '../../../config/messages.dart';
import '../../../widget/dev_account_switch.dart';
import '../../../widget/app_ui.dart';
import '../../../widget/app_motion.dart';
import '../worker_screen/labor_consult_screen.dart';

class ClientMyPageScreen extends StatefulWidget {
  const ClientMyPageScreen({super.key});
  @override
  State<ClientMyPageScreen> createState() => _ClientMyPageScreenState();
}

class _ClientMyPageScreenState extends State<ClientMyPageScreen> {
  // ===== Profile State =====
  String companyName = '회사명';
  String managerName = '담당자명';
  String phoneNumber = '전화번호';
  String logoUrl = '';

  // ===== Subscription =====
  bool _subLoading = true;
  SubscriptionStatus? _sub;

  // ===== 이용권 (/api/pass/remain — 즉시게시 -1 = 프로 무제한) =====
  bool _passLoading = true;
  int _instant = 0;
  int _instant7 = 0;
  int _urgent = 0;

  // Helpers
  String _getFullImageUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$baseUrl$path';
  }

  String _formatPhone(String phone) {
    final p = phone.replaceAll(RegExp(r'\D'), '');
    if (p.length == 11) {
      return '${p.substring(0, 3)}-${p.substring(3, 7)}-${p.substring(7)}';
    }
    if (p.length == 10) {
      return '${p.substring(0, 3)}-${p.substring(3, 6)}-${p.substring(6)}';
    }
    return phone;
  }

  Future<String> _phoneRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = (prefs.getString('userPhone') ?? '').replaceAll(
      RegExp(r'\D'),
      '',
    );
    return raw;
  }

  Future<int?> _clientId() async {
    final prefs = await SharedPreferences.getInstance();
    // 기업 로그인 구조상 clientId가 있을 확률이 높음
    return prefs.getInt('clientId') ?? prefs.getInt('userId');
  }

  @override
  void initState() {
    super.initState();
    ScreenAnalyticsService.instance.logScreenView('client_my_page');
    _loadProfileInfo();
    _loadSubscription();
    _loadPasses();
  }

  Future<void> _loadPasses() async {
    try {
      final res = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/pass/remain'),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        _instant = int.tryParse('${d['instant'] ?? d['remaining'] ?? 0}') ?? 0;
        _instant7 = int.tryParse('${d['instant7'] ?? 0}') ?? 0;
        _urgent = int.tryParse('${d['urgent'] ?? 0}') ?? 0;
      }
    } catch (_) {}
    if (mounted) setState(() => _passLoading = false);
  }

  Future<void> _loadSubscription() async {
    try {
      final api = AiApi(baseUrl);
      final s = await api.fetchMySubscription();
      if (!mounted) return;
      setState(() {
        _sub = s;
        _subLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _subLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadProfileInfo(), _loadSubscription(), _loadPasses()]);
  }

  /// '스탠다드 구독 중 · 12일 남음' / null(구독 안 함)
  String? _subLine() {
    if (!(_sub?.active ?? false)) return null;
    const names = {'lite': '베이직', 'standard': '스탠다드', 'pro': '무제한'};
    final raw = (_sub!.plan ?? '').toLowerCase();
    final name = names.entries
        .firstWhere((e) => raw.contains(e.key), orElse: () => const MapEntry('', '구독'))
        .value;
    final d = _sub!.expiresAt;
    final left = d == null ? '' : ' · ${d.difference(DateTime.now()).inDays}일 남음';
    return '$name 구독 중$left';
  }

  Future<void> _loadProfileInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final cachedCompany = prefs.getString('companyName') ?? '';
    final cachedManager = prefs.getString('userName') ?? '';
    final cachedPhone = prefs.getString('userPhone') ?? '';
    final cachedLogo = prefs.getString('logoUrl') ?? '';

    setState(() {
      companyName = cachedCompany.isNotEmpty ? cachedCompany : '회사명';
      managerName = cachedManager.isNotEmpty ? cachedManager : '담당자명';
      phoneNumber = cachedPhone.isNotEmpty ? cachedPhone : '전화번호';
      logoUrl = cachedLogo;
    });

    final clientId = prefs.getInt('clientId') ?? prefs.getInt('userId');
    if (clientId == null) return;

    try {
      final uri = Uri.parse(
        '$baseUrl/api/client/profile',
      ).replace(queryParameters: {'id': '$clientId'});
      final res = await AuthenticatedHttpClient.get(
        uri,
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return;
      final raw = jsonDecode(res.body);
      final data =
          raw is Map<String, dynamic>
              ? ((raw['data'] is Map<String, dynamic>)
                  ? raw['data'] as Map<String, dynamic>
                  : raw)
              : <String, dynamic>{};

      final freshCompany = data['company_name']?.toString().trim() ?? '';
      final freshManager = data['manager_name']?.toString().trim() ?? '';
      final freshPhone = data['phone']?.toString().trim() ?? '';
      final freshLogo = data['logo_url']?.toString().trim() ?? '';

      if (freshCompany.isNotEmpty) {
        await prefs.setString('companyName', freshCompany);
      }
      if (freshManager.isNotEmpty) {
        await prefs.setString('userName', freshManager);
      }
      if (freshPhone.isNotEmpty) {
        await prefs.setString('userPhone', freshPhone);
      }
      if (freshLogo.isNotEmpty) {
        await prefs.setString('logoUrl', freshLogo);
      }

      if (!mounted) return;
      setState(() {
        companyName =
            freshCompany.isNotEmpty
                ? freshCompany
                : freshManager.isNotEmpty
                ? freshManager
                : companyName;
        managerName = freshManager.isNotEmpty ? freshManager : managerName;
        phoneNumber = freshPhone.isNotEmpty ? freshPhone : phoneNumber;
        logoUrl = freshLogo.isNotEmpty ? freshLogo : logoUrl;
      });
    } catch (e) {
      debugPrint('client my profile sync error: $e');
    }
  }

  // =========================
  // Logout / Withdraw
  // =========================

  Future<void> _confirmLogout() async {
    final ok = await showAppSheet(
      context,
      title: '로그아웃할까요?',
      message: '다시 로그인하면 이어서 쓸 수 있어요.',
      confirmLabel: '로그아웃',
      cancelLabel: '취소',
    );
    if (!ok) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamedAndRemoveUntil('/onboarding', (route) => false);
  }

  Future<void> _confirmWithdraw() async {
    final ok = await showAppSheet(
      context,
      title: '정말 탈퇴할까요?',
      message: '남은 이용권이 사라지고 계정을 되돌릴 수 없어요.',
      confirmLabel: '탈퇴하기',
      cancelLabel: '취소',
      destructive: true,
    );
    if (!ok) return;
    await _withdrawAccount();
  }

  Future<http.Response> _deleteWithJsonBody(
    Uri uri,
    Map<String, dynamic> body,
    Map<String, String> headers,
  ) async {
    final req = http.Request('DELETE', uri);
    req.headers.addAll(headers);
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode(body);

    final streamed = await req.send().timeout(const Duration(seconds: 8));
    return http.Response.fromStream(streamed);
  }

  Future<void> _withdrawAccount() async {
    final uid = await _clientId(); // 만약 기업이 clientId면 여기도 clientId로 바꾸는 게 더 안전
    final phone = await _phoneRaw();

    if (uid == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유저 정보(아이디/전화번호)가 없어서 탈퇴를 진행할 수 없어요.')),
      );
      return;
    }

    final headers = await AuthenticatedHttpClient.authJsonHeaders();

    // 서버가 query로 phone을 요구하는 경우 대응
    final uriQuery = Uri.parse(
      '$baseUrl/api/client/profile?id=$uid&phone=$phone',
    );

    // 서버가 body로 phone을 요구하는 경우 대응
    final uriBody = Uri.parse('$baseUrl/api/client/profile');

    try {
      // 1) query 방식 먼저
      var res = await AuthenticatedHttpClient.delete(
        uriQuery,
      ).timeout(const Duration(seconds: 8));

      // 2) 안 되면 body 방식
      if (res.statusCode < 200 || res.statusCode >= 300) {
        res = await _deleteWithJsonBody(uriBody, {
          'id': uid,
          'phone': phone,
        }, headers);
      }

      final ok = res.statusCode >= 200 && res.statusCode < 300; // 200/204 모두 성공
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(Msg.withdrawFailed)),
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!mounted) return;
      Navigator.of(
        context,
        rootNavigator: true,
      ).pushNamedAndRemoveUntil('/onboarding', (route) => false);
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('서버 응답이 늦어요. 잠시 후 다시 시도해줘')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('탈퇴 중 오류가 발생했어')));
    }
  }

  // 2026-10 리디자인: 알바생 마이와 같은 뼈대 (화면 폭 흰 블록 + 회색 아이콘 줄, 토스·당근 마이).
  // 알바생의 '이번 달 일한 금액' 자리에 사장님은 '남은 이용권' — 공고 올릴 때 가장 먼저 궁금한 것.
  @override
  Widget build(BuildContext context) {
    final contact = [
      if (managerName != '담당자명') managerName,
      if (phoneNumber != '전화번호') _formatPhone(phoneNumber),
    ].join(' · ');
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverAppBar(
              pinned: true,
              automaticallyImplyLeading: false,
              backgroundColor: AppColors.bgCard,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 52,
              titleSpacing: 20,
              title: Text('마이', style: AppTextStyles.tabTitle),
            ),
            SliverList.list(
              children: [
                Container(
                  color: AppColors.bgCard,
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    children: [
                      AppProfileHeader(
                        imageUrl: _getFullImageUrl(logoUrl),
                        title: companyName,
                        subtitle: contact.isEmpty ? '프로필을 채워 주세요' : contact,
                        fallbackIcon: Icons.storefront_rounded,
                        loading: false,
                        onTap: () async {
                          await Navigator.pushNamed(context, '/edit_profile');
                          if (mounted) _loadProfileInfo();
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _PassBox(
                          loading: _passLoading,
                          instant: _instant,
                          instant7: _instant7,
                          urgent: _urgent,
                          subLine: _subLoading ? null : _subLine(),
                          onTap: () async {
                            await Navigator.pushNamed(context, '/purchase-pass');
                            if (mounted) _refreshAll();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                AppMenuSection(
                  title: '이용권·구독',
                  children: [
                    AppMenuRow(
                      icon: Icons.confirmation_number_outlined,
                      label: '이용권 구매',
                      onTap: () async {
                        await Navigator.pushNamed(context, '/purchase-pass');
                        if (mounted) _refreshAll();
                      },
                    ),
                    AppMenuRow(
                      icon: Icons.workspace_premium_outlined,
                      label: (_sub?.active ?? false) ? '구독 관리' : '구독하기',
                      subtitle:
                          (_sub?.active ?? false) ? null : '매달 이용권을 더 싸게 받아요',
                      onTap: () async {
                        await Navigator.pushNamed(
                          context,
                          (_sub?.active ?? false)
                              ? '/subscription/manage'
                              : '/subscribe',
                        );
                        if (mounted) _refreshAll();
                      },
                    ),
                    AppMenuRow(
                      icon: Icons.notifications_none_rounded,
                      label: '알림 설정',
                      onTap:
                          () => Navigator.pushNamed(context, '/notifications'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AppMenuSection(
                  title: '도움',
                  children: [
                    AppMenuRow(
                      icon: Icons.balance_rounded,
                      label: 'AI 노무 상담',
                      subtitle: '최저임금·주휴수당·근로계약이 궁금할 때',
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const LaborConsultScreen()),
                          ),
                    ),
                    AppMenuRow(
                      icon: Icons.headset_mic_outlined,
                      label: '고객센터',
                      onTap: () => Navigator.pushNamed(context, '/support'),
                    ),
                    AppMenuRow(
                      icon: Icons.campaign_outlined,
                      label: '공지사항',
                      onTap: () => Navigator.pushNamed(context, '/notices'),
                    ),
                    AppMenuRow(
                      icon: Icons.card_giftcard_rounded,
                      label: '이벤트',
                      onTap: () => Navigator.pushNamed(context, '/events'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AppMenuSection(
                  title: '안전',
                  children: [
                    AppMenuRow(
                      icon: Icons.flag_outlined,
                      label: '신고 내역',
                      onTap:
                          () => Navigator.pushNamed(context, '/report-history'),
                    ),
                    AppMenuRow(
                      icon: Icons.block_rounded,
                      label: '차단한 사용자',
                      onTap:
                          () => Navigator.pushNamed(context, '/blocked-users'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AppMenuSection(
                  children: [
                    AppMenuRow(
                      label: '약관 및 정책',
                      onTap: () => Navigator.pushNamed(context, '/terms-list'),
                    ),
                    const AppBizInfoRow(),
                  ],
                ),
                const DevAccountSwitchButton(),
                // 계정 행동은 맨 아래 작은 글자로 (알바생 마이와 같음)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _confirmLogout,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          textStyle: AppTextStyles.body2,
                        ),
                        child: const Text('로그아웃'),
                      ),
                      const Text('|', style: AppTextStyles.caption),
                      TextButton(
                        onPressed: _confirmWithdraw,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textTertiary,
                          textStyle: AppTextStyles.body2,
                        ),
                        child: const Text('회원 탈퇴'),
                      ),
                    ],
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

/// 남은 이용권 — 숫자 두 개가 이 화면의 포인트. 누르면 이용권 구매.
class _PassBox extends StatelessWidget {
  final bool loading;
  final int instant; // -1 = 무제한(프로)
  final int instant7;
  final int urgent;
  final String? subLine;
  final VoidCallback onTap;
  const _PassBox({
    required this.loading,
    required this.instant,
    required this.instant7,
    required this.urgent,
    required this.subLine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int n) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.body2),
          const SizedBox(height: 4),
          loading
              ? Text('-', style: AppTextStyles.h1)
              : n < 0
              ? Text('무제한', style: AppTextStyles.h1)
              : AppCountUp(value: n, suffix: '개', style: AppTextStyles.h1),
        ],
      ),
    );

    return AppPressScale(
      haptic: false,
      child: Material(
        color: AppColors.bgMuted,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '남은 이용권',
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '구매',
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [cell('즉시 게시', instant), cell('긴급 호출', urgent)],
                ),
                if (instant7 > 0) ...[
                  const SizedBox(height: 12),
                  Text('즉시 게시 7일권 $instant7개', style: AppTextStyles.body2),
                ],
                if (subLine != null) ...[
                  const SizedBox(height: 12),
                  Text(subLine!, style: AppTextStyles.body2),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
