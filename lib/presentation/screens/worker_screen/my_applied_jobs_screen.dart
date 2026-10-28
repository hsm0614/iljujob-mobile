// MyAppliedJobsScreen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:iljujob/widget/app_motion.dart';
import 'package:http/http.dart' as http;
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/widget/app_ui.dart';
import 'package:iljujob/utils/apply_stage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../../config/constants.dart';
import '../../../data/models/job.dart';
import '../../../data/services/authenticated_http_client.dart';
import '../../../data/services/screen_analytics_service.dart';
import 'job_detail_screen.dart';
import '../../chat/chat_room_screen.dart';
import 'package:iljujob/utils/pay_display.dart';
import '../../../config/messages.dart';
import '../../widgets/albailju_common.dart';

const kBrandBlue = AppColors.primary;

class MyAppliedJobsScreen extends StatefulWidget {
  /// 빈 화면 '공고 보러 가기' — 탭 안이라 pop 으로는 홈에 못 간다. 탭 컨테이너가 넘겨준다
  final VoidCallback? onGoHome;
  const MyAppliedJobsScreen({super.key, this.onGoHome});

  @override
  State<MyAppliedJobsScreen> createState() => _MyAppliedJobsScreenState();
}

class _MyAppliedJobsScreenState extends State<MyAppliedJobsScreen> {
  final Map<String, ApplyStage> _stageByJob = {};
  final Map<String, String> _replySpeedByJob = {};
  final Set<String> _reviewableJobs = {};
  ApplyStage _stage(Job j) =>
      _stageByJob['${j.id}'] ?? applyStageOf(jobStatus: j.status);

  // Tabs
  int _tabIndex = 0; // 0=지원현황, 1=찜한공고

  // Data
  List<Job> appliedJobs = [];
  List<Job> bookmarkedJobs = [];

  List<Job> filteredApplied = [];
  List<Job> filteredBookmarked = [];

  Set<String> hiddenJobIds = {}; // 로컬 숨김
  bool isLoading = true;
  // Filters
  String filterStatus =
      '전체'; // 전체 | todo | waiting | done (apply_stage.dart group)
  String searchQuery = '';

  // Review status
  Map<String, bool> reviewStatusMap = {};
  List<dynamic> _extractBookmarkList(dynamic decoded) {
    dynamic v = decoded;

    // 흔한 래핑 케이스들 처리
    if (v is Map) {
      v = v['data'] ?? v['result'] ?? v;
      if (v is Map) {
        v =
            v['bookmarks'] ??
            v['items'] ??
            v['results'] ??
            v['jobs'] ??
            v['list'] ??
            v;
      }
    }

    if (v is List) return v;
    return const [];
  }

