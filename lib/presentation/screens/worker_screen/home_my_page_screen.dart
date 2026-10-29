import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:async'; // TimeoutException
import '../../../config/constants.dart'; // baseUrl
import '../../../data/services/authenticated_http_client.dart';
import '../../../data/services/screen_analytics_service.dart';
import 'package:geolocator/geolocator.dart';

import '../../../data/services/background_location_service.dart';
import 'edit_worker_profile_screen.dart';
import 'labor_consult_screen.dart';
import '../../../config/app_theme.dart';
import '../../../widget/dev_account_switch.dart';
import '../../../config/messages.dart';
import '../../../widget/app_ui.dart';
import '../../../widget/app_motion.dart';

class WorkerMyPageScreen extends StatefulWidget {
  /// 정산 박스를 누르면 캘린더 탭으로 (월별 정산이 거기 있다)
  final VoidCallback? onGoCalendar;
  const WorkerMyPageScreen({super.key, this.onGoCalendar});

  @override
  State<WorkerMyPageScreen> createState() => _WorkerMyPageScreenState();
}

class _WorkerMyPageScreenState extends State<WorkerMyPageScreen> {
  // ===== Brand =====
  static const Color kBrandBlue = AppColors.primary;
  static const Color kBg = AppColors.bgPage;

  // ===== Profile State =====
  bool _loading = true;
  String _name = '이름 미등록';
  String _phone = '전화번호';
  String _imagePath = '';

  // ===== Settlement Summary =====
  bool _loadingSettle = true;
  int _settledAmount = 0; // 정산 완료
  int _pendingAmount = 0; // 정산 예정

  // ===== Activity Score =====
  bool _loadingScore = true;
  int _totalScore = 0;
  String _grade = 'NEW';
  int _loginScore = 0;
  int _statusUpdateScore = 0;
  int _attendanceScore = 0;
  int _responseScore = 0;
  int _cancelPenalty = 0;


  bool _alwaysLocation = false;

  @override
  void initState() {
    super.initState();
    ScreenAnalyticsService.instance.logScreenView('worker_my_page');
    _bootstrap();
    BackgroundLocationService.isEnabled().then((on) {
      if (mounted) setState(() => _alwaysLocation = on);
    });
  }

