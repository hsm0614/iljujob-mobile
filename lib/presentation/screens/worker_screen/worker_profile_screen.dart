import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../config/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/services/authenticated_http_client.dart';
import '../../../config/messages.dart';
import '../../../config/app_theme.dart';
import '../../../widget/app_ui.dart';

class WorkerProfileScreen extends StatefulWidget {
  final int workerId;

  const WorkerProfileScreen({super.key, required this.workerId});

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> experiences = [];
  List<Map<String, dynamic>> licenses = [];
  bool isLoading = true;
  bool isBlocked = false;

  /// 이력서 열람 동의 여부 (워커가 프로필에서 체크한 값)
  bool canViewResume = false;

  int _activityScore = 0;

  @override
  void initState() {
    super.initState();
    _fetchProfile(widget.workerId);
  }

  /// 서버에서 내려오는 열람 동의 플래그 파싱
  bool _parseResumeFlag(dynamic flag) {
    if (flag == null) return false;
    if (flag is bool) return flag;
    if (flag is num) return flag == 1;

    if (flag is String) {
      final upper = flag.toUpperCase();
      return upper == '1' || upper == 'Y' || upper == 'YES' || upper == 'TRUE';
    }
    return false;
  }

  Future<void> _fetchProfile(int workerId) async {
    // 토큰을 붙인다 — 서버가 이력서 열람 동의를 요청자 기준으로 판정하고, 토큰 없으면 이름을 가려 보낸다
    Future<dynamic> getJson(String path) async {
      try {
        final res = await AuthenticatedHttpClient.get(Uri.parse('$baseUrl$path'));
        return res.statusCode == 200 ? jsonDecode(res.body) : null;
      } catch (_) {
        return null;
      }
    }

    final r = await Future.wait([
      getJson('/api/worker/profile?id=$workerId'),
      getJson('/api/worker/experiences?workerId=$workerId'),
      getJson('/api/worker/licenses?workerId=$workerId'),
      getJson('/api/worker/activity-score?workerId=$workerId'),
    ]);
    if (!mounted) return;
    setState(() {
      if (r[0] is Map) {
        profile = Map<String, dynamic>.from(r[0]);
        canViewResume = _parseResumeFlag(profile!['resume_consent']);
      }
      if (r[1] is List) experiences = List<Map<String, dynamic>>.from(r[1]);
      if (r[2] is List) licenses = List<Map<String, dynamic>>.from(r[2]);
      if (r[3] is Map) {
        _activityScore = (r[3]['total_score'] as num?)?.toInt() ?? 0;
      }
      isLoading = false;
    });
  }

  String get _ageGender {
    final y = int.tryParse((profile?['birth_year'] ?? '').toString().padRight(4).substring(0, 4).trim());
    final g = profile?['gender'];
    return [
      if (y != null && y > 1900) '${DateTime.now().year - y}세',
      if (g == 'male' || g == '남') '남' else if (g == 'female' || g == '여') '여',
    ].join(' · ');
  }

