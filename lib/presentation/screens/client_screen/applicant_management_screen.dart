// lib/presentation/screens/applicant_management_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:iljujob/widget/app_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/constants.dart';
import '../../../data/services/authenticated_http_client.dart';
import '../../../data/services/screen_analytics_service.dart';
import '../../chat/chat_room_screen.dart'; // 경로 맞게 수정
import '../../widgets/albailju_common.dart';
import '../../../config/app_theme.dart';
import '../../../config/messages.dart';
import '../../../utils/pay_display.dart';

// ─── 모델 ────────────────────────────────────────────────────────

class ApplicantModel {
  final int applicationId;
  final DateTime appliedAt;
  final bool isConfirmed;
  final bool isCompleted;
  final int workerId;
  final String workerName;
  final String workerPhoneMasked;
  final String? profileImageUrl;
  final int? birthYear;
  final String? gender;
  final int? activityScore;

  /// 구직자가 지원을 취소한 건. 목록에서 지우지 않고 회색으로 남긴다 —
  /// 조용히 사라지면 사장님은 지원자가 왔다 간 사실 자체를 모른다.
  final bool isCanceled;
  final DateTime? canceledAt;

  ApplicantModel({
    required this.applicationId,
    required this.appliedAt,
    required this.isConfirmed,
    required this.isCompleted,
    required this.workerId,
    required this.workerName,
    required this.workerPhoneMasked,
    this.profileImageUrl,
    this.birthYear,
    this.gender,
    this.activityScore,
    this.isCanceled = false,
    this.canceledAt,
  });

  factory ApplicantModel.fromJson(Map<String, dynamic> j) {
    return ApplicantModel(
      applicationId: j['application_id'] ?? 0,
      appliedAt: DateTime.tryParse(j['applied_at'] ?? '') ?? DateTime.now(),
      isConfirmed: j['is_confirmed'] == true || j['is_confirmed'] == 1,
      isCompleted: j['is_completed'] == true || j['is_completed'] == 1,
      workerId: j['worker_id'] ?? 0,
      workerName: j['worker_name'] ?? '이름 없음',
      workerPhoneMasked: j['worker_phone_masked']?.toString() ?? '',
      profileImageUrl: j['profile_image_url'],
      birthYear:
          j['birth_year'] != null ? int.tryParse('${j['birth_year']}') : null,
      gender: j['gender'],
      activityScore:
          j['activity_score'] != null
              ? int.tryParse('${j['activity_score']}') ?? 0
              : 0,
      isCanceled: j['is_canceled'] == true || j['is_canceled'] == 1,
      canceledAt:
          j['canceled_at'] != null
              ? DateTime.tryParse('${j['canceled_at']}')
              : null,
    );
  }

  int get safeActivityScore => activityScore ?? 0;

  String get activityGrade {
    final score = safeActivityScore;
    if (score >= 100) return 'S';
    if (score >= 70) return 'A';
    if (score >= 40) return 'B';
    if (score >= 20) return 'C';
    return 'NEW';
  }

  bool get isNew => !isConfirmed && !isCanceled;
  int get age => birthYear != null ? DateTime.now().year - birthYear! : 0;
  String get genderLabel =>
      gender == 'male'
          ? '남'
          : gender == 'female'
          ? '여'
          : '';

  String get statusLabel {
    if (isCanceled) return '지원 취소';
    if (isCompleted) return '근무 완료';
    if (isConfirmed) return '출근 확정';
    return '처리 필요';
  }

  String get actionLabel {
    if (isCompleted) return '완료 확인';
    if (isConfirmed) return '확정 확인';
    return '채팅하기';
  }

  int get sortWeight {
    if (isCanceled) return 4; // 취소는 항상 맨 아래
    if (isCompleted) return 3;
    if (isConfirmed) return 2;
    return 1;
  }
}

class JobApplicantGroup {
  final int jobId;
  final String jobTitle;
  final String? locationCity;
  final String? startDate;
  final String jobStatus;
  final List<ApplicantModel> applicants;

  JobApplicantGroup({
    required this.jobId,
    required this.jobTitle,
    this.locationCity,
    this.startDate,
    required this.jobStatus,
    required this.applicants,
  });

