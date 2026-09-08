// lib/presentation/screens/applicant_management_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/constants.dart';
import '../../../data/services/authenticated_http_client.dart';
import '../../../data/services/screen_analytics_service.dart';
import '../../chat/chat_room_screen.dart'; // 경로 맞게 수정
import '../../widgets/albailju_common.dart';
import '../../../config/app_theme.dart';

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

  Color get activityGradeColor {
    switch (activityGrade) {
      case 'S':
        return const Color(0xFFFF6B00);
      case 'A':
        return AppColors.primary;
      case 'B':
        return const Color(0xFF0F766E);
      case 'C':
        return AppColors.textSecondary;
      default:
        return AppColors.textTertiary;
    }
  }

  Color get activityGradeBg {
    switch (activityGrade) {
      case 'S':
        return const Color(0xFFFFF0E6);
      case 'A':
        return const Color(0xFFE8F0FF);
      case 'B':
        return const Color(0xFFE8F7EF);
      case 'C':
        return const Color(0xFFF1F3F5);
      default:
        return AppColors.bgPage;
    }
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
const kBrandBlue = AppColors.primary;
const _blue = AppColors.primary;
const _blueBg = Color(0xFFE8F0FF);
const _green = Color(0xFF0F766E);
const _greenBg = Color(0xFFE8F7EF);
const _signalTime = Color(0xFFEA8035); // 시간이 급함
const _signalTimeBg = Color(0xFFFDF1E7);
const _ink = AppColors.textPrimary;
const _inkSecondary = AppColors.textSecondary;
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
  int _unreadCount = 0;
  int _currentPage = 1;
  final Map<int, bool> _expanded = {};
  final Map<int, Set<int>> _selectedByJob = {};
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

      if (res.statusCode != 200) throw Exception('서버 오류 (${res.statusCode})');

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
        _unreadCount = summary['unread'] ?? 0;
        _loading = false;
        _currentPage = 1;
        _selectedByJob.clear();
      });
    } on AuthSessionExpiredException {
      _redirectToOnboarding();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
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
    JobApplicantGroup group,
  ) async {
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
      } else if (res.statusCode == 404) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('아직 채팅방이 없습니다.')));
      } else {
        throw Exception('채팅방 조회 실패');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('오류: $e')));
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

  void _toggleAllApplicants(JobApplicantGroup group) {
    setState(() {
      final selected = _selectedSet(group.jobId);
      final ids = group.activeApplicants.map((a) => a.workerId).toSet();
      if (selected.length == ids.length) {
        selected.clear();
      } else {
        selected
          ..clear()
          ..addAll(ids);
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '채용 연락, 일정 조율, 출근확정, 분쟁 및 노쇼 확인 목적에 한해 이용해 주세요.',
                  style: TextStyle(
                    fontSize: 13,
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
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4B5563),
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '확인하고 보기',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('연락처 조회 실패: $e')));
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
                  const Icon(Icons.mark_chat_unread_rounded, color: _blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '선택 지원자 ${selected.length}명에게 메시지',
                      style: const TextStyle(
                        fontSize: 17,
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
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                  fillColor: const Color(0xFFF8F9FB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _blue, width: 1.4),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '메시지 발송',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
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
      if (res.statusCode != 200) {
        throw Exception(body['message']?.toString() ?? '발송 실패');
      }
      setState(() => _selectedSet(group.jobId).clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${body['sent'] ?? workerIds.length}명에게 메시지를 보냈어요.'),
        ),
      );
      await _fetch();
    } on AuthSessionExpiredException {
      _redirectToOnboarding();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('메시지 발송 실패: $e')));
    } finally {
      if (mounted) setState(() => _bulkSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AlbailjuAppBar(
        title: '지원자 관리',
        brand: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetch,
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
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
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        children: [
                          _buildSummaryRow(),
                          const SizedBox(height: 16),
                          ..._pagedGroups.map(_buildJobCard),
                        ],
                      ),
                    ),
                    if (_totalPages > 1) _buildPagination(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
    );
  }

  // ─── 요약 카드 ───────────────────────────────────────────────────

  Widget _buildSummaryRow() {
    final completedCount = _groups.fold(
      0,
      (s, g) => s + g.applicants.where((a) => a.isCompleted).length,
    );
    // 숫자는 전부 잉크색. 파랑은 누를 수 있는 것에만 쓰고(CTA Blue Rule),
    // 초록 계열은 돈·신뢰 신호 전용이다(Two-Signal Rule) — '완료' 같은
    // 분류에 쓰면 한 화면에서 색끼리 경쟁해 전부 무시된다.
    return Row(
      children: [
        _summaryCard('전체', '$_totalCount명'),
        const SizedBox(width: 10),
        _summaryCard('미확인', '$_unreadCount명'),
        const SizedBox(width: 10),
        _summaryCard('완료', '$completedCount명'),
      ],
    );
  }

  Widget _summaryCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 공고 카드 ───────────────────────────────────────────────────

  Widget _buildJobCard(JobApplicantGroup group) {
    final isExpanded = _expanded[group.jobId] ?? false;
    final hasMore = group.applicants.length > _applicantsPreview;
    final showList =
        isExpanded
            ? group.applicants
            : group.applicants.take(_applicantsPreview).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 공고 헤더
          _buildJobCardHeader(group),

          // 지원자 없음
          if (group.applicants.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.inbox_rounded,
                      size: 28,
                      color: AppColors.textDisabled,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '아직 지원자가 없어요',
                      style: TextStyle(
                        fontSize: 13,
                        color: const Color(0xFFBCC0CB),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ...showList.asMap().entries.map(
              (e) => _buildApplicantRow(
                e.value,
                group,
                isLast: e.key == showList.length - 1 && !hasMore,
              ),
            ),

            // 더보기 / 접기
            if (hasMore)
              InkWell(
                onTap:
                    () => setState(() => _expanded[group.jobId] = !isExpanded),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.bgPage,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(18),
                    ),
                    border: Border(
                      top: BorderSide(color: AppColors.bgPage),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isExpanded
                            ? '접기'
                            : '${group.applicants.length - _applicantsPreview}명 더보기',
                        style: const TextStyle(
                          fontSize: 13,
                          color: _blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: _blue,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildJobCardHeader(JobApplicantGroup group) {
    final hasNew = group.newCount > 0;
    final selectedCount = _selectedSet(group.jobId).length;
    final allSelected =
        group.activeApplicants.isNotEmpty &&
        selectedCount == group.activeApplicants.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: hasNew ? const Color(0xFFF0F5FF) : const Color(0xFFFAFAFA),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(bottom: BorderSide(color: AppColors.bgPage)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 공고 활성 상태 도트
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      group.jobStatus == 'active'
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFBCC0CB),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.jobTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (group.locationCity != null) ...[
                          Icon(
                            Icons.location_on_rounded,
                            size: 12,
                            color: _inkSecondary,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              group.locationCity!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _inkSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (group.startDate != null) ...[
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: _inkSecondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            group.startDate!.length >= 10
                                ? group.startDate!.substring(0, 10)
                                : group.startDate!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _inkSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 지원자 수 뱃지
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                // 인원수만. '신규 N'은 아래 '처리 필요 N명' 칩과 정의가 사실상
                // 같아서 둘 다 붙이면 같은 정보를 두 번 말한다(Everyone-Has-It Rule).
                decoration: BoxDecoration(
                  color: AppColors.bgMuted,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${group.activeApplicants.length}명',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          // 취소만 남은 공고엔 선택·메시지가 의미 없다
          if (group.activeApplicants.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // 뱃지 색은 두 갈래뿐이다 — 주황=시간이 급함, 초록계열=돈·신뢰.
                // 파랑은 누를 수 있는 것 전용이라 정보 칩에는 쓰지 않는다.
                if (group.pendingCount > 0)
                  _headerSignalChip(
                    icon: Icons.priority_high_rounded,
                    label: '처리 필요 ${group.pendingCount}명',
                    color: _signalTime,
                    background: _signalTimeBg,
                  ),
                if (group.confirmedCount > 0)
                  _headerSignalChip(
                    icon: Icons.check_circle_outline_rounded,
                    label: '출근 확정 ${group.confirmedCount}명',
                    color: _green,
                    background: _greenBg,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _smallActionChip(
                  label: allSelected ? '선택 해제' : '전체 선택',
                  selected: allSelected,
                  color: _blue,
                  onTap: () => _toggleAllApplicants(group),
                ),
                const SizedBox(width: 8),
                _smallActionChip(
                  label: selectedCount > 0 ? '메시지 $selectedCount' : '메시지',
                  selected: selectedCount > 0,
                  color: _green,
                  onTap:
                      selectedCount > 0 && !_bulkSending
                          ? () => _showBulkMessageSheet(group)
                          : null,
                ),
                const Spacer(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _smallActionChip({
    required String label,
    required bool selected,
    required Color color,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              selected && enabled
                  ? color
                  : enabled
                  ? Colors.white
                  : AppColors.bgPage,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                selected && enabled
                    ? color
                    : enabled
                    ? AppColors.textDisabled
                    : AppColors.bgPage,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color:
                selected && enabled
                    ? Colors.white
                    : enabled
                    ? AppColors.textSecondary
                    : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _headerSignalChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 지원자 행 ───────────────────────────────────────────────────

  /// 취소한 지원자. 목록에서 지우지 않고 회색으로 남긴다 — 조용히 사라지면
  /// 사장님은 지원자가 왔다 간 사실 자체를 모른다(채팅방만 남아 더 헷갈린다).
  /// 선택·연락처·채팅 액션은 전부 뺀다. 더 이상 진행할 게 없는 상대다.
  Widget _buildCanceledApplicantRow(
    ApplicantModel applicant, {
    required bool isLast,
  }) {
    final when = applicant.canceledAt;
    final subtitle = [
      if (applicant.age > 0) '${applicant.age}세',
      if (applicant.genderLabel.isNotEmpty) applicant.genderLabel,
      when != null ? '${_timeAgo(when)} 취소' : '지원 취소',
    ].join(' · ');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              // 체크박스 자리를 비워 활성 지원자와 세로선을 맞춘다
              const SizedBox(width: 34),
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
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: _inkSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(applicant),
            ],
          ),
        ),
        if (!isLast)
          const Divider(
            height: 1,
            thickness: 0.5,
            indent: 46,
            color: AppColors.bgPage,
          ),
      ],
    );
  }

  Widget _buildApplicantRow(
    ApplicantModel applicant,
    JobApplicantGroup group, {
    required bool isLast,
  }) {
    if (applicant.isCanceled) {
      return _buildCanceledApplicantRow(applicant, isLast: isLast);
    }
    final selected = _isSelected(group, applicant);
    final visiblePhone = _visiblePhones[applicant.applicationId];
    final phoneLoading = _phoneLoading.contains(applicant.applicationId);
    final actionColor =
        applicant.isCompleted
            ? _green
            : applicant.isConfirmed
            ? const Color(0xFF0C447C)
            : _blue;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _toggleApplicant(group, applicant),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? _blue : Colors.white,
                    border: Border.all(
                      color:
                          selected
                              ? _blue
                              : applicant.isNew
                              ? _blue
                              : AppColors.textDisabled,
                      width: 1.5,
                    ),
                  ),
                  child:
                      selected
                          ? const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Colors.white,
                          )
                          : null,
                ),
              ),
              GestureDetector(
                onTap: () => _goToWorkerProfile(applicant),
                child: _buildAvatar(applicant),
              ),
              const SizedBox(width: 12),
              // 이름·활동등급 영역 탭 = 프로필 상세 (채팅 전 지원자 검증)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _goToWorkerProfile(applicant),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Text(
                              applicant.workerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: AppColors.textTertiary,
                          ),
                          const Spacer(),
                          _statusChip(applicant),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        [
                          if (applicant.age > 0) '${applicant.age}세',
                          if (applicant.genderLabel.isNotEmpty)
                            applicant.genderLabel,
                          _timeAgo(applicant.appliedAt),
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: _inkSecondary,
                        ),
                      ),
                      const SizedBox(height: 7),
                      // 지원 시각은 바로 위 메타줄에 이미 있다. 같은 값을 칩으로
                      // 한 번 더 붙이면 화면만 시끄러워진다.
                      _activityGradeBadge(applicant),
                      if (applicant.workerPhoneMasked.isNotEmpty ||
                          visiblePhone != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.phone_iphone_rounded,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 5),
                              // 좁은 화면에서 번호가 '연락처 보기'를 밀어내 28px 넘쳤다.
                              // 번호만 줄어들게 두고 버튼은 온전히 남긴다.
                              Flexible(
                                child: Text(
                                  visiblePhone ?? applicant.workerPhoneMasked,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                              ),
                              if (visiblePhone == null) ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap:
                                      phoneLoading
                                          ? null
                                          : () =>
                                              _showApplicantPhone(applicant),
                                  child: Text(
                                    phoneLoading ? '확인 중' : '연락처 보기',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color:
                                          phoneLoading
                                              ? AppColors.textTertiary
                                              : _blue,
                                    ),
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap:
                                      () => _copyApplicantPhone(visiblePhone),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.copy_rounded,
                                        size: 13,
                                        color: _blue,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        '복사',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          color: _blue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _goToChat(applicant, group),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: actionColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    applicant.actionLabel,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 0.5,
            indent: 46,
            color: AppColors.bgPage,
          ),
      ],
    );
  }

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
                  color: isSelected ? _blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? _blue : AppColors.textDisabled,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$page',
                    style: TextStyle(
                      fontSize: 14,
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
          borderRadius: BorderRadius.circular(10),
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
    final colors = [
      [const Color(0xFFE6F1FB), const Color(0xFF0C447C)],
      [const Color(0xFFE1F5EE), const Color(0xFF085041)],
      [const Color(0xFFEEEDFE), const Color(0xFF3C3489)],
      [const Color(0xFFFAEEDA), const Color(0xFF633806)],
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
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: c[1],
        ),
      ),
    );
  }

  Widget _activityGradeBadge(ApplicantModel applicant) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: applicant.activityGradeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_rounded,
            size: 11,
            color: applicant.activityGradeColor,
          ),
          const SizedBox(width: 3),
          Text(
            '${applicant.activityGrade} · ${applicant.safeActivityScore}점',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: applicant.activityGradeColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(ApplicantModel applicant) {
    if (applicant.isCanceled) {
      return _chip(applicant.statusLabel, const Color(0xFFF1F3F5), _inkSecondary);
    }
    if (applicant.isCompleted) {
      return _chip(
        applicant.statusLabel,
        const Color(0xFFE1F5EE),
        const Color(0xFF085041),
      );
    }
    if (applicant.isConfirmed) {
      return _chip(
        applicant.statusLabel,
        const Color(0xFFE6F1FB),
        const Color(0xFF0C447C),
      );
    }
    if (applicant.isNew) return _chip(applicant.statusLabel, _blueBg, _blue);
    return _chip('확인', const Color(0xFFF1F3F5), _inkSecondary);
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _miniInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgPage,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.textSecondary),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.people_alt_outlined,
            size: 56,
            color: Color(0xFFBCC0CB),
          ),
          const SizedBox(height: 16),
          const Text(
            '아직 지원자가 없어요',
            style: TextStyle(fontSize: 16, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 8),
          const Text(
            '공고를 올리면 알바생들이 지원할 거예요!',
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 24),
          TextButton(onPressed: _fetch, child: const Text('새로고침')),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(
            _error ?? '알 수 없는 오류',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _fetch, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
