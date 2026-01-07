import 'dart:async'; // TimeoutException
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../config/constants.dart'; // baseUrl
import '../../data/services/ai_api.dart'; // fetchMySubscription()

class ClientMyPageScreen extends StatefulWidget {
  const ClientMyPageScreen({super.key});
  @override
  State<ClientMyPageScreen> createState() => _ClientMyPageScreenState();
}

class _ClientMyPageScreenState extends State<ClientMyPageScreen> {
  // ===== Branding =====
  static const Color brandBlue = Color(0xFF3B8AFF);
  static const Color brandBlueLight = Color(0xFF6EB6FF);

  // ===== Profile State =====
  String companyName = '회사명';
  String managerName = '담당자명';
  String phoneNumber = '전화번호';
  String logoUrl = '';

  // ===== Subscription =====
  bool _subLoading = true;
  SubscriptionStatus? _sub;

  // Helpers
  String _getFullImageUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$baseUrl$path';
  }

  String _formatPhone(String phone) {
    final p = phone.replaceAll(RegExp(r'\D'), '');
    if (p.length == 11) return '${p.substring(0, 3)}-${p.substring(3, 7)}-${p.substring(7)}';
    if (p.length == 10) return '${p.substring(0, 3)}-${p.substring(3, 6)}-${p.substring(6)}';
    return phone;
  }

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken') ?? '';
  }
