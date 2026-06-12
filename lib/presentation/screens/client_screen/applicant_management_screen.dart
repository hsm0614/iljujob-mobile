// lib/presentation/screens/applicant_management_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/constants.dart';
import '../../chat/chat_room_screen.dart'; // 경로 맞게 수정
import '../../widgets/albailju_common.dart';

// ─── 모델 ────────────────────────────────────────────────────────

class ApplicantModel {
  final int applicationId;
  final DateTime appliedAt;
  final bool isConfirmed;
  final bool isCompleted;
  final int workerId;
  final String workerName;
  final String? profileImageUrl;
  final int? birthYear;
  final String? gender;
  final int? activityScore;

  ApplicantModel({
    required this.applicationId,
    required this.appliedAt,
    required this.isConfirmed,
    required this.isCompleted,
    required this.workerId,
    required this.workerName,
    this.profileImageUrl,
    this.birthYear,
    this.gender,
    this.activityScore,
  });

  factory ApplicantModel.fromJson(Map<String, dynamic> j) {
    return ApplicantModel(
      applicationId: j['application_id'] ?? 0,
      appliedAt: DateTime.tryParse(j['applied_at'] ?? '') ?? DateTime.now(),
      isConfirmed: j['is_confirmed'] == true || j['is_confirmed'] == 1,
      isCompleted: j['is_completed'] == true || j['is_completed'] == 1,
      workerId: j['worker_id'] ?? 0,
      workerName: j['worker_name'] ?? '이름 없음',
      profileImageUrl: j['profile_image_url'],
      birthYear:
          j['birth_year'] != null ? int.tryParse('${j['birth_year']}') : null,
      gender: j['gender'],
      activityScore:
          j['activity_score'] != null
              ? int.tryParse('${j['activity_score']}') ?? 0
              : 0,
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
        return const Color(0xFF3B8AFF);
      case 'B':
        return const Color(0xFF0F766E);
      case 'C':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF9CA3AF);
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
        return const Color(0xFFF4F6FA);
    }
  }

  bool get isNew => !isConfirmed;
  int get age => birthYear != null ? DateTime.now().year - birthYear! : 0;
  String get genderLabel =>
      gender == 'male'
          ? '남'
          : gender == 'female'
          ? '여'
          : '';
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
    return JobApplicantGroup(
      jobId: j['job_id'] ?? 0,
      jobTitle: j['job_title'] ?? '공고 없음',
      locationCity: j['location_city'],
      startDate: j['start_date'],
      jobStatus: j['job_status'] ?? '',
      applicants: list,
    );
  }

  int get newCount => applicants.where((a) => a.isNew).length;
}

