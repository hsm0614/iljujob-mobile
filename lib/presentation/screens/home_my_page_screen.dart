import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:async'; // TimeoutException
import '../../config/constants.dart'; // baseUrl
import 'edit_worker_profile_screen.dart';

class WorkerMyPageScreen extends StatefulWidget {
  const WorkerMyPageScreen({super.key});

  @override
  State<WorkerMyPageScreen> createState() => _WorkerMyPageScreenState();
}

class _WorkerMyPageScreenState extends State<WorkerMyPageScreen> {
  // ===== Brand =====
  static const Color kBrandBlue = Color(0xFF3B8AFF);
  static const Color kBrandBlueLight = Color(0xFF6EB6FF);
  static const Color kBg = Color(0xFFF6F7FB);

  // ===== Profile State =====
  bool _loading = true;
  String _name = '이름 미등록';
  String _phone = '전화번호';
  String _imagePath = '';

  // ===== Settlement Summary =====
  bool _loadingSettle = true;
  int _settledAmount = 0; // 정산 완료
  int _pendingAmount = 0; // 정산 예정

  final _moneyFmt = NumberFormat('#,###');

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // 1) 캐시 먼저 보여주고
    await _loadCachedProfile();

    // 2) 서버로 최신 갱신(프로필 + 정산)
    await Future.wait([
      _refreshProfileFromServer(),
      _refreshSettlementSummary(),
    ]);
  }

  // =========================
  // Common helpers
  // =========================

  String _fullImageUrl(String path) {
    final p = (path).trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http')) return p;
    return '$baseUrl$p';
  }

  String _formatPhone(String phone) {
    final p = phone.replaceAll(RegExp(r'\D'), '');
    if (p.length == 11) return '${p.substring(0, 3)}-${p.substring(3, 7)}-${p.substring(7)}';
    if (p.length == 10) return '${p.substring(0, 2)}-${p.substring(2, 6)}-${p.substring(6)}';
    return phone;
  }

  String _formatMoney(int v) => '${_moneyFmt.format(v)}원';

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken') ?? '';
  }

  Future<int?> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('userId');
  }

  String _pickFirstNonEmpty(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  int _pickFirstInt(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final raw = data[k];
      if (raw == null) continue;
      final n = int.tryParse(raw.toString().replaceAll(RegExp(r'[^0-9-]'), ''));
      if (n != null) return n;
    }
    return 0;
  }

  // =========================
  // Profile
  // =========================

  Future<void> _loadCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();

    final cachedName = [
      prefs.getString('workerName'),
      prefs.getString('userName'),
      prefs.getString('name'),
      prefs.getString('user_name'),
    ].where((v) => v != null && v.trim().isNotEmpty).map((e) => e!.trim()).toList();

    final cachedPhone = (prefs.getString('userPhone') ?? '').trim();
    final cachedImage = (prefs.getString('workerProfileImageUrl') ?? '').trim();

    if (!mounted) return;
    setState(() {
      _name = cachedName.isNotEmpty ? cachedName.first : _name;
      _phone = cachedPhone.isNotEmpty ? cachedPhone : _phone;
      _imagePath = cachedImage.isNotEmpty ? cachedImage : _imagePath;
      _loading = false;
    });
  }

  Future<void> _refreshProfileFromServer() async {
    try {
      final token = await _token();
      final uid = await _userId();

      http.Response res;

      if (token.isNotEmpty) {
        res = await http.get(
          Uri.parse('$baseUrl/api/worker/profile'),
          headers: {'Authorization': 'Bearer $token'},
        );

        if (res.statusCode != 200 && uid != null) {
          res = await http.get(Uri.parse('$baseUrl/api/worker/profile?id=$uid'));
        }
      } else {
        if (uid == null) return;
        res = await http.get(Uri.parse('$baseUrl/api/worker/profile?id=$uid'));
      }

      if (res.statusCode != 200) return;

      final raw = jsonDecode(res.body);
      final Map<String, dynamic> data = (raw is Map && raw['data'] is Map)
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});

      final name = _pickFirstNonEmpty(data, [
        'name',
        'workerName',
        'worker_name',
        'userName',
        'user_name',
        'nickname',
      ]);

      final phone = _pickFirstNonEmpty(data, [
        'phone',
        'userPhone',
        'user_phone',
      ]);

      final image = _pickFirstNonEmpty(data, [
        'profile_image_url',
        'profileImageUrl',
        'profile_image',
        'imageUrl',
        'image_url',
      ]);

      final prefs = await SharedPreferences.getInstance();
      if (name.isNotEmpty) {
        await prefs.setString('workerName', name);
        await prefs.setString('userName', name);
      }
      if (phone.isNotEmpty) await prefs.setString('userPhone', phone);
      if (image.isNotEmpty) await prefs.setString('workerProfileImageUrl', image);

      if (!mounted) return;
      setState(() {
        if (name.isNotEmpty) _name = name;
        if (phone.isNotEmpty) _phone = phone;
        if (image.isNotEmpty) _imagePath = image;
        _loading = false;
      });
    } catch (_) {}
  }

  // =========================
  // Settlement Summary (정산 완료/예정)
  // =========================

 Future<void> _refreshSettlementSummary() async {
  if (!mounted) return;
  setState(() => _loadingSettle = true);

  http.Response? res;
  try {
    final token = await _token();
    final uid = await _userId();

    Uri? uri;
    if (token.isNotEmpty) {
      uri = Uri.parse('$baseUrl/api/worker/settlement-summary');
      res = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 8));
    } else if (uid != null) {
      uri = Uri.parse('$baseUrl/api/worker/settlement-summary?id=$uid');
      res = await http.get(uri).timeout(const Duration(seconds: 8));
    } else {
      debugPrint('❌ settlement-summary: no token & no userId');
      return;
    }



    if (res.statusCode != 200) return;

    final raw = jsonDecode(res.body);
    final Map<String, dynamic> data = (raw is Map && raw['data'] is Map)
        ? Map<String, dynamic>.from(raw['data'] as Map)
        : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});

    final settled = _pickFirstInt(data, [
      'settledAmount',
      'completedAmount',
      'paidAmount',
      'settled',
      'completed',
      'paid',
    ]);

    final pending = _pickFirstInt(data, [
      'pendingAmount',
      'expectedAmount',
      'scheduledAmount',
      'pending',
      'expected',
      'scheduled',
    ]);

    if (!mounted) return;
    setState(() {
      _settledAmount = settled;
      _pendingAmount = pending;
    });
  } on TimeoutException {
    debugPrint('⏱️ settlement-summary timeout (서버/네트워크 응답 없음)');
  } catch (e) {
    debugPrint('❌ settlement-summary error: $e');
  } finally {
    if (!mounted) return;
    setState(() => _loadingSettle = false); // ✅ 무조건 종료
  }
}

  // =========================
  // Navigation
  // =========================

  Future<void> _goEditProfile() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditWorkerProfileScreen()),
    );
    await _bootstrap();
  }

  Future<void> _confirmLogout() async {
  if (!mounted) return;

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true, // ✅ 중요 (안드로이드 하단 겹침 방지)
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
    isScrollControlled: true, // ✅ 중요
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ConfirmSheet(
      title: '정말 탈퇴할까요?',
      message: '탈퇴하면 계정 정보가 삭제되고 복구가 어려워요.',
      confirmText: '탈퇴하기',
      confirmColor: Color(0xFFDC2626),
      icon: Icons.person_off_rounded,
    ),
  );

  if (ok != true) return;
  await _withdrawAccount();
}