  // 상시 위치 공유. '항상 허용' 을 못 받으면 켜지지 않는다 —
  // 안드로이드 11+ 는 앱이 직접 줄 수 없고 설정 화면에서만 줄 수 있다.
  Future<void> _toggleAlwaysLocation() async {
    if (_alwaysLocation) {
      await BackgroundLocationService.disable();
      if (!mounted) return;
      setState(() => _alwaysLocation = false);
      return;
    }

    final ok = await BackgroundLocationService.enable();
    if (!mounted) return;
    setState(() => _alwaysLocation = ok);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('위치 권한을 \'항상 허용\' 으로 바꿔야 켤 수 있어요.'),
          action: SnackBarAction(
            label: '설정 열기',
            onPressed: Geolocator.openAppSettings,
          ),
        ),
      );
    }
  }

  Future<void> _bootstrap() async {
    // 1) 캐시 먼저 보여주고
    await _loadCachedProfile();

    // 2) 서버로 최신 갱신(프로필 + 정산 + 활동지수)
    await Future.wait([
      _refreshProfileFromServer(),
      _refreshSettlementSummary(),
      _refreshActivityScore(),
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
    if (p.length == 11)
      return '${p.substring(0, 3)}-${p.substring(3, 7)}-${p.substring(7)}';
    if (p.length == 10)
      return '${p.substring(0, 2)}-${p.substring(2, 6)}-${p.substring(6)}';
    return phone;
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

    final cachedName =
        [
              prefs.getString('workerName'),
              prefs.getString('userName'),
              prefs.getString('name'),
              prefs.getString('user_name'),
            ]
            .where((v) => v != null && v.trim().isNotEmpty)
            .map((e) => e!.trim())
            .toList();

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
      final uid = await _userId();

      http.Response res;

      try {
        res = await AuthenticatedHttpClient.get(
          Uri.parse('$baseUrl/api/worker/profile'),
        ).timeout(const Duration(seconds: 8));
      } on AuthSessionExpiredException {
        if (uid == null) rethrow;
        res = await http.get(Uri.parse('$baseUrl/api/worker/profile?id=$uid'));
      }

      if (res.statusCode != 200 && uid != null) {
        res = await http.get(Uri.parse('$baseUrl/api/worker/profile?id=$uid'));
      }

      if (res.statusCode != 200) return;

      final raw = jsonDecode(res.body);
      final Map<String, dynamic> data =
          (raw is Map && raw['data'] is Map)
              ? Map<String, dynamic>.from(raw['data'] as Map)
              : (raw is Map
                  ? Map<String, dynamic>.from(raw)
                  : <String, dynamic>{});

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
      if (image.isNotEmpty)
        await prefs.setString('workerProfileImageUrl', image);

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
      final uid = await _userId();

      try {
        res = await AuthenticatedHttpClient.get(
          Uri.parse('$baseUrl/api/worker/settlement-summary'),
        ).timeout(const Duration(seconds: 8));
      } on AuthSessionExpiredException {
        if (uid == null) {
          debugPrint('❌ settlement-summary: no token & no userId');
          return;
        }
        res = await http
            .get(Uri.parse('$baseUrl/api/worker/settlement-summary?id=$uid'))
            .timeout(const Duration(seconds: 8));
      }

      if (res.statusCode != 200) return;

      final raw = jsonDecode(res.body);
      final Map<String, dynamic> data =
          (raw is Map && raw['data'] is Map)
              ? Map<String, dynamic>.from(raw['data'] as Map)
              : (raw is Map
                  ? Map<String, dynamic>.from(raw)
                  : <String, dynamic>{});

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
  // Activity Score
  // =========================

  Future<void> _refreshActivityScore() async {
    if (!mounted) return;
    setState(() => _loadingScore = true);
    try {
      final uid = await _userId();
      if (uid == null) return;
      final res = await http
          .get(Uri.parse('$baseUrl/api/worker/activity-score?workerId=$uid'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _totalScore = (data['total_score'] as num?)?.toInt() ?? 0;
          _grade = data['grade']?.toString() ?? 'NEW';
          _loginScore = (data['login_score'] as num?)?.toInt() ?? 0;
          _statusUpdateScore =
              (data['status_update_score'] as num?)?.toInt() ?? 0;
          _attendanceScore = (data['attendance_score'] as num?)?.toInt() ?? 0;
          _responseScore = (data['response_rate_score'] as num?)?.toInt() ?? 0;
          _cancelPenalty = (data['cancel_penalty'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingScore = false);
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
      message: '프로필·지원 내역·채팅이 모두 지워지고 되돌릴 수 없어요.',
      confirmLabel: '탈퇴하기',
      cancelLabel: '취소',
      destructive: true,
    );
    if (!ok) return;
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
      final res = await AuthenticatedHttpClient.delete(
        uri,
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        if (!mounted) return;
        debugPrint('탈퇴 실패 (${res.statusCode})');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(Msg.withdrawFailed)));
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('탈퇴 중 오류가 발생했어')));
    }
  }


  // =========================
  // UI — 2026-10 리디자인: 떠 있는 카드·파란 아이콘 → 화면 폭 흰 블록 + 회색 아이콘 줄
  // (토스·당근 마이). 같은 메뉴가 두 번(프로필 수정) 나오던 것도 정리
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
                        imageUrl: _fullImageUrl(_imagePath),
                        title: _name,
                        subtitle: _formatPhone(_phone),
                        loading: _loading,
                        onTap: _goEditProfile,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _MoneyBox(
                          loading: _loadingSettle,
                          settled: _settledAmount,
                          pending: _pendingAmount,
                          onTap: widget.onGoCalendar,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _TrustRow(
                          loading: _loadingScore,
                          score: _totalScore,
                          grade: _grade,
                          onTap: _showScoreSheet,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                AppMenuSection(
                  title: '내 알바',
                  children: [
                    AppMenuRow(
                      icon: Icons.favorite_border_rounded,
                      label: '관심 공고',
                      onTap:
                          () =>
                              Navigator.pushNamed(context, '/bookmarked-jobs'),
                    ),
                    AppMenuRow(
                      icon: Icons.notifications_none_rounded,
                      label: '알림 설정',
                      onTap:
                          () => Navigator.pushNamed(context, '/notifications'),
                    ),
                    AppMenuRow(
                      icon: Icons.near_me_outlined,
                      label: '상시 위치 공유',
                      subtitle: '앱을 닫아도 근처 사장님의 급구 연락을 받아요',
                      onTap: _toggleAlwaysLocation,
                      trailing: Switch.adaptive(
                        value: _alwaysLocation,
                        activeTrackColor: AppColors.primary,
                        onChanged: (_) => _toggleAlwaysLocation(),
                      ),
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
                      subtitle: '임금·주휴수당·해고가 궁금할 때',
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LaborConsultScreen(),
                            ),
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
                // 계정 행동은 실수로 누르기 쉬운 빨간 줄 대신 맨 아래 작은 글자로 (토스·당근 공통)
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

  void _showScoreSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder:
          (_) => _ScoreDetailSheet(
            score: _totalScore,
            grade: _grade,
            loginScore: _loginScore,
            statusUpdateScore: _statusUpdateScore,
            attendanceScore: _attendanceScore,
            responseScore: _responseScore,
            cancelPenalty: _cancelPenalty,
          ),
    );
  }
}

/* --------------------------- 프로필 --------------------------- */

class _MoneyBox extends StatelessWidget {
  final bool loading;
  final int settled;
  final int pending;
  final VoidCallback? onTap;

  const _MoneyBox({
    required this.loading,
    required this.settled,
    required this.pending,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgMuted,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('이번 달 일한 금액', style: AppTextStyles.body2),
                    const SizedBox(height: 4),
                    loading
                        ? Text('-', style: AppTextStyles.jobPayDisplay)
                        : AppCountUp(
                          value: settled,
                          style: AppTextStyles.jobPayDisplay.copyWith(
                            fontSize: AppFontSize.display,
                          ),
                        ),
                    if (!loading && pending > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '일할 예정 ${NumberFormat('#,###').format(pending)}원 더 있어요',
                        style: AppTextStyles.body2.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* --------------------------- 신뢰도 --------------------------- */

// 등급 기준은 CLAUDE.md·서버와 같다: NEW <20 · C 20~39 · B 40~69 · A 70~99 · S 100+
// (전엔 진행 바만 30/60/100/150을 써서 'B 55점 → A까지 45점'처럼 틀리게 나왔다)
Color _gradeColor(String grade) => switch (grade) {
  'S' => AppColors.gradeS,
  'A' => AppColors.gradeA,
  'B' => AppColors.gradeB,
  _ => AppColors.textSecondary,
};

String _gradeLabel(String grade) => switch (grade) {
  'S' => '최고 신뢰',
  'A' => '높은 신뢰',
  'B' => '보통',
  'C' => '낮음',
  _ => '새로 온 알바생',
};

/// (다음 등급, 현재 구간 시작, 다음 등급 점수). S면 다음 등급 없음
(String?, int, int) _nextGrade(String grade) => switch (grade) {
  'NEW' => ('C', 0, 20),
  'C' => ('B', 20, 40),
  'B' => ('A', 40, 70),
  'A' => ('S', 70, 100),
  _ => (null, 100, 100),
};

class _TrustRow extends StatelessWidget {
  final bool loading;
  final int score;
  final String grade;
  final VoidCallback onTap;

  const _TrustRow({
    required this.loading,
    required this.score,
    required this.grade,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(grade);
    final (next, from, to) = _nextGrade(grade);
    final progress =
        next == null ? 1.0 : ((score - from) / (to - from)).clamp(0.0, 1.0);

    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child:
            loading
                ? const SizedBox(
                  height: 44,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                : Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      // 'NEW'가 40px 칸에서 두 줄로 꺾이던 것
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          grade,
                          maxLines: 1,
                          style: AppTextStyles.h3.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '내 신뢰도 $score점',
                                  style: AppTextStyles.jobTitle,
                                ),
                                TextSpan(
                                  text: '  ${_gradeLabel(grade)}',
                                  style: AppTextStyles.body2,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 4,
                              backgroundColor: AppColors.bgMuted,
                              valueColor: AlwaysStoppedAnimation(color),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            next == null
                                ? '최고 등급이에요. 사장님 후보 목록 맨 위에 보여요'
                                : '$next등급까지 ${to - score}점',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
      ),
    );
  }
}

class _ScoreDetailSheet extends StatelessWidget {
  final int score;
  final String grade;
  final int loginScore;
  final int statusUpdateScore;
  final int attendanceScore;
  final int responseScore;
  final int cancelPenalty;

  const _ScoreDetailSheet({
    required this.score,
    required this.grade,
    required this.loginScore,
    required this.statusUpdateScore,
    required this.attendanceScore,
    required this.responseScore,
    required this.cancelPenalty,
  });

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(grade);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('내 신뢰도 $score점', style: AppTextStyles.h2),
            const SizedBox(height: 4),
            Text(
              '점수가 높을수록 사장님 긴급 호출 후보 목록 위쪽에 보여요.',
              style: AppTextStyles.body2,
            ),
            const SizedBox(height: 20),
            _DetailRow('앱 접속', '하루 한 번 열면 +3점', loginScore),
            _DetailRow('활동', '공고 보기·관심 공고·채팅', statusUpdateScore),
            _DetailRow('응답', '긴급 호출에 답하면 오르고, 안 하면 내려가요', responseScore),
            _DetailRow('출근', '출근 확정 후 실제 출근하면 +10점', attendanceScore),
            _DetailRow(
              '취소·노쇼',
              '수락 후 취소 -3점 · 노쇼 -10점',
              -cancelPenalty,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                children: [
                  for (final (g, range) in const [
                    ('S', '100점 이상'),
                    ('A', '70 ~ 99점'),
                    ('B', '40 ~ 69점'),
                    ('C', '20 ~ 39점'),
                    ('NEW', '20점 미만'),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(
                              g,
                              style: AppTextStyles.captionBold.copyWith(
                                fontSize: AppFontSize.body2,
                                color: _gradeColor(g),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              range,
                              style: AppTextStyles.body2.copyWith(
                                color:
                                    g == grade
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary,
                                fontWeight:
                                    g == grade
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (g == grade)
                            Text(
                              '지금',
                              style: AppTextStyles.captionBold.copyWith(
                                color: color,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String desc;
  final int score;
  const _DetailRow(this.label, this.desc, this.score);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.body1),
                Text(desc, style: AppTextStyles.body2),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            score < 0 ? '$score점' : '+$score점',
            style: AppTextStyles.jobTitle.copyWith(
              color: score < 0 ? AppColors.error : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/* --------------------------- 사업자 정보 --------------------------- */

