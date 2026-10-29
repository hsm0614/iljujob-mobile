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
  String _activityGrade = 'NEW';

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

  String maskName(String name) {
    if (name.isEmpty) return name;
    if (name.length == 2) {
      return '${name[0]}*';
    } else if (name.length > 2) {
      return name[0] + '*' * (name.length - 2) + name[name.length - 1];
    } else {
      return name; // 한 글자인 경우 그대로
    }
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
        _activityGrade = (r[3]['grade'] ?? 'NEW').toString();
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

  void _showReportDialog(String targetType, int targetId) {
    final TextEditingController reasonController = TextEditingController();
    String? selectedReason;

    final List<String> reasonOptions = [
      '음란물 또는 불쾌한 콘텐츠',
      '폭력성 또는 위협적인 언행',
      '욕설/혐오 발언/차별',
      '허위 정보 또는 사기 의심',
      '기타',
    ];

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('사용자 신고'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  items:
                      reasonOptions
                          .map(
                            (reason) => DropdownMenuItem<String>(
                              value: reason,
                              child: Text(reason),
                            ),
                          )
                          .toList(),
                  initialValue: selectedReason,
                  onChanged: (value) {
                    selectedReason = value;
                  },
                  decoration: const InputDecoration(
                    labelText: '신고 사유',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: '상세 내용을 입력해주세요 (선택)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '※ 신고된 내용은 운영 정책에 따라 24시간 이내에 조치됩니다.',
                  style: TextStyle(fontSize: AppFontSize.meta, color: AppColors.textSecondary),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedReason == null || selectedReason!.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('신고 사유를 선택해주세요')),
                    );
                    return;
                  }

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
                      'reasonCategory': selectedReason,
                      'reasonDetail': reasonController.text.trim(),
                    },
                  );

                  Navigator.pop(context);

                  if (response.statusCode == 200) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('신고를 접수했어요.')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(Msg.server)),
                    );
                  }
                },
                child: const Text('신고'),
              ),
            ],
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
                children: [
                  _header(),
                  const SizedBox(height: 8),
                  _resumeSection(),
                ],
              ),
    );
  }

  // 사진·이름·나이 → 신뢰 숫자 세 칸. 예전엔 네모 상자 4개(알바온도 점수와 활동등급이 따로)였다
  Widget _header() {
    final img = (profile!['profile_image_url'] ?? '').toString();
    Widget cell(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(value, style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.body2),
        ],
      ),
    );
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
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
                    Text(maskName((profile!['name'] ?? '').toString()), style: AppTextStyles.h2),
                    if (_ageGender.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(_ageGender, style: AppTextStyles.body2),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: AppColors.bgMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(
              children: [
                cell('신뢰도', '$_activityGrade · $_activityScore점'),
                cell('채용 확정', '${profile!['confirmed_count'] ?? 0}번'),
                cell('근무 완료', '${profile!['completed_count'] ?? 0}번'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 이력서: 동의 안 했으면 한 줄, 했으면 채운 칸만 ('없음'이 줄줄이 찍히던 것)
  Widget _resumeSection() {
    if (!canViewResume) {
      return Container(
        color: AppColors.bgCard,
        padding: const EdgeInsets.all(20),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('이력서', style: AppTextStyles.h3),
            SizedBox(height: 6),
            Text('이 알바생은 이력서를 공개하지 않았어요 · 경력은 채팅으로 물어봐 주세요', style: AppTextStyles.body2),
          ],
        ),
      );
    }
    String v(String k) => (profile![k] ?? '').toString().trim();
    final rows = <(String, String)>[
      ('강점', v('strengths')),
      ('성격', v('traits')),
      ('희망 업무', v('desired_work')),
      ('가능 요일', v('available_days')),
      ('가능 시간', v('available_times')),
    ].where((r) => r.$2.isNotEmpty).toList();
    final intro = v('introduction');
    final empty = rows.isEmpty && intro.isEmpty && experiences.isEmpty && licenses.isEmpty;

    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('이력서', style: AppTextStyles.h3),
          if (empty) ...[
            const SizedBox(height: 6),
            const Text('아직 이력서를 채우지 않았어요', style: AppTextStyles.body2),
          ],
          if (intro.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(intro, style: AppTextStyles.body1.copyWith(color: AppColors.textPrimary, height: 1.5)),
          ],
          for (final r in rows) _infoRow(r.$1, r.$2),
          if (experiences.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('경력', style: AppTextStyles.body1),
            // 가게 이름이 길어 라벨 칸(84)에 안 들어간다 — 이름 위, 기간·내용 아래 두 줄
            for (final e in experiences)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((e['place'] ?? '').toString(), style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    Text(
                      [e['duration'], e['description']].where((x) => (x ?? '').toString().trim().isNotEmpty).join(' · '),
                      style: AppTextStyles.body2,
                    ),
                  ],
                ),
              ),
          ],
          if (licenses.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('자격·면허', style: AppTextStyles.body1),
            for (final l in licenses) _infoRow((l['name'] ?? '').toString(), (l['issued_at'] ?? '').toString()),
          ],
        ],
      ),
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