// ─── 상수 ────────────────────────────────────────────────────────
const kBrandBlue = Color(0xFF3B8AFF);
const _blue = Color(0xFF3B8AFF);
const _blueBg = Color(0xFFE8F0FF);
const _green = Color(0xFF0F766E);
const _greenBg = Color(0xFFE8F7EF);
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

  @override
  void initState() {
    super.initState();
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

      final res = await http
          .get(Uri.parse('$baseUrl/api/applicants/by-client/$clientId'))
          .timeout(const Duration(seconds: 10));

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

  Future<void> _goToChat(
    ApplicantModel applicant,
    JobApplicantGroup group,
  ) async {
    try {
      final res = await http.get(
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
      final ids = group.applicants.map((a) => a.workerId).toSet();
      if (selected.length == ids.length) {
        selected.clear();
      } else {
        selected
          ..clear()
          ..addAll(ids);
      }
    });
  }

  Future<String> _authToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken') ?? '';
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
                        color: Color(0xFF191F28),
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
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
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
                    borderSide: const BorderSide(color: Color(0xFFE5E8EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E8EB)),
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
      final token = await _authToken();
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/applicants/bulk-message'),
            headers: {
              'Content-Type': 'application/json',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'jobId': group.jobId,
              'clientId': clientId,
              'workerIds': workerIds,
              'message': message,
            }),
          )
          .timeout(const Duration(seconds: 12));
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
      backgroundColor: const Color(0xFFF4F6FA),
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
    return Row(
      children: [
        _summaryCard(
          '전체',
          '$_totalCount명',
          const Color(0xFF191F28),
          Colors.white,
        ),
        const SizedBox(width: 10),
        _summaryCard('미확인', '$_unreadCount명', _blue, _blueBg),
        const SizedBox(width: 10),
        _summaryCard('완료', '$completedCount명', _green, _greenBg),
      ],
    );
  }

  Widget _summaryCard(
    String label,
    String value,
    Color textColor,
    Color bgColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E8EB)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
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
        border: Border.all(color: const Color(0xFFE5E8EB)),
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
                      color: const Color(0xFFD1D5DB),
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
                    color: const Color(0xFFF4F6FA),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(18),
                    ),
                    border: Border(
                      top: BorderSide(color: const Color(0xFFF4F6FA)),
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
        group.applicants.isNotEmpty && selectedCount == group.applicants.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: hasNew ? const Color(0xFFF0F5FF) : const Color(0xFFFAFAFA),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(bottom: BorderSide(color: const Color(0xFFF4F6FA))),
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
                        color: Color(0xFF191F28),
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
                            color: const Color(0xFF9CA3AF),
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              group.locationCity!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFF9CA3AF),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (group.startDate != null) ...[
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: const Color(0xFF9CA3AF),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            group.startDate!.length >= 10
                                ? group.startDate!.substring(0, 10)
                                : group.startDate!,
                            style: TextStyle(
                              fontSize: 12,
                              color: const Color(0xFF9CA3AF),
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
                decoration: BoxDecoration(
                  color:
                      group.applicants.isEmpty
                          ? const Color(0xFFF4F6FA)
                          : (hasNew ? _blueBg : const Color(0xFFF0FFF4)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  group.applicants.isEmpty
                      ? '0명'
                      : '${group.applicants.length}명${hasNew ? ' · 신규 ${group.newCount}' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        group.applicants.isEmpty
                            ? Colors.grey
                            : (hasNew ? _blue : _green),
                  ),
                ),
              ),
            ],
          ),
          if (group.applicants.isNotEmpty) ...[
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
                  : const Color(0xFFF4F6FA),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                selected && enabled
                    ? color
                    : enabled
                    ? const Color(0xFFD1D5DB)
                    : const Color(0xFFF4F6FA),
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
                    ? const Color(0xFF6B7280)
                    : const Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }

  // ─── 지원자 행 ───────────────────────────────────────────────────

  Widget _buildApplicantRow(
    ApplicantModel applicant,
    JobApplicantGroup group, {
    required bool isLast,
  }) {
    final selected = _isSelected(group, applicant);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
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
                              : const Color(0xFFD1D5DB),
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
              _buildAvatar(applicant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 5,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 92),
                          child: Text(
                            applicant.workerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _activityGradeBadge(applicant),
                        _statusChip(applicant),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (applicant.age > 0) '${applicant.age}세',
                        if (applicant.genderLabel.isNotEmpty)
                          applicant.genderLabel,
                        _timeAgo(applicant.appliedAt),
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _goToChat(applicant, group),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _blue,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '채팅',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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
            color: const Color(0xFFF4F6FA),
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
                    color: isSelected ? _blue : const Color(0xFFD1D5DB),
                  ),
                ),
                child: Center(
                  child: Text(
                    '$page',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color:
                          isSelected ? Colors.white : const Color(0xFF6B7280),
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
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: Icon(
          icon,
          size: 20,
          color: active ? const Color(0xFF6B7280) : const Color(0xFFD1D5DB),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: applicant.activityGradeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        applicant.activityGrade,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: applicant.activityGradeColor,
        ),
      ),
    );
  }

  Widget _statusChip(ApplicantModel applicant) {
    if (applicant.isCompleted) {
      return _chip('완료', const Color(0xFFE1F5EE), const Color(0xFF085041));
    }
    if (applicant.isConfirmed) {
      return _chip('채용확정', const Color(0xFFE6F1FB), const Color(0xFF0C447C));
    }
    if (applicant.isNew) return _chip('신규', _blueBg, _blue);
    return _chip('확인', const Color(0xFFF1F3F5), const Color(0xFF9CA3AF));
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600),
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
            style: TextStyle(fontSize: 16, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 8),
          const Text(
            '공고를 올리면 알바생들이 지원할 거예요!',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
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
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _fetch, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