  factory JobApplicantGroup.fromJson(Map<String, dynamic> j) {
    final list =
        (j['applicants'] as List? ?? [])
            .map((a) => ApplicantModel.fromJson(a))
            .toList();
    list.sort((a, b) {
      final byStatus = a.sortWeight.compareTo(b.sortWeight);
      if (byStatus != 0) return byStatus;
      return b.appliedAt.compareTo(a.appliedAt);
    });
    return JobApplicantGroup(
      jobId: j['job_id'] ?? 0,
      jobTitle: j['job_title'] ?? '공고 없음',
      locationCity: j['location_city'],
      startDate: j['start_date'],
      jobStatus: j['job_status'] ?? '',
      applicants: list,
    );
  }

  /// 취소를 뺀 지원자. 모든 숫자는 이걸 기준으로 센다 —
  /// '3명'에 취소가 섞이면 사장님이 채용 가능 인원을 잘못 읽는다.
  List<ApplicantModel> get activeApplicants =>
      applicants.where((a) => !a.isCanceled).toList();

  int get newCount => activeApplicants.where((a) => a.isNew).length;
  int get pendingCount =>
      activeApplicants.where((a) => !a.isConfirmed && !a.isCompleted).length;
  int get confirmedCount =>
      activeApplicants.where((a) => a.isConfirmed && !a.isCompleted).length;
  int get canceledCount => applicants.length - activeApplicants.length;
}

// ─── 상수 ────────────────────────────────────────────────────────
const int _jobsPerPage = 5;
const int _applicantsPreview = 3;

// ─── 화면 ────────────────────────────────────────────────────────

class ApplicantManagementScreen extends StatefulWidget {
  const ApplicantManagementScreen({super.key});

  @override
  State<ApplicantManagementScreen> createState() =>
      _ApplicantManagementScreenState();
}

class _ApplicantManagementScreenState extends State<ApplicantManagementScreen> {
  bool _loading = true;
  bool _bulkSending = false;
  String? _error;
  List<JobApplicantGroup> _groups = [];
  int _totalCount = 0;
  int _currentPage = 1;
  final Map<int, bool> _expanded = {};
  final Map<int, Set<int>> _selectedByJob = {};
  /// 여러 명에게 메시지 — 선택 중인 공고(한 번에 하나)
  int? _selectingJob;
  final Map<int, String> _visiblePhones = {};
  final Set<int> _phoneLoading = {};