Future<String> _phoneRaw() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = (prefs.getString('userPhone') ?? '').replaceAll(RegExp(r'\D'), '');
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
    _loadProfileInfo();
    _loadSubscription();
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
    await Future.wait([
      _loadProfileInfo(),
      _loadSubscription(),
    ]);
  }

  String _subSummaryText() {
    if (_subLoading) return '조회 중...';
    if (!(_sub?.active ?? false)) return '미구독';
    final plan = (_sub!.plan ?? '구독').toUpperCase();
    final d = _sub!.expiresAt;
    final days = (d != null) ? d.difference(DateTime.now()).inDays : null;
    final left = (days != null) ? 'D-$days' : '';
    return '$plan $left';
  }

  Future<void> _loadProfileInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      companyName = prefs.getString('companyName') ?? '회사명';
      managerName = prefs.getString('userName') ?? '담당자명';
      phoneNumber = prefs.getString('userPhone') ?? '전화번호';
      logoUrl = prefs.getString('logoUrl') ?? '';
    });
  }

  // =========================
  // Logout / Withdraw
  // =========================

  Future<void> _confirmLogout() async {
    if (!mounted) return;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true, // ✅ 안드로이드 하단 가드
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfirmSheet(
        title: '로그아웃할까요?',
        message: '로그아웃하면 다시 로그인해야 해요.',
        confirmText: '로그아웃',
        confirmColor: const Color(0xFFDC2626),
        icon: Icons.logout_rounded,
      ),
    );

    if (ok != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil('/onboarding', (route) => false);
  }

  Future<void> _confirmWithdraw() async {
    if (!mounted) return;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true, // ✅ 안드로이드 하단 가드
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfirmSheet(
        title: '정말 탈퇴할까요?',
        message: '탈퇴하면 계정 정보가 삭제되고 복구가 어려워요.',
        confirmText: '탈퇴하기',
        confirmColor: const Color(0xFFDC2626),
        icon: Icons.person_off_rounded,
      ),
    );

    if (ok != true) return;
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

  final token = await _token();
  final headers = <String, String>{};
  if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

  // ✅ 서버가 query로 phone을 요구하는 경우 대응
  final uriQuery = Uri.parse('$baseUrl/api/client/profile?id=$uid&phone=$phone');

  // ✅ 서버가 body로 phone을 요구하는 경우 대응
  final uriBody = Uri.parse('$baseUrl/api/client/profile');

  try {
    // 1) query 방식 먼저
    var res = await http.delete(uriQuery, headers: headers).timeout(const Duration(seconds: 8));

    // 2) 안 되면 body 방식
    if (res.statusCode < 200 || res.statusCode >= 300) {
      res = await _deleteWithJsonBody(
        uriBody,
        {'id': uid, 'phone': phone},
        headers,
      );
    }

    final ok = res.statusCode >= 200 && res.statusCode < 300; // ✅ 200/204 모두 성공
    if (!ok) {
      if (!mounted) return;
      final msg = res.body.isNotEmpty ? res.body : '(empty body)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('탈퇴 실패 (${res.statusCode}) $msg')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil('/onboarding', (route) => false);
  } on TimeoutException {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('서버 응답이 늦어요. 잠시 후 다시 시도해줘')),
    );
  } catch (_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('탈퇴 중 오류가 발생했어')),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        color: brandBlue,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              elevation: 0,
              backgroundColor: Colors.white,
              expandedHeight: 200,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3B8AFF), Color(0xFF6EB6FF)],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '마이페이지',
                            style: TextStyle(
                              fontFamily: 'Jalnan2TTF',
                              color: Colors.white,
                              fontSize: 22,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _ProfileCard(
                            brandBlue: brandBlue,
                            brandBlueLight: brandBlueLight,
                            logoUrl: _getFullImageUrl(logoUrl),
                            companyName: companyName,
                            managerName: managerName,
                            phoneNumber: _formatPhone(phoneNumber),
                            onEdit: () => Navigator.pushNamed(context, '/edit_profile'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              toolbarHeight: 0,
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _SectionCard(
                  title: '사용자',
                  children: [
                    _ItemTile(
                      icon: Icons.workspace_premium,
                      label: '구독 관리',
                      trailing: _StatusPill(text: _subSummaryText()),
                      onTap: () async {
                        await Navigator.pushNamed(context, '/subscription/manage');
                        if (mounted) _loadSubscription();
                      },
                    ),
                    if (!(_sub?.active ?? false))
                      _ItemTile(
                        icon: Icons.credit_card,
                        label: '구독하기',
                        onTap: () async {
                          final ok = await Navigator.pushNamed(context, '/subscribe');
                          if (ok == true && mounted) _loadSubscription();
                        },
                      ),
                    _ItemTile(
                      icon: Icons.credit_card,
                      label: '이용권 구매',
                      onTap: () => Navigator.pushNamed(context, '/purchase-pass'),
                    ),
                    _ItemTile(
                      icon: Icons.notifications_active,
                      label: '알림 설정',
                      onTap: () => Navigator.pushNamed(context, '/notifications'),
                    ),
                    _ItemTile(
                      icon: Icons.report,
                      label: '신고 내역',
                      onTap: () => Navigator.pushNamed(context, '/report-history'),
                    ),
                    _ItemTile(
                      icon: Icons.block,
                      label: '차단한 사용자',
                      onTap: () => Navigator.pushNamed(context, '/blocked-users'),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _SectionCard(
                  title: '고객센터',
                  children: [
                    _ItemTile(
                      icon: Icons.campaign,
                      label: '공지사항',
                      onTap: () => Navigator.pushNamed(context, '/notices'),
                    ),
                    _ItemTile(
                      icon: Icons.local_activity_outlined,
                      label: '이벤트',
                      onTap: () => Navigator.pushNamed(context, '/events'),
                    ),
                    _ItemTile(
                      icon: Icons.support_agent,
                      label: '고객센터',
                      onTap: () => Navigator.pushNamed(context, '/support'),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _SectionCard(
                  title: '서비스',
                  children: [
                    _ItemTile(
                      icon: Icons.policy,
                      label: '약관 및 정책',
                      onTap: () => Navigator.pushNamed(context, '/terms-list'),
                    ),
                    _ExpandableBizInfo(brandBlue: brandBlue),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: _SectionCard(
                  title: '계정',
                  children: [
                    _ItemTile(
                      icon: Icons.logout,
                      label: '로그아웃',
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                      trailing: const Icon(Icons.logout, size: 18, color: Color(0xFFDC2626)),
                      onTap: _confirmLogout,
                    ),
                    _ItemTile(
                      icon: Icons.person_off_rounded,
                      label: '회원 탈퇴',
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                      trailing: const Icon(Icons.delete_forever, size: 18, color: Color(0xFFDC2626)),
                      onTap: _confirmWithdraw,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* --------------------------- Widgets --------------------------- */

class _ProfileCard extends StatelessWidget {
  final Color brandBlue;
  final Color brandBlueLight;
  final String logoUrl;
  final String companyName;
  final String managerName;
  final String phoneNumber;
  final VoidCallback onEdit;

  const _ProfileCard({
    required this.brandBlue,
    required this.brandBlueLight,
    required this.logoUrl,
    required this.companyName,
    required this.managerName,
    required this.phoneNumber,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoUrl.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xFFEAF2FF),
                backgroundImage: hasLogo ? NetworkImage(logoUrl) : null,
                child: hasLogo ? null : const Icon(Icons.business, size: 30, color: Colors.black54),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onEdit,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: brandBlue,
                        shape: BoxShape.circle,
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Icon(Icons.edit, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TwoLine(title: companyName, subtitle: '회사명'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _ChipText(
                      text: managerName,
                      icon: Icons.person,
                      maxWidth: 160,
                      ensureVisible: false,
                    ),
                    _ChipText(
                      text: phoneNumber,
                      icon: Icons.call,
                      maxWidth: 220,
                      ensureVisible: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            fit: FlexFit.loose,
            child: LayoutBuilder(
              builder: (_, c) {
                final narrow = c.maxWidth < 120;
                if (narrow) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: IconButton.filledTonal(
                      onPressed: onEdit,
                      icon: const Icon(Icons.arrow_forward_ios, size: 16),
                    ),
                  );
                }
                return Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    child: FilledButton.tonalIcon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.arrow_forward_ios, size: 16),
                      label: const Text('프로필'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEAF2FF),
                        foregroundColor: brandBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        minimumSize: const Size(0, 40),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoLine extends StatelessWidget {
  final String title;
  final String subtitle;
  const _TwoLine({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: '$subtitle: ',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          TextSpan(
            text: title,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipText extends StatelessWidget {
  final String text;
  final IconData icon;
  final double maxWidth;
  final bool ensureVisible;

  const _ChipText({
    required this.text,
    required this.icon,
    this.maxWidth = 160,
    this.ensureVisible = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F6FF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF3B8AFF)),
            const SizedBox(width: 6),
            if (ensureVisible)
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              )
            else
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B8AFF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Jalnan2TTF',
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._withDividers(children),
        ],
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    final List<Widget> out = [];
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i != items.length - 1) out.add(const Divider(height: 1, indent: 56));
    }
    return out;
  }
}

class _ItemTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextStyle? labelStyle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _ItemTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelStyle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: ListTile(
          leading: Icon(icon, size: 22, color: const Color(0xFF3B8AFF)),
          title: Text(
            label,
            style: labelStyle ?? t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black38),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          dense: true,
          minLeadingWidth: 0,
        ),
      ),
    );
  }
}

class _ExpandableBizInfo extends StatelessWidget {
  final Color brandBlue;
  const _ExpandableBizInfo({required this.brandBlue});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(Icons.info_outline, color: brandBlue),
        title: const Text('사업자 정보', style: TextStyle(fontWeight: FontWeight.w700)),
        shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.transparent)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: const [
          _BizInfoItem('법인명', '주식회사 찾다'),
          _BizInfoItem('대표자', '황성민'),
          _BizInfoItem('사업자등록번호', '480-88-03690'),
          _BizInfoItem('법인등록번호', '120111-0146420'),
          _BizInfoItem('통신판매업 번호', '2025-인천연수구-2179호'),
          _BizInfoItem('이메일', 'hsm@outfind.co.kr'),
          _BizInfoItem('고객센터', '070-4792-3001 / 010-4653-3002'),
          _BizInfoItem('개업연월일', '2025년 05월 26일'),
          _BizInfoItem('사업장 소재지', '인천광역시 연수구 하모니로178번길 22, 7층 707-나60호 (송도동)'),
          _BizInfoItem('본점 소재지', '인천광역시 연수구 하모니로178번길 22, 7층 707-나60호 (송도동)'),
          _BizInfoItem('업태', '정보통신업'),
          _BizInfoItem('종목', '데이터베이스 및 온라인 정보제공업, 온라인활용마케팅 및 관련사업지원서비스'),
        ],
      ),
    );
  }
}

class _BizInfoItem extends StatelessWidget {
  final String k;
  final String v;
  const _BizInfoItem(this.k, this.v);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: const TextStyle(color: Colors.black54, fontSize: 13.5)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontSize: 13.5, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  const _StatusPill({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF3B8AFF),
        ),
      ),
    );
  }
}

/* --------------------------- Confirm Bottom Sheet (Android Safe) --------------------------- */

class _ConfirmSheet extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final Color confirmColor;
  final IconData icon;

  const _ConfirmSheet({
    required this.title,
    required this.message,
    required this.confirmText,
    required this.confirmColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomSafe), // ✅ 안드로이드 가림 방지 핵심
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: confirmColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: confirmColor),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280), height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF111827),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('취소', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: confirmColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(confirmText, style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
