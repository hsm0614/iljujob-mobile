// 📁 presentation/screens/applicant_list_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';
import '../../../config/messages.dart';
import '../../../config/app_theme.dart';
import '../../../widget/app_ui.dart';

class ApplicantListScreen extends StatefulWidget {
  const ApplicantListScreen({super.key});

  @override
  State<ApplicantListScreen> createState() => _ApplicantListScreenState();
}

class _ApplicantListScreenState extends State<ApplicantListScreen> {
  final List<dynamic> applicants = [];
  bool isLoading = true;
  bool _aiSorted = false; // AI 정렬 여부
  String? jobId;


  String formatDate(String isoDate) {
    try {
      return DateFormat('yyyy.MM.dd').format(DateTime.parse(isoDate).toLocal());
    } catch (_) {
      return isoDate;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args != null && jobId == null) {
      jobId = args.toString();
      _loadApplicants(jobId!);
    }
  }

  Future<void> _loadApplicants(String jobId) async {
    setState(() => isLoading = true);
    try {
      final uri = Uri.parse('$baseUrl/api/apply/applicants?jobId=$jobId');
      final response = await AuthenticatedHttpClient.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['applicants'] ?? [];

        // AI 스코어 있는지 확인
        final hasAiScore = list.any((a) => a['ai_score'] != null);

        setState(() {
          applicants
            ..clear()
            ..addAll(list);
          _aiSorted = hasAiScore;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        debugPrint('지원자 정보 조회 실패 (${response.statusCode})');
        _showSnackbar(Msg.applicantLoadFailed);
      }
    } on AuthSessionExpiredException {
      setState(() => isLoading = false);
      _showSnackbar(Msg.loginRequired);
      if (mounted) Navigator.pushNamed(context, '/login');
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackbar(Msg.network);
    }
  }

  Future<void> _goToChatRoom(int workerId) async {
    if (jobId == null) return;
    final getUri = Uri.parse(
      '$baseUrl/api/chat/get-room-by-id?jobId=$jobId&workerId=$workerId',
    );
    try {
      int? chatRoomId;
      Map<String, dynamic>? jobInfo;

      final getRes = await AuthenticatedHttpClient.get(getUri);
      if (getRes.statusCode == 200) {
        final data = jsonDecode(getRes.body);
        chatRoomId = data['chatRoomId'] as int?;
        jobInfo = (data['jobInfo'] as Map?)?.cast<String, dynamic>();
      } else if (getRes.statusCode == 404) {
        final startRes = await AuthenticatedHttpClient.postJson(
          Uri.parse('$baseUrl/api/chat/start'),
          body: {'jobId': jobId, 'workerId': workerId},
        );
        if (startRes.statusCode == 200) {
          final data = jsonDecode(startRes.body);
          chatRoomId = data['chatRoomId'] as int?;
          jobInfo = (data['jobInfo'] as Map?)?.cast<String, dynamic>();
        } else {
          _showSnackbar('채팅방 생성에 실패했어요.');
          return;
        }
      }

      if (chatRoomId == null || !mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => ChatRoomScreen(
                chatRoomId: chatRoomId!,
                jobInfo: {...?jobInfo, 'worker_id': workerId},
              ),
        ),
      );
    } on AuthSessionExpiredException {
      _showSnackbar(Msg.loginRequired);
      if (mounted) Navigator.pushNamed(context, '/login');
    } catch (e) {
      _showSnackbar(Msg.network);
    }
  }