  @override
  void initState() {
    super.initState();
    ScreenAnalyticsService.instance.logScreenView(
      'client_applicant_management',
    );
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getInt('userId') ?? 0;
      if (clientId == 0) throw Exception('로그인이 필요합니다.');

      final res = await AuthenticatedHttpClient.get(
        // 취소 지원자는 명시적으로 요청할 때만 내려온다. 구버전 앱은 이 값을
        // 안 보내서 취소 건을 아예 못 받는다 — is_canceled를 모르는 구버전이
        // 취소자를 정상 지원자로 표시하는 걸 막기 위한 장치다.
        Uri.parse(
          '$baseUrl/api/applicants/by-client/$clientId?includeCanceled=1',
        ),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) throw Exception('서버 오류 (${res.statusCode})'); // 노출 금지 — catch 에서 Msg 로 치환

      final data = jsonDecode(res.body);
      final groups =
          (data['jobs'] as List? ?? [])
              .map((j) => JobApplicantGroup.fromJson(j))
              .toList();
      final summary = data['summary'] as Map<String, dynamic>? ?? {};

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _totalCount = summary['total'] ?? 0;
        _loading = false;
        _currentPage = 1;
        _selectedByJob.clear();
        _selectingJob = null;
      });
    } on AuthSessionExpiredException {
      _redirectToOnboarding();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '잠시 후 다시 시도해 주세요.'; // 'Exception: 서버 오류 (500)'가 그대로 보이던 것. 제목이 이미 '불러오지 못했어요'
        _loading = false;
      });
    }
  }

  int get _totalPages => (_groups.length / _jobsPerPage).ceil().clamp(1, 9999);

  List<JobApplicantGroup> get _pagedGroups {
    final start = (_currentPage - 1) * _jobsPerPage;
    final end = (start + _jobsPerPage).clamp(0, _groups.length);
    return _groups.sublist(start, end);
  }

  // 채팅(=채용) 전에 지원자 프로필·신뢰도 확인
  void _goToWorkerProfile(ApplicantModel applicant) {
    if (applicant.workerId <= 0) return;
    Navigator.pushNamed(
      context,
      '/worker-profile',
      arguments: applicant.workerId,
    );
  }

  Future<void> _goToChat(
    ApplicantModel applicant,
    JobApplicantGroup group, {
    bool retried = false,
  }) async {
    try {
      // 서버가 /api/chat/get-room에 참여자 검증을 건다 — 맨몸 http.get이면 401이다
      final res = await AuthenticatedHttpClient.get(
        Uri.parse(
          '$baseUrl/api/chat/get-room?jobId=${group.jobId}&workerId=${applicant.workerId}',
        ),
      );
      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final roomId = data['chatRoomId'];
        if (roomId == null) throw Exception('채팅방 ID 없음');

        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => ChatRoomScreen(
                  chatRoomId:
                      roomId is int ? roomId : int.parse(roomId.toString()),
                  jobInfo: {
                    'id': group.jobId,
                    'job_id': group.jobId,
                    'title': group.jobTitle,
                    'location_city': group.locationCity,
                    'worker_id': applicant.workerId,
                    'user_name': applicant.workerName,
                    'user_thumbnail_url': applicant.profileImageUrl,
                    'client_thumbnail_url': null,
                    'client_company_name': null,
                  },
                ),
          ),
        ).then((_) => _fetch());
      } else if (res.statusCode == 404 && !retried) {
        // 지원은 했는데 방이 없는 건(구버전 지원 경로, 90일 598건 중 5건) — 예전엔 '아직 채팅방이 없어요'에서 막혔다
        final created = await AuthenticatedHttpClient.postJson(
          Uri.parse('$baseUrl/api/chat/start'),
          body: {'workerId': applicant.workerId, 'jobId': group.jobId},
        );
        if (!mounted) return;
        if (created.statusCode != 200 && created.statusCode != 201) throw Exception('채팅방 생성 실패');
        await _goToChat(applicant, group, retried: true);
      } else {
        throw Exception('채팅방 조회 실패');
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('지원자 관리 오류: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(Msg.server)));
    }
  }

  Set<int> _selectedSet(int jobId) =>
      _selectedByJob.putIfAbsent(jobId, () => <int>{});

  bool _isSelected(JobApplicantGroup group, ApplicantModel applicant) =>
      _selectedSet(group.jobId).contains(applicant.workerId);

  void _toggleApplicant(JobApplicantGroup group, ApplicantModel applicant) {
    setState(() {
      final selected = _selectedSet(group.jobId);
      if (selected.contains(applicant.workerId)) {
        selected.remove(applicant.workerId);
      } else {
        selected.add(applicant.workerId);
      }
    });
  }

  void _redirectToOnboarding() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/onboarding', (_) => false);
  }

  String _formatPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return raw;
  }

  Future<void> _showApplicantPhone(ApplicantModel applicant) async {
    if (applicant.applicationId <= 0 ||
        _phoneLoading.contains(applicant.applicationId)) {
      return;
    }

    final agreed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '지원자 연락처 보기',
                  style: TextStyle(
                    fontSize: AppFontSize.titleLg,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '채용 연락, 일정 조율, 출근확정, 분쟁 및 노쇼 확인 목적에 한해 이용해 주세요.',
                  style: TextStyle(
                    fontSize: AppFontSize.body2,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          '확인하고 보기'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (agreed != true) return;

    setState(() => _phoneLoading.add(applicant.applicationId));
    try {
      final res = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/applicants/contact/${applicant.applicationId}'),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        throw Exception(body['message']?.toString() ?? '연락처 조회 실패');
      }
      final phone = body['worker_phone']?.toString() ?? '';
      if (phone.isEmpty) throw Exception('등록된 연락처가 없습니다.');
      setState(() {
        _visiblePhones[applicant.applicationId] = _formatPhone(phone);
      });
    } on AuthSessionExpiredException {
      _redirectToOnboarding();
    } catch (e) {
      if (!mounted) return;
      debugPrint('연락처 조회 실패: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(Msg.loadFailed)));
    } finally {
      if (mounted) {
        setState(() => _phoneLoading.remove(applicant.applicationId));
      }
    }
  }

  Future<void> _copyApplicantPhone(String phone) async {
    final text = phone.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('연락처를 복사했어요.')));
  }

  Future<void> _showBulkMessageSheet(JobApplicantGroup group) async {
    final selected = _selectedSet(group.jobId).toList();
    if (selected.isEmpty || _bulkSending) return;

    final controller = TextEditingController(
      text: '안녕하세요. ${group.jobTitle} 공고 담당자입니다.\n지원해주셔서 감사합니다. 채팅 확인 부탁드려요.',
    );
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.mark_chat_unread_rounded, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '선택 지원자 ${selected.length}명에게 메시지',
                      style: const TextStyle(
                        fontSize: AppFontSize.title,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                group.jobTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: AppFontSize.meta, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                minLines: 4,
                maxLines: 7,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: '지원자에게 보낼 메시지를 입력하세요.',
                  filled: true,
                  fillColor: AppColors.bgMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(ctx, text);
                  },
                  child: const Text(
                    '메시지 발송'),
                ),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (message == null || message.trim().isEmpty) return;
    await _sendBulkMessage(group, selected, message.trim());
  }

  Future<void> _sendBulkMessage(
    JobApplicantGroup group,
    List<int> workerIds,
    String message,
  ) async {
    if (_bulkSending) return;
    setState(() => _bulkSending = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getInt('userId') ?? 0;
      final res = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/applicants/bulk-message'),
        body: {
          'jobId': group.jobId,
          'clientId': clientId,
          'workerIds': workerIds,
          'message': message,
        },
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 409) {
        // 고른 사람 모두 대화가 끝났거나 막힌 방 — 서버 문구를 그대로
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body['message']?.toString() ?? Msg.messageSendFailed)));
        return;
      }
      if (res.statusCode != 200) {
        throw Exception(body['message']?.toString() ?? '발송 실패');
      }
      setState(() {
        _selectedSet(group.jobId).clear();
        _selectingJob = null;
      });
      final skipped = (body['skipped'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${body['sent'] ?? workerIds.length}명에게 메시지를 보냈어요.'
            '${skipped > 0 ? ' 대화가 끝난 $skipped명은 빠졌어요.' : ''}',
          ),
        ),
      );
      await _fetch();
    } on AuthSessionExpiredException {
      _redirectToOnboarding();
    } catch (e) {
      if (!mounted) return;
      debugPrint('메시지 발송 실패: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(Msg.messageSendFailed)));
    } finally {
      if (mounted) setState(() => _bulkSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selecting = _selectingJob != null;
    final selectedCount = selecting ? _selectedSet(_selectingJob!).length : 0;
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AlbailjuAppBar(
        title: '지원자 관리',
        brand: true,
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetch,
          ),
        ],
      ),
      body:
          _loading
              ? const AppSkeletonList(avatar: true)
              : _error != null
              ? _buildError()
              : _groups.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                onRefresh: _fetch,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        children: [
                          _buildSummaryRow(),
                          const SizedBox(height: 12),
                          ..._pagedGroups.map(_buildJobCard),
                        ],
                      ),
                    ),
                    if (_totalPages > 1 && !selecting) _buildPagination(),
                  ],
                ),
              ),
      // 여러 명 선택 중일 때만 — 평소엔 행마다 체크박스·'메시지' 칩이 떠 있던 것(늘 비활성이라 버튼처럼 안 보였다)
      bottomNavigationBar:
          selecting
              ? AppBottomBar(
                child: AppPrimaryButton(
                  label: selectedCount > 0 ? '$selectedCount명에게 메시지 보내기' : '메시지 보낼 사람을 골라 주세요',
                  loading: _bulkSending,
                  onPressed:
                      selectedCount > 0
                          ? () => _showBulkMessageSheet(_groups.firstWhere((g) => g.jobId == _selectingJob))
                          : null,
                ),
              )
              : null,
    );
  }

  // ─── 요약 한 줄 ──────────────────────────────────────────────────
  // 큰 숫자 상자 3개였던 것 → 한 줄. '미확인'은 실제로는 '채용 확정 전'이라 이름도 바꿨다.
  Widget _buildSummaryRow() {
    final pending = _groups.fold(0, (s, g) => s + g.pendingCount);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text.rich(
        TextSpan(
          style: AppTextStyles.body2,
          children: [
            TextSpan(text: '지원자 $_totalCount명', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            if (pending > 0) TextSpan(text: ' · 채용 확정 전 $pending명'),
          ],
        ),
      ),
    );
  }

  // ─── 공고 카드 ───────────────────────────────────────────────────

  Widget _buildJobCard(JobApplicantGroup group) {
    final isExpanded = _expanded[group.jobId] ?? false;
    final hasMore = group.applicants.length > _applicantsPreview;
    final showList = isExpanded ? group.applicants : group.applicants.take(_applicantsPreview).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildJobCardHeader(group),
          if (group.applicants.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Text('아직 지원자가 없어요', style: AppTextStyles.body2),
            )
          else ...[
            for (final (i, a) in showList.indexed)
              _buildApplicantRow(a, group, isLast: i == showList.length - 1 && !hasMore),
            if (hasMore)
              InkWell(
                onTap: () => setState(() => _expanded[group.jobId] = !isExpanded),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.lg)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: Text(
                      isExpanded ? '접기' : '${group.applicants.length - _applicantsPreview}명 더보기',
                      style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildJobCardHeader(JobApplicantGroup group) {
    final closed = group.jobStatus != 'active';
    final selectingThis = _selectingJob == group.jobId;
    final start = group.startDate != null && group.startDate!.length >= 10
        ? DateTime.tryParse(group.startDate!.substring(0, 10))
        : null;
    final meta = [
      if (group.locationCity?.isNotEmpty ?? false) group.locationCity!,
      if (formatWorkDays(start, null, null) case final d?) d,
      '${group.activeApplicants.length}명 지원',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (closed) ...[const JobSignalBadge(label: '마감'), const SizedBox(width: 6)],
                    Flexible(
                      child: Text(
                        group.jobTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.w700,
                          color: closed ? AppColors.textSecondary : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(meta, style: AppTextStyles.body2),
              ],
            ),
          ),
          // 2명 이상일 때만 — 한 명이면 그냥 채팅하면 된다
          if (group.activeApplicants.length >= 2)
            TextButton(
              onPressed: () => setState(() {
                if (selectingThis) {
                  _selectingJob = null;
                  _selectedByJob.clear();
                } else {
                  _selectedByJob.clear();
                  _selectingJob = group.jobId;
                }
              }),
              child: Text(selectingThis ? '선택 취소' : '여러 명에게 메시지'),
            ),
        ],
      ),
    );
  }

  // ─── 지원자 행 ───────────────────────────────────────────────────

  /// 취소한 지원자. 목록에서 지우지 않고 회색으로 남긴다 — 조용히 사라지면
  /// 사장님은 지원자가 왔다 간 사실 자체를 모른다(채팅방만 남아 더 헷갈린다).
  /// 선택·연락처·채팅 액션은 전부 뺀다. 더 이상 진행할 게 없는 상대다.
  Widget _buildCanceledApplicantRow(ApplicantModel applicant) {
    final when = applicant.canceledAt;
    final subtitle = [
      if (applicant.age > 0) '${applicant.age}세',
      if (applicant.genderLabel.isNotEmpty) applicant.genderLabel,
      when != null ? '${_timeAgo(when)} 취소' : '지원 취소',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Opacity(opacity: 0.45, child: _buildAvatar(applicant)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  applicant.workerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.body2),
              ],
            ),
          ),
          const JobSignalBadge(label: '지원 취소'),
        ],
      ),
    );
  }

  Widget _buildApplicantRow(
    ApplicantModel applicant,
    JobApplicantGroup group, {
    required bool isLast,
  }) {
    if (applicant.isCanceled) return _buildCanceledApplicantRow(applicant);
    final selecting = _selectingJob == group.jobId;
    final selected = _isSelected(group, applicant);
    final visiblePhone = _visiblePhones[applicant.applicationId];
    final phoneLoading = _phoneLoading.contains(applicant.applicationId);
    final meta = [
      if (applicant.age > 0) '${applicant.age}세',
      if (applicant.genderLabel.isNotEmpty) applicant.genderLabel,
      '${_timeAgo(applicant.appliedAt)} 지원',
    ].join(' · ');
    // 상태 배지는 확정·완료만. '처리 필요'는 거의 모든 행에 붙어 정보가 없었다(Everyone-Has-It)
    final status =
        applicant.isCompleted
            ? const JobSignalBadge(label: '근무 완료', signal: JobSignal.trust)
            : applicant.isConfirmed
            ? const JobSignalBadge(label: '출근 확정', signal: JobSignal.trust)
            : null;

    return InkWell(
      // 선택 중이면 행 전체가 체크, 아니면 프로필(채팅 전 지원자 확인)
      onTap: selecting ? () => _toggleApplicant(group, applicant) : () => _goToWorkerProfile(applicant),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selecting) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 24,
                  color: selected ? AppColors.primary : AppColors.textDisabled,
                ),
              ),
              const SizedBox(width: 10),
            ],
            _buildAvatar(applicant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          applicant.workerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AppGradeBadge(score: applicant.safeActivityScore),
                      if (status != null) ...[const SizedBox(width: 4), status],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(meta, style: AppTextStyles.body2),
                  if (!selecting && (applicant.workerPhoneMasked.isNotEmpty || visiblePhone != null))
                    // 번호는 글자 한 줄 + 오른쪽 글자 링크. 회색 상자에 테두리까지 있던 것을 걷어냈다
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap:
                          phoneLoading
                              ? null
                              : visiblePhone != null
                              ? () => _copyApplicantPhone(visiblePhone)
                              : () => _showApplicantPhone(applicant),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text.rich(
                          TextSpan(
                            style: AppTextStyles.body2,
                            children: [
                              TextSpan(text: visiblePhone ?? applicant.workerPhoneMasked),
                              const TextSpan(text: '  '),
                              TextSpan(
                                text: phoneLoading ? '확인 중' : visiblePhone != null ? '복사' : '번호 보기',
                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!selecting) ...[
              const SizedBox(width: 8),
              // 채용 전 = 할 일이라 파랑, 확정 뒤엔 보조(회색). 라벨은 하는 일 하나 — '완료 확인'·'확정 확인'도 결국 채팅방이었다
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child:
                    applicant.isConfirmed || applicant.isCompleted
                        ? OutlinedButton(style: _rowBtn, onPressed: () => _goToChat(applicant, group), child: const Text('채팅'))
                        : ElevatedButton(style: _rowBtn, onPressed: () => _goToChat(applicant, group), child: const Text('채팅')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 행 안 작은 버튼 — 색·모양은 테마, 크기만 줄인다
  static final ButtonStyle _rowBtn = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(64, 38)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
    textStyle: WidgetStatePropertyAll(AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600)),
  );

  // ─── 페이지네이션 ────────────────────────────────────────────────

  Widget _buildPagination() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _pageArrowBtn(
            icon: Icons.chevron_left_rounded,
            onTap:
                _currentPage > 1 ? () => setState(() => _currentPage--) : null,
          ),
          const SizedBox(width: 8),
          ...List.generate(_totalPages, (i) {
            final page = i + 1;
            final isSelected = page == _currentPage;
            return GestureDetector(
              onTap: () => setState(() => _currentPage = page),
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.textDisabled,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$page',
                    style: TextStyle(
                      fontSize: AppFontSize.button,
                      fontWeight: FontWeight.w600,
                      color:
                          isSelected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 8),
          _pageArrowBtn(
            icon: Icons.chevron_right_rounded,
            onTap:
                _currentPage < _totalPages
                    ? () => setState(() => _currentPage++)
                    : null,
          ),
        ],
      ),
    );
  }

  Widget _pageArrowBtn({required IconData icon, VoidCallback? onTap}) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.textDisabled),
        ),
        child: Icon(
          icon,
          size: 20,
          color: active ? AppColors.textSecondary : AppColors.textDisabled,
        ),
      ),
    );
  }

  // ─── 헬퍼 ────────────────────────────────────────────────────────

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${dt.month}/${dt.day}';
  }

  Widget _buildAvatar(ApplicantModel applicant) {
    // 사진 없는 아바타: 사람마다 다른 파스텔 4색(라벤더 포함) → 중립 한 색 (2026-10)
    final colors = [
      [AppColors.bgMuted, AppColors.textSecondary],
    ];
    final c = colors[applicant.workerId % colors.length];

    if (applicant.profileImageUrl != null &&
        applicant.profileImageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: NetworkImage(applicant.profileImageUrl!),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: c[0],
      child: Text(
        applicant.workerName.isNotEmpty ? applicant.workerName[0] : '?',
        style: TextStyle(
          fontSize: AppFontSize.button,
          fontWeight: FontWeight.w600,
          color: c[1],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return AppEmptyState(
      icon: Icons.people_alt_outlined,
      title: '아직 지원자가 없어요',
      message: '공고를 올리면 알바생들이 지원할 거예요.',
      actionLabel: '새로고침',
      onAction: _fetch,
      secondaryAction: true,
    );
  }

  Widget _buildError() {
    return AppEmptyState(
      icon: Icons.error_outline_rounded,
      title: '불러오지 못했어요',
      message: _error ?? '알 수 없는 오류',
      actionLabel: '다시 시도',
      onAction: _fetch,
    );
  }
}