  Future<void> _block(String targetType, int targetId) async {
    if (isBlocked) return;
    final ok = await showAppSheet(
      context,
      title: '이 알바생을 차단할까요?',
      message: '차단하면 채팅과 지원을 더 주고받을 수 없어요.',
      confirmLabel: '차단하기',
      cancelLabel: '취소',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final response = await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/user-block/block'),
      body: {'userId': prefs.getInt('userId') ?? 0, 'targetId': targetId, 'targetType': targetType},
    );
    if (!mounted) return;
    if (response.statusCode == 200) setState(() => isBlocked = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(response.statusCode == 200 ? '차단했어요.' : Msg.server)),
    );
  }

  // 신고·차단은 자주 쓰는 게 아니다 — 앱바에 빨간 신고·검정 차단 아이콘이 늘 떠 있던 것을 ⋯ 하나로
  void _showMoreSheet() {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('신고하기'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showReportDialog('worker', widget.workerId);
                  },
                ),
                ListTile(
                  title: Text(isBlocked ? '차단한 알바생이에요' : '차단하기', style: TextStyle(color: isBlocked ? AppColors.textTertiary : AppColors.error)),
                  onTap:
                      isBlocked
                          ? null
                          : () {
                            Navigator.pop(ctx);
                            _block('worker', widget.workerId);
                          },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _showReportDialog(String targetType, int targetId) async {
    final r = await showReportSheet(
      context,
      title: '이 사용자를 신고할까요?',
      reasons: const [
        '음란물 또는 불쾌한 콘텐츠',
        '폭력성 또는 위협적인 언행',
        '욕설/혐오 발언/차별',
        '허위 정보 또는 사기 의심',
        '기타',
      ],
    );
    if (r == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final reporterId = prefs.getInt('userId') ?? 0;
    final reporterType = prefs.getString('userType');

    final response = await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/user-report'),
      body: {
        'reporterId': reporterId,
        if (reporterType != null && reporterType.isNotEmpty)
          'reporterType': reporterType,
        'targetId': targetId,
        'targetType': targetType,
        'reasonCategory': r.reason,
        'reasonDetail': r.detail,
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(response.statusCode == 200 ? '신고를 접수했어요.' : Msg.server),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AppBar(
        title: const Text('알바생 프로필'),
        actions: [
          IconButton(tooltip: '더보기', icon: const Icon(Icons.more_horiz_rounded), onPressed: _showMoreSheet),
        ],
      ),
      body:
          isLoading
              ? const AppSkeletonList(rows: 3, avatar: true)
              : profile == null
              ? AppEmptyState(
                icon: Icons.person_off_outlined,
                title: '프로필을 불러오지 못했어요',
                message: '잠시 후 다시 시도해 주세요.',
                actionLabel: '다시 시도',
                onAction: () {
                  setState(() => isLoading = true);
                  _fetchProfile(widget.workerId);
                },
              )
              : ListView(
                padding: EdgeInsets.only(bottom: 24 + MediaQuery.of(context).padding.bottom),
                children: [_header(), _resumeSection()],
              ),
    );
  }

  // 숫자 상자(신뢰도·채용 확정·근무 완료 세 칸)는 어느 앱에나 있는 틀이라 이 사람이 안 보였다(대표 10-30).
  // → 이름·등급 + 실제 기록 몇 줄(또 부르고 싶다는 사장님 수, 우리 앱에서 일한 횟수, 최근 접속)
  Widget _header() {
    final img = (profile!['profile_image_url'] ?? '').toString();
    final completed = int.tryParse('${profile!['completed_count'] ?? 0}') ?? 0;
    final good = int.tryParse('${profile!['eval_good'] ?? 0}') ?? 0;
    final facts = <(IconData, String)>[
      if (good > 0) (Icons.favorite_border_rounded, '사장님 $good명이 또 부르고 싶대요'),
      (Icons.work_outline_rounded, completed > 0 ? '알바일주에서 $completed번 일했어요' : '알바일주 첫 근무 전'),
      if (_lastActive() case final a?) (Icons.access_time_rounded, a),
    ];
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.bgMuted,
                backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
                child: img.isEmpty ? const Icon(Icons.person_rounded, size: 32, color: AppColors.textTertiary) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 지원한 사장님에겐 이미 공개된 이름 — 가리면 기계 같았다(토큰 없는 조회는 서버가 가린다)
                        Flexible(child: Text((profile!['name'] ?? '').toString(), style: AppTextStyles.h2)),
                        const SizedBox(width: 8),
                        AppGradeBadge(score: _activityScore),
                      ],
                    ),
                    if (_ageGender.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(_ageGender, style: AppTextStyles.body2),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final (icon, text) in facts)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(text, style: AppTextStyles.body1.copyWith(color: AppColors.textPrimary)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String? _lastActive() {
    final t = DateTime.tryParse('${profile!['last_active_at'] ?? ''}')?.toLocal();
    if (t == null) return null;
    final d = DateTime.now().difference(t).inDays;
    if (d <= 0) return '오늘 접속';
    if (d < 30) return '$d일 전 접속';
    return '한 달 넘게 접속 안 함';
  }

  Widget _section(String title, List<Widget> children) => Container(
    width: double.infinity,
    color: AppColors.bgCard,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(title, style: AppTextStyles.h3), ...children],
    ),
  );

  Widget _resumeSection() {
    String v(String k) => (profile![k] ?? '').toString().trim();
    final intro = v('introduction');
    // '물류,기타'처럼 쉼표 목록 — 칩으로 (시안 4번, 2026-11). 가능 시간만 문장이라 줄로 남긴다
    List<String> split(String k) =>
        v(k).replaceAll(RegExp(r'[\[\]"]'), '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty && e != 'null').toList();
    final days = split('available_days');
    final chipGroups = <(String, List<String>)>[
      ('희망하는 일', split('desired_work')),
      ('나의 강점', [...split('strengths'), ...split('traits')]),
    ].where((g) => g.$2.isNotEmpty).toList();
    final rows = <(String, String)>[
      ('가능 시간', v('available_times')),
    ].where((r) => r.$2.isNotEmpty).toList();
    final history = (profile!['work_history'] as List?) ?? const [];

    String md(String ymd) {
      final d = DateTime.tryParse(ymd);
      return d == null ? '' : '${d.month}월 ${d.day}일';
    }

    Widget chips(List<String> items) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(c, style: AppTextStyles.body2.copyWith(fontSize: AppFontSize.button, color: AppColors.textPrimary)),
          ),
      ],
    );
    const week = ['월', '화', '수', '목', '금', '토', '일'];

    return Column(
      children: [
        // 사장님이 고를 때 먼저 보는 것: 언제 되나 · 무슨 일 원하나 · 어떤 사람인가 (이력서 열람 동의 때만)
        if (canViewResume && (days.isNotEmpty || chipGroups.isNotEmpty))
          _section('이런 사람이에요', [
            if (days.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('가능한 요일', style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final d in week)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: days.any((x) => x.startsWith(d)) ? AppColors.primary : AppColors.bgMuted,
                        ),
                        child: Text(d,
                            style: AppTextStyles.body2.copyWith(
                              fontSize: AppFontSize.button,
                              fontWeight: FontWeight.w600,
                              color: days.any((x) => x.startsWith(d)) ? Colors.white : AppColors.textTertiary,
                            )),
                      ),
                    ),
                ],
              ),
            ],
            for (final (title, items) in chipGroups) ...[
              const SizedBox(height: 16),
              Text(title, style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              chips(items),
            ],
          ]),
        // 자기소개 — 이 화면에서 유일하게 본인 목소리가 들어가는 자리라 크게
        if (canViewResume && intro.isNotEmpty)
          _section('자기소개', [
            const SizedBox(height: 10),
            Text(intro, style: AppTextStyles.body1.copyWith(color: AppColors.textPrimary, height: 1.6)),
          ]),
        if (history.isNotEmpty)
          _section('알바일주에서 한 일', [
            for (final h in history)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (h['title'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(md((h['work_date'] ?? '').toString()), style: AppTextStyles.body2),
                  ],
                ),
              ),
          ]),
        if (!canViewResume)
          _section('이력서', [const SizedBox(height: 6), const Text('비공개', style: AppTextStyles.body2)])
        else if (rows.isNotEmpty || experiences.isNotEmpty || licenses.isNotEmpty)
          _section('이력서', [
            for (final r in rows) _infoRow(r.$1, r.$2),
            for (final e in experiences)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((e['place'] ?? '').toString(), style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    if ([e['duration'], e['description']].any((x) => (x ?? '').toString().trim().isNotEmpty))
                      Text(
                        [e['duration'], e['description']].where((x) => (x ?? '').toString().trim().isNotEmpty).join(', '),
                        style: AppTextStyles.body2,
                      ),
                  ],
                ),
              ),
            for (final l in licenses) _infoRow('자격증', [l['name'], l['issued_at']].where((x) => (x ?? '').toString().isNotEmpty).join(' ')),
          ]),
      ],
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 84, child: Text(label, style: AppTextStyles.body2)),
        Expanded(child: Text(value, style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary))),
      ],
    ),
  );
}