  void _showSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.fixed),
    );
  }

  // AI 이유 → 사람 말 (홈 공고 카드 AI 요약과 같은 표기, test/ai_summary_test.dart)
  static const _reasonLabel = {
    '가까움': '가까워요',
    '시간대겹침': '시간대가 맞아요',
    '시급상위': '시급이 높아요',
    '완료이력좋음': '근무 이력이 좋아요',
    '의미유사': '업무가 잘 맞아요',
  };

  String _timeAgo(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)}분 전';
    if (d.inHours < 24) return '${d.inHours}시간 전';
    if (d.inDays < 7) return '${d.inDays}일 전';
    return formatDate(iso);
  }

  // 지원자 관리와 같은 행·같은 버튼 (2026-10). 예전엔 가린 이름 옆에 실명을 괄호로 같이 찍고,
  // 이모지 칩·매칭률 막대·순위 원이 붙어 있었다.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AppBar(title: Text(applicants.isEmpty ? '지원자' : '지원자 ${applicants.length}명')),
      body:
          isLoading
              ? const AppSkeletonList(avatar: true)
              : applicants.isEmpty
              ? const AppEmptyState(
                icon: Icons.people_alt_outlined,
                title: '아직 지원자가 없어요',
                message: '지원이 오면 알림으로 알려드릴게요',
              )
              : RefreshIndicator(
                onRefresh: () => _loadApplicants(jobId!),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (_aiSorted)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
                        child: Text('이 공고와 잘 맞는 순서로 보여드려요', style: AppTextStyles.body2),
                      ),
                    Container(
                      color: AppColors.bgCard,
                      child: Column(
                        children: [
                          for (final a in applicants)
                            if (int.tryParse('${a['worker_id']}') case final id?) _row(a, id),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _row(dynamic a, int workerId) {
    final name = (a['name'] ?? '이름 비공개').toString();
    final img = (a['profile_image_url'] ?? '').toString();
    final by = int.tryParse('${a['birth_year'] ?? ''}'.padRight(4).substring(0, 4).trim());
    final g = a['gender'];
    final confirmed = a['is_confirmed'] == 1 || a['is_confirmed'] == true;
    final completed = a['is_completed'] == 1 || a['is_completed'] == true;
    final score = double.tryParse('${a['ai_score'] ?? ''}');
    final dist = double.tryParse('${a['dist_km'] ?? ''}');
    final reasons = [
      for (final r in ((a['ai_reasons'] as List?) ?? []).take(2))
        if (_reasonLabel[r] case final l?) r == '가까움' && dist != null ? '$l (${dist < 1 ? '${(dist * 1000).round()}m' : '${dist.toStringAsFixed(1)}km'})' : l,
    ];
    final meta = [
      if (by != null && by > 1900) '${DateTime.now().year - by}세',
      if (g == 'male') '남' else if (g == 'female') '여',
      '${_timeAgo((a['created_at'] ?? '').toString())} 지원',
    ].where((x) => x.trim().isNotEmpty).join(' · ');
    // 퍼센트는 0.7 이상일 때만 — 낮은 점수를 숫자로 보이면 오히려 깎아내린다(홈 AI 요약과 같은 규칙)
    final fit = [
      if (score != null && score >= 0.7) '${(score * 100).round()}% 맞음',
      ...reasons,
    ].join(' · ');

    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/worker-profile', arguments: workerId),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.bgMuted,
              backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
              child: img.isEmpty
                  ? Text(name.isNotEmpty ? name[0] : '?', style: AppTextStyles.body1.copyWith(color: AppColors.textSecondary))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AppGradeBadge(score: int.tryParse('${a['activity_score'] ?? 0}') ?? 0),
                      if (completed || confirmed) ...[
                        const SizedBox(width: 4),
                        JobSignalBadge(label: completed ? '근무 완료' : '출근 확정', signal: JobSignal.trust),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(meta, style: AppTextStyles.body2),
                  if (fit.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(fit, style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child:
                  confirmed || completed
                      ? OutlinedButton(style: _rowBtn, onPressed: () => _goToChatRoom(workerId), child: const Text('채팅'))
                      : ElevatedButton(style: _rowBtn, onPressed: () => _goToChatRoom(workerId), child: const Text('채팅')),
            ),
          ],
        ),
      ),
    );
  }

  static final ButtonStyle _rowBtn = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(64, 38)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
    textStyle: WidgetStatePropertyAll(AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600)),
  );
}