  @override
  void initState() {
    super.initState();
    ScreenAnalyticsService.instance.logScreenView('worker_activity');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadHiddenIds();
      await _loadAll();
    });
  }

  Future<void> _loadAll() async {
    setState(() => isLoading = true);
    await Future.wait([_loadAppliedJobs(), _loadBookmarkedJobs()]);
    if (!mounted) return;
    _applyFilters();
    setState(() => isLoading = false);
  }

  Future<void> _loadHiddenIds() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('hiddenJobIds') ?? [];
    hiddenJobIds = stored.toSet();
  }

  Future<void> _saveHiddenIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hiddenJobIds', hiddenJobIds.toList());
  }

  Future<Job?> _fetchJobById(String jobId) async {
    final candidates = <Uri>[
      Uri.parse('$baseUrl/api/job/$jobId'),
      Uri.parse('$baseUrl/api/job/detail?jobId=$jobId'),
      Uri.parse('$baseUrl/api/job/get?jobId=$jobId'),
      Uri.parse('$baseUrl/api/job/get_job?jobId=$jobId'),
      Uri.parse('$baseUrl/api/job/job-detail?jobId=$jobId'),
    ];

    for (final uri in candidates) {
      try {
        final res = await AuthenticatedHttpClient.get(uri);
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          // 서버가 {job:{...}} / {...} 둘 다 가능하게
          final Map<String, dynamic>? map =
              (decoded is Map && decoded['job'] is Map)
                  ? Map<String, dynamic>.from(decoded['job'])
                  : (decoded is Map
                      ? Map<String, dynamic>.from(decoded)
                      : null);

          if (map != null && map.isNotEmpty) return Job.fromJson(map);
        }
      } catch (_) {}
    }
    return null;
  }

  // ---------------------------
  // Applied jobs
  // ---------------------------
  Future<void> _loadAppliedJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');

    if (workerId == null) {
      _showErrorSnackbar(Msg.loginExpired);
      appliedJobs = [];
      return;
    }

    // ✅ 너 기존 코드 그대로 유지 (endpoint 주의!)
    // 너는 위에서 /api/applications/my-jobs 를 쓰고 있는데
    // 다른 화면에서는 /api/apply/my-jobs 도 쓰더라. 프로젝트 기준에 맞춰 하나로 통일해.
    final url = Uri.parse(
      '$baseUrl/api/applications/my-jobs?workerId=$workerId',
    );

    try {
      final res = await AuthenticatedHttpClient.get(url);
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);

        final jobs = List<Job>.from(
          raw
              .map((item) => Job.fromJson(item))
              .where((job) => job.status != 'deleted'),
        );
        // 상태(답장 여부·출근확정)는 Job 모델 밖 값이라 따로 들고 있는다
        _stageByJob
          ..clear()
          ..addEntries(
            (raw as List).whereType<Map>().map(
              (r) => MapEntry(
                '${r['id']}',
                applyStageOf(
                  jobStatus: '${r['status'] ?? ''}',
                  workStatus: r['work_status'] as String?,
                  isConfirmed: '${r['is_confirmed']}' == '1',
                  isCompleted: '${r['is_completed']}' == '1',
                  clientReplied: '${r['client_replied']}' == '1',
                  appliedAt: DateTime.tryParse('${r['applied_at']}'),
                ),
              ),
            ),
          );
        // 후기는 사장님이 답했고 근무일이 지난 공고만 (서버 reviewController와 같은 기준)
        _reviewableJobs
          ..clear()
          ..addAll(
            raw.whereType<Map>().where(
              (r) =>
                  '${r['client_replied']}' == '1' &&
                  '${r['work_day_passed']}' == '1',
            ).map((r) => '${r['id']}'),
          );
        _replySpeedByJob.clear();
        for (final r in raw.whereType<Map>()) {
          int n(String k) => int.tryParse('${r[k] ?? 0}') ?? 0;
          final label = replySpeedLabel(
            n('client_reply_n'),
            n('client_reply_1h'),
            n('client_reply_24h'),
          );
          if (label != null) _replySpeedByJob['${r['id']}'] = label;
        }

        // 후기 여부 미리 로딩
        reviewStatusMap.clear();
        for (final job in jobs) {
          if (job.clientId == null) continue;
          final key = '${job.clientId}-${job.title}';
          reviewStatusMap[key] = await _checkIfReviewed(
            clientId: job.clientId!,
            jobTitle: job.title,
          );
        }

        appliedJobs = jobs;
      } else {
        appliedJobs = [];
      }
    } catch (_) {
      appliedJobs = [];
    }
  }

  Future<bool> _checkIfReviewed({
    required int clientId,
    required String jobTitle,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');
    if (workerId == null) return false;

    final encodedTitle = Uri.encodeComponent(jobTitle.trim());
    final url = Uri.parse(
      '$baseUrl/api/review/has-reviewed?clientId=$clientId&workerId=$workerId&jobTitle=$encodedTitle',
    );

    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['hasReviewed'] == true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _removeBookmark(Job job) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId');

      if (userId == null) {
        _showErrorSnackbar(Msg.loginExpired);
        return;
      }

      final uri = Uri.parse('$baseUrl/api/bookmark/remove');
      final res = await AuthenticatedHttpClient.postJson(
        uri,
        body: {'userId': userId, 'jobId': job.id},
      );

      if (res.statusCode == 200) {
        bookmarkedJobs.removeWhere((j) => j.id == job.id);
        _applyFilters();

        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('관심 공고에서 뺐어요.')));
      } else {
        debugPrint('찜 해제 실패 (${res.statusCode})');
        _showErrorSnackbar(Msg.bookmarkFailed);
      }
    } catch (e) {
      debugPrint('찜 해제 중 오류가 발생했습니다: $e');
      _showErrorSnackbar(Msg.bookmarkFailed);
    }
  }

  Future<void> _loadBookmarkedJobs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId');

      if (userId == null) {
        bookmarkedJobs = [];
        return;
      }

      final candidates = <Uri>[
        Uri.parse('$baseUrl/api/bookmark/list?userId=$userId'),
        Uri.parse('$baseUrl/api/bookmark/list?workerId=$userId'),
        Uri.parse('$baseUrl/api/bookmark/list?worker_id=$userId'),
      ];

      http.Response? resp200;
      for (final uri in candidates) {
        final r = await AuthenticatedHttpClient.get(uri);
        if (r.statusCode == 200) {
          resp200 = r;
          break;
        }
      }

      if (resp200 == null) {
        bookmarkedJobs = [];
        return;
      }

      final decoded = jsonDecode(resp200.body);
      final list = _extractBookmarkList(decoded);

      List<Job> jobs = [];

      // ✅ 1) 공고 객체가 바로 오는 경우
      if (list.isNotEmpty && list.first is Map) {
        final maps =
            list
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
        jobs = maps.map((m) => Job.fromJson(m)).toList();
      }
      // ✅ 2) jobId만 오는 경우 -> 상세 조회로 Job 리스트 만들기
      else if (list.isNotEmpty && (list.first is String || list.first is num)) {
        final ids = list.map((e) => e.toString()).toList();

        // 병렬로 가져오기 (수량 적으니 OK)
        final fetched = await Future.wait(ids.map((id) => _fetchJobById(id)));
        jobs = fetched.whereType<Job>().toList();
      }

      // ✅ UI가 보는 리스트에 넣기
      bookmarkedJobs = jobs;
    } catch (e, st) {
      debugPrint('❌ _loadBookmarkedJobs error: $e\n$st');
      bookmarkedJobs = [];
    }
  }

  // ---------------------------
  // Bookmarked jobs (찜한 공고)
  // ---------------------------

  // ---------------------------
  // Filters
  // ---------------------------
  void _applyFilters() {
    List<Job> a = appliedJobs;
    List<Job> b = bookmarkedJobs;

    // 로컬 숨김
    a = a.where((j) => !hiddenJobIds.contains(j.id)).toList();
    b = b.where((j) => !hiddenJobIds.contains(j.id)).toList();

    // ✅ 지원현황: deleted 숨김 유지
    a = a.where((j) => j.status != 'deleted').toList();

    // ✅ 찜탭: 삭제된 공고는 숨기고 저장한 공고만 보여주기
    b = b.where((j) => j.status != 'deleted').toList();

    // ✅ 진행 필터: 지원현황 탭에서만 적용
    if (filterStatus != '전체') {
      a = a.where((j) => _matchesActivityFilter(j, filterStatus)).toList();
    }

    // 검색(둘 다 적용)
    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim();
      a =
          a
              .where((j) => j.title.contains(q) || j.location.contains(q))
              .toList();
      b =
          b
              .where((j) => j.title.contains(q) || j.location.contains(q))
              .toList();
    }

    if (!mounted) return;
    setState(() {
      filteredApplied = a;
      filteredBookmarked = b; // ✅ 이제 deleted만 들어감
    });
  }

  // ---------------------------
  // Actions
  // ---------------------------
  void _showErrorSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 더보기 (2026-10): 빨간 아이콘 목록 → 공고 이름 + 글자 줄.
  /// 숨기기는 되돌리기 스낵바가 있어 확인 창 없이 바로 (메뉴→확인→되돌리기 3단계였다)
  void _showCardActions(Job job) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    job.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body2,
                  ),
                ),
                AppMenuRow(
                  label: '목록에서 숨기기',
                  subtitle: '이 기기에서만 안 보여요',
                  trailing: const SizedBox.shrink(),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _hide(job.id);
                  },
                ),
                if (job.status == 'active')
                  InkWell(
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _confirmCancel(job);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Text(
                        '지원 취소',
                        style: AppTextStyles.body1.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  Future<void> _hide(String jobId) async {
    hiddenJobIds.add(jobId);
    await _saveHiddenIds();
    _applyFilters();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('목록에서 숨겼어요.'),
        action: SnackBarAction(
          label: '되돌리기',
          onPressed: () async {
            hiddenJobIds.remove(jobId);
            await _saveHiddenIds();
            _applyFilters();
          },
        ),
      ),
    );
  }

  Future<void> _confirmCancel(Job job) async {
    final confirmed = await showAppSheet(
      context,
      title: '이 공고 지원을 취소할까요?',
      message: '취소한 지원은 되돌릴 수 없어요. 다시 하려면 새로 지원해야 해요.',
      confirmLabel: '지원 취소',
      cancelLabel: '닫기',
      destructive: true,
    );

    if (confirmed == true) {
      await _cancelApplication(job);
    }
  }

  Future<void> _cancelApplication(Job job) async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');

    if (workerId == null) {
      _showErrorSnackbar(Msg.loginExpired);
      return;
    }

    final uri = Uri.parse('$baseUrl/api/applications/cancel');

    try {
      final res = await AuthenticatedHttpClient.postJson(
        uri,
        body: {'jobId': job.id, 'workerId': workerId},
      );

      if (res.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('지원을 취소했어요.')));
        await _loadAppliedJobs();
        _applyFilters();
      } else {
        debugPrint('지원 취소 실패 (${res.statusCode})');
        _showErrorSnackbar(Msg.applyCancelFailed);
      }
    } catch (e) {
      debugPrint('지원 취소 중 오류가 발생했습니다: $e');
      _showErrorSnackbar(Msg.applyCancelFailed);
    }
  }

  Future<void> _openChatRoom(Job job) async {
    final uri = Uri.parse(
      '$baseUrl/api/chat/get-room-by-id?jobId=${job.id}&workerId=${job.workerId}',
    );

    try {
      final res = await AuthenticatedHttpClient.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final chatRoomId = data['chatRoomId'];
        final jobInfo = Map<String, dynamic>.from(data['jobInfo']);

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => ChatRoomScreen(chatRoomId: chatRoomId, jobInfo: jobInfo),
          ),
        );
      } else {
        debugPrint('채팅방 정보 요청 실패 (${res.statusCode})');
        _showErrorSnackbar(Msg.chatCreateFailed);
      }
    } catch (e) {
      debugPrint('네트워크 오류: $e');
      _showErrorSnackbar(Msg.network);
    }
  }

  // ---------------------------
  // UI bits (스샷 톤)
  // ---------------------------
  Widget _headerSearch() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Colors.white,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.bgMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: TextField(
          onChanged: (v) {
            searchQuery = v;
            _applyFilters();
          },
          decoration: const InputDecoration(
            prefixIcon: Icon(
              Icons.search_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
            hintText: '제목 또는 지역으로 검색',
            hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: AppFontSize.button),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            isDense: true,
          ),
        ),
      ),
    );
  }

  Widget _topTabs() {
    Widget tabItem({
      required int idx,
      required String title,
      required int count,
    }) {
      final selected = _tabIndex == idx;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tabIndex = idx),
          child: SizedBox(
            height: 48,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppFontSize.button,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color:
                            selected
                                ? AppColors.textPrimary
                                : AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 5),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? kBrandBlue : AppColors.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700,
                          color:
                              selected ? Colors.white : AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 3,
                  width: double.infinity,
                  color: selected ? kBrandBlue : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            tabItem(idx: 0, title: '지원 현황', count: filteredApplied.length),
            tabItem(idx: 1, title: '관심 공고', count: filteredBookmarked.length),
          ],
        ),
        Container(height: 1, color: AppColors.border),
      ],
    );
  }

  /// 상태 묶음 칩: 전체 · 할 일 · 답장 대기 · 지난 지원 (개수 함께). 할 일이 있으면 그게 먼저 보인다
  Widget _statusChips() {
    Widget chip(String key, String label) {
      final selected = filterStatus == key;
      final n = _activityCount(key);
      return Material(
        color: selected ? AppColors.primaryLight : AppColors.bgMuted,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.full),
          onTap: () {
            setState(() => filterStatus = key);
            _applyFilters();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              '$label $n',
              style: AppTextStyles.captionBold.copyWith(
                fontSize: AppFontSize.body2,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 6,
          children: [
            chip('전체', '전체'),
            chip('todo', '할 일'),
            chip('waiting', '답장 대기'),
            chip('done', '지난 지원'),
          ],
        ),
      ),
    );
  }

  bool _matchesActivityFilter(Job job, String key) =>
      key == '전체' || _stage(job).group == key;

  int _activityCount(String key) =>
      appliedJobs
          .where((job) => job.status != 'deleted')
          .where((job) => _matchesActivityFilter(job, key))
          .length;

  Widget _emptyView({required bool forBookmark}) {
    return AppEmptyState(
      icon:
          forBookmark
              ? Icons.favorite_border_rounded
              : Icons.work_outline_rounded,
      title: forBookmark ? '관심 공고가 아직 없어요' : '아직 지원한 알바가 없어요',
      message:
          forBookmark
              ? '마음에 드는 공고를 하트로 저장해두면\n나중에 빠르게 다시 볼 수 있어요.'
              : '지금 바로 동네 알바를 찾아볼까요?',
      actionLabel: '공고 보러 가기',
      // 예전엔 popUntil(isFirst)였는데 탭 안이라 아무 일도 안 일어났다
      onAction:
          widget.onGoHome ??
          () => Navigator.popUntil(context, (r) => r.isFirst),
    );
  }

  Widget _jobRow(Job job, {required bool bookmarkedTab, bool last = false}) {
    final reviewKey = '${job.clientId}-${job.title}';
    final reviewed = reviewStatusMap[reviewKey] == true;
    final isDeleted = job.status == 'deleted';
    // 지원일은 applications.created_at(=applied_at). 공고 생성일(job.createdAt)을
    // 쓰면 "3일 전에 올라온 공고에 오늘 지원"이 "지원일 3일 전"으로 표시된다.
    final appliedDate = job.appliedAt ?? job.createdAt;
    final fmt = DateFormat('MM.dd');
    final start = job.startDate != null ? fmt.format(job.startDate!) : '';
    final end = job.endDate != null ? fmt.format(job.endDate!) : '';
    // 하루짜리는 '06.09 ~ 06.09' 대신 '06.09', 날짜 없는 장기는 요일
    final period =
        start.isEmpty
            ? (formatWeekdays(job.weekdays) ?? '')
            : (end.isEmpty || end == start ? start : '$start ~ $end');
    final hours =
        job.workingHours.replaceAll('~', '').trim().isEmpty
            ? ''
            : job.workingHours;
    final meta = [
      if (period.isNotEmpty) period,
      if (hours.isNotEmpty) hours,
      if (!bookmarkedTab && appliedDate != null)
        '${fmt.format(appliedDate.toLocal())} 지원',
    ].join(' · ');

    final stage = _stage(job);
    final company = (job.company ?? '').trim();
    final head =
        company.isNotEmpty
            ? company
            : job.location.split(RegExp(r'\s+')).take(3).join(' ');
    final done = !bookmarkedTab && stage.group == 'done';
    final replySpeed =
        bookmarkedTab || stage.group != 'waiting'
            ? null
            : _replySpeedByJob['${job.id}'];
    final negotiable = isNegotiablePayType(job.payType);

    return InkWell(
      onTap:
          (bookmarkedTab && isDeleted)
              ? null
              : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
                );
              },
      child: Opacity(
        opacity: (bookmarkedTab && isDeleted) ? 0.55 : 1.0,
        // 홈 목록과 같은 흰 줄 + 아래 구분선 (마지막 줄 뒤엔 없음)
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            border:
                last
                    ? null
                    : const Border(
                      bottom: BorderSide(color: AppColors.borderSub),
                    ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 회사(없으면 시·구) · 오른쪽에 지금 상태
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            head,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.jobMeta,
                          ),
                        ),
                        if (!bookmarkedTab) ...[
                          const SizedBox(width: 8),
                          Text(
                            stage.label,
                            style: AppTextStyles.captionBold.copyWith(
                              color: stage.color,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      job.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.jobTitle.copyWith(
                        color: done ? AppColors.textSecondary : null,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(meta, style: AppTextStyles.jobMeta),
                    ],
                    if (job.pay.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: formatJobPay(job.pay, job.payType),
                              style:
                                  negotiable
                                      ? AppTextStyles.body2.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary,
                                      )
                                      : AppTextStyles.body1.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                            ),
                            if (!negotiable && job.payType.isNotEmpty)
                              TextSpan(
                                text: ' ${job.payType}',
                                style: AppTextStyles.jobMeta,
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (replySpeed != null) ...[
                      const SizedBox(height: 6),
                      Text(replySpeed, style: AppTextStyles.caption),
                    ],

                    // 지금 해야 할 일 — 상태와 같은 기준(apply_stage.dart)
                    if (!bookmarkedTab && stage.next != null) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap:
                            stage == ApplyStage.waitingLong
                                ? widget.onGoHome
                                : () => _openChatRoom(job),
                        child: Text(
                          '${stage.next} ›',
                          style: AppTextStyles.captionBold.copyWith(
                            fontSize: AppFontSize.body2,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                    // 끝난 지원 중 사장님과 이야기했고 근무일이 지난 것만 후기 (지원 취소·숨기기는 ⋯ 더보기).
                    // 작성한 후기는 기준과 상관없이 '작성 완료'로 보여준다
                    if (done &&
                        (reviewed || _reviewableJobs.contains('${job.id}'))) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap:
                            reviewed
                                ? null
                                : () => Navigator.pushNamed(
                                  context,
                                  '/review',
                                  arguments: {
                                    'jobId': job.id,
                                    'clientId': job.clientId,
                                    'jobTitle': job.title,
                                    'companyName': job.company,
                                  },
                                ),
                        child: Text(
                          reviewed ? '후기 작성 완료' : '후기 남기기 ›',
                          style: AppTextStyles.captionBold.copyWith(
                            fontSize: AppFontSize.body2,
                            color:
                                reviewed
                                    ? AppColors.textTertiary
                                    : AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (job.imageUrls.isNotEmpty) ...[
                const SizedBox(width: 12),
                _thumb(job),
              ],

              // 오른쪽 아이콘 (채팅 · 더보기 / 관심 해제)
              const SizedBox(width: 4),
              Column(
                children: [
                  if (bookmarkedTab)
                    IconButton(
                      icon: const Icon(Icons.favorite_rounded, size: 22),
                      color: AppColors.badgeNew,
                      tooltip: '관심 해제',
                      onPressed: () => _removeBookmark(job),
                    )
                  else ...[
                    IconButton(
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 20,
                      ),
                      color: AppColors.textSecondary,
                      tooltip: '채팅하기',
                      onPressed: () => _openChatRoom(job),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_horiz_rounded, size: 22),
                      color: AppColors.textTertiary,
                      tooltip: '더보기',
                      onPressed: () => _showCardActions(job),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 실제 이미지가 있을 때만
  Widget _thumb(Job job) {
    final raw = job.imageUrls.first;
    final url = raw.startsWith('http') ? raw : '$baseUrl$raw';
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Image.network(
        url,
        width: 64,
        height: 64,
        cacheWidth: 192,
        fit: BoxFit.cover,
        errorBuilder:
            (_, __, ___) =>
                Container(width: 64, height: 64, color: AppColors.bgMuted),
      ),
    );
  }

  // ---------------------------
  // Build
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final list = _tabIndex == 0 ? filteredApplied : filteredBookmarked;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.bgPage,
        appBar: AlbailjuAppBar(
          title: '내 활동',
          brand: true,
          actions: [
            IconButton(
              tooltip: '새로고침',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loadAll,
            ),
            const SizedBox(width: 6),
          ],
        ),
        body:
            isLoading
                ? const AppSkeletonList()
                : Column(
                  children: [
                    // 지원 0건이면 검색창·'0'짜리 칩 없이 빈 화면 안내만 (평가 2026-10)
                    if (appliedJobs.isNotEmpty || bookmarkedJobs.isNotEmpty)
                      _headerSearch(),
                    _topTabs(),
                    if (_tabIndex == 0 && appliedJobs.isNotEmpty) ...[
                      _statusChips(),
                    ] else
                      const SizedBox(height: 12),
                    Expanded(
                      child:
                          list.isEmpty
                              ? _emptyView(forBookmark: _tabIndex == 1)
                              : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 24),
                                itemCount: list.length,
                                itemBuilder:
                                    (context, i) => AppFadeSlideIn(
                                      key: ValueKey(
                                        'act_${_tabIndex}_${list[i].id}',
                                      ),
                                      index: i,
                                      child: _jobRow(
                                        list[i],
                                        bookmarkedTab: _tabIndex == 1,
                                        last: i == list.length - 1,
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