Future<void> _withdrawAccount() async {
  final uid = await _userId();
  if (uid == null) {
    debugPrint('❌ withdraw: no userId');
    return;
  }

  final uri = Uri.parse('$baseUrl/api/worker/profile?id=$uid');

  try {
    final token = await _token();

    http.Response res;
    if (token.isNotEmpty) {
      res = await http
          .delete(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 8));

      // 토큰 방식 막혀있으면(서버 구현차이) id 방식 재시도
      if (res.statusCode == 401 || res.statusCode == 403) {
        res = await http.delete(uri).timeout(const Duration(seconds: 8));
      }
    } else {
      res = await http.delete(uri).timeout(const Duration(seconds: 8));
    }

    if (res.statusCode != 200) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('탈퇴 실패 (${res.statusCode})')),
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
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('탈퇴 중 오류가 발생했어')),
    );
  }
}

  // =========================
  // UI
  // =========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: RefreshIndicator(
        onRefresh: _bootstrap,
        color: kBrandBlue,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              elevation: 0,
              backgroundColor: Colors.white,
              expandedHeight: 215, // ✅ 통계가 카드 안으로 들어가서 너무 높일 필요 없음
              automaticallyImplyLeading: false,
              toolbarHeight: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [kBrandBlue, kBrandBlueLight],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '마이페이지',
                            style: TextStyle(
                              fontFamily: 'Jalnan2TTF',
                              color: Colors.white,
                              fontSize: 22,
                              height: 1.1,
                            ),
                          ),
                          const Spacer(),

                          // ✅ 프로필 카드 안에 정산완료/정산예정 붙임
                          GestureDetector(
                            onTap: _goEditProfile,
                            child: _WorkerProfileCard(
                              brandBlue: kBrandBlue,
                              imageUrl: _fullImageUrl(_imagePath),
                              displayName: _name,
                              phoneText: _formatPhone(_phone),
                              loading: _loading,
                              loadingSettle: _loadingSettle,
                              settledText: _formatMoney(_settledAmount),
                              pendingText: _formatMoney(_pendingAmount),
                              onEditProfile: _goEditProfile,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _SectionCard(
                  title: '내 알바일주 관리',
                  children: [
                    _ItemTile(
                      icon: Icons.edit_rounded,
                      label: '프로필 수정',
                      onTap: _goEditProfile,
                    ),
                    _ItemTile(
                      icon: Icons.favorite_border,
                      label: '찜한 공고',
                      onTap: () => Navigator.pushNamed(context, '/bookmarked-jobs'),
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
                      icon: Icons.campaign_rounded,
                      label: '공지사항',
                      onTap: () => Navigator.pushNamed(context, '/notices'),
                    ),
                    _ItemTile(
                      icon: Icons.local_activity_outlined,
                      label: '이벤트',
                      onTap: () => Navigator.pushNamed(context, '/events'),
                    ),
                    _ItemTile(
                      icon: Icons.support_agent_rounded,
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
                  children: const [
                    _ItemTileStatic(
                      icon: Icons.policy_rounded,
                      label: '약관 및 정책',
                      routeName: '/terms-list',
                    ),
                    _ExpandableBizInfo(brandBlue: kBrandBlue),
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
                      icon: Icons.logout_rounded,
                      label: '로그아웃',
                      labelStyle: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                      trailing: const Icon(Icons.logout, size: 18, color: Color(0xFFDC2626)),
                      onTap: _confirmLogout,
                    ),
                    _ItemTile(
  icon: Icons.person_off_rounded,
  label: '회원 탈퇴',
  labelStyle: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
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

/* --------------------------- Profile Card (with Settlement) --------------------------- */

class _WorkerProfileCard extends StatelessWidget {
  final Color brandBlue;
  final String imageUrl;
  final String displayName;
  final String phoneText;
  final bool loading;

  final bool loadingSettle;
  final String settledText;
  final String pendingText;

  final VoidCallback onEditProfile;

  const _WorkerProfileCard({
    required this.brandBlue,
    required this.imageUrl,
    required this.displayName,
    required this.phoneText,
    required this.loading,
    required this.loadingSettle,
    required this.settledText,
    required this.pendingText,
    required this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    final hasImg = imageUrl.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.97),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFFEAF2FF),
                    backgroundImage: (!loading && hasImg) ? NetworkImage(imageUrl) : null,
                    child: (loading || !hasImg)
                        ? const Icon(Icons.account_circle, size: 30, color: Colors.black54)
                        : null,
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onEditProfile,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: brandBlue,
                            shape: BoxShape.circle,
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: const Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loading ? '불러오는 중…' : displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Pill(
                      icon: Icons.call_rounded,
                      text: loading ? '잠시만요' : phoneText,
                      color: const Color(0xFF3B8AFF),
                      bg: const Color(0xFFF1F6FF),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: onEditProfile,
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                label: const Text('프로필 수정'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEAF2FF),
                  foregroundColor: const Color(0xFF3B8AFF),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  minimumSize: const Size(0, 40),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          Container(height: 1, color: const Color(0xFFF1F5F9)),
          const SizedBox(height: 10),

          // ✅ 카드 안쪽 정산완료/정산예정
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  title: '정산 완료',
                  value: loadingSettle ? '불러오는 중…' : settledText,
                  icon: Icons.check_circle_rounded,
                  accent: const Color(0xFF3B8AFF),
                  bg: const Color(0xFFEAF2FF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  title: '정산 예정',
                  value: loadingSettle ? '불러오는 중…' : pendingText,
                  icon: Icons.schedule_rounded,
                  accent: const Color(0xFF3B8AFF),
                  bg: const Color(0xFFF1F6FF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final Color bg;

  const _MiniStat({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return Container(
          // ✅ height 고정 제거 (기기별로 더 안전)
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(0.14)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min, // ✅ 세로로 덜 먹게
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF64748B),
                        height: 1.0, // ✅ 라인높이 줄임
                      ),
                    ),
                    const SizedBox(height: 4),
                    // ✅ value가 길거나 공간이 작으면 자동 축소
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/* --------------------------- Common UI Widgets --------------------------- */

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color bg;

  const _Pill({
    required this.icon,
    required this.text,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w800),
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

  const _SectionCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
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
    final out = <Widget>[];
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
            style: labelStyle ?? t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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

class _ItemTileStatic extends StatelessWidget {
  final IconData icon;
  final String label;
  final String routeName;

  const _ItemTileStatic({
    required this.icon,
    required this.label,
    required this.routeName,
  });

  @override
  Widget build(BuildContext context) {
    return _ItemTile(
      icon: icon,
      label: label,
      onTap: () => Navigator.pushNamed(context, routeName),
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
        leading: Icon(Icons.info_outline_rounded, color: brandBlue),
        title: const Text('사업자 정보', style: TextStyle(fontWeight: FontWeight.w800)),
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
    padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomSafe), // ✅ 여기!
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
