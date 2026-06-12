// 📁 presentation/screens/applicant_list_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';
import 'package:iljujob/utiles/auth_util.dart';

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

  static const Color _brandBlue  = Color(0xFF3B8AFF);
  static const Color _bg         = Color(0xFFF4F6FA);
  static const Color _border     = Color(0xFFE5E8EB);
  static const Color _text       = Color(0xFF191F28);
  static const Color _label      = Color(0xFF8B95A1);

  String formatDate(String isoDate) {
    try {
      return DateFormat('yyyy.MM.dd').format(DateTime.parse(isoDate).toLocal());
    } catch (_) { return isoDate; }
  }

  String maskName(String name) {
    if (name.isEmpty) return name;
    if (name.length == 2) return '${name[0]}*';
    if (name.length > 2) return '${name[0]}${'*' * (name.length - 2)}${name[name.length - 1]}';
    return name;
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
      final response = await http.get(uri, headers: await authHeaders());

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['applicants'] ?? [];

        // AI 스코어 있는지 확인
        final hasAiScore = list.any((a) => a['ai_score'] != null);

        setState(() {
          applicants..clear()..addAll(list);
          _aiSorted = hasAiScore;
          isLoading = false;
        });
      } else if (response.statusCode == 401) {
        setState(() => isLoading = false);
        _showSnackbar('로그인이 필요한 기능입니다.');
        if (mounted) Navigator.pushNamed(context, '/login');
      } else {
        setState(() => isLoading = false);
        _showSnackbar('지원자 정보를 불러오지 못했어요. (코드 ${response.statusCode})');
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackbar('네트워크 오류가 발생했어요.');
    }
  }

  Future<void> _goToChatRoom(int workerId) async {
    if (jobId == null) return;
    final getUri = Uri.parse(
      '$baseUrl/api/chat/get-room-by-id?jobId=$jobId&workerId=$workerId',
    );
    try {
      final headers = await authHeaders();
      int? chatRoomId;
      Map<String, dynamic>? jobInfo;

      final getRes = await http.get(getUri, headers: headers);
      if (getRes.statusCode == 200) {
        final data = jsonDecode(getRes.body);
        chatRoomId = data['chatRoomId'] as int?;
        jobInfo    = (data['jobInfo'] as Map?)?.cast<String, dynamic>();
      } else if (getRes.statusCode == 404) {
        final startRes = await http.post(
          Uri.parse('$baseUrl/api/chat/start'),
          headers: headers,
          body: jsonEncode({'jobId': jobId, 'workerId': workerId}),
        );
        if (startRes.statusCode == 200) {
          final data = jsonDecode(startRes.body);
          chatRoomId = data['chatRoomId'] as int?;
          jobInfo    = (data['jobInfo'] as Map?)?.cast<String, dynamic>();
        } else {
          _showSnackbar('채팅방 생성에 실패했어요.');
          return;
        }
      }

      if (chatRoomId == null || !mounted) return;

      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          chatRoomId: chatRoomId!,
          jobInfo: {...?jobInfo, 'worker_id': workerId},
        ),
      ));
    } catch (e) {
      _showSnackbar('네트워크 오류가 발생했어요.');
    }
  }

  void _showSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.fixed),
    );
  }

  // ── AI 스코어 색상 ──────────────────────────────────────
  Color _scoreColor(double score) {
    if (score >= 0.80) return const Color(0xFF10B981); // 초록
    if (score >= 0.60) return const Color(0xFF3B8AFF); // 파랑
    if (score >= 0.40) return const Color(0xFFF59E0B); // 노랑
    return const Color(0xFF9CA3AF);                    // 회색
  }

  // ── reasons 아이콘 매핑 ─────────────────────────────────
  Map<String, String> get _reasonIcons => {
    '가까움':     '📍',
    '위치':       '📍',
    '직종':       '💼',
    '의미유사':   '💼',
    '시급상위':   '💰',
    '시간대겹침': '🕐',
    '완료이력좋음': '⭐',
  };

  String _reasonIcon(String reason) {
    for (final entry in _reasonIcons.entries) {
      if (reason.contains(entry.key)) return entry.value;
    }
    return '✅';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _brandBlue,
        elevation: 0.4,
        title: Row(children: [
          const Text('지원자 목록'),
          const SizedBox(width: 8),
          // 지원자 수 배지
          if (applicants.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _brandBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${applicants.length}명',
                style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _brandBlue),
              ),
            ),
        ]),
        actions: [
          // AI 정렬 배지
          if (_aiSorted)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3182F6), Color(0xFF6C5CE7)]),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('✨', style: TextStyle(fontSize: 12)),
                SizedBox(width: 4),
                Text('AI 정렬됨',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : applicants.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () => _loadApplicants(jobId!),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: applicants.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final a = applicants[index];
                      final int? workerId = int.tryParse(
                          (a['worker_id'] ?? '').toString());
                      if (workerId == null) return const SizedBox.shrink();

                      final double? aiScore = a['ai_score'] != null
                          ? double.tryParse(a['ai_score'].toString())
                          : null;
                      final List reasons =
                          (a['ai_reasons'] as List?) ?? [];
                      final double? distKm = a['dist_km'] != null
                          ? double.tryParse(a['dist_km'].toString())
                          : null;

                      return _buildApplicantCard(
                        rank:        index + 1,
                        workerId:    workerId,
                        name:        maskName((a['name'] ?? '이름 비공개').toString()),
                        originalName: (a['name'] ?? '이름 비공개').toString(),
                        createdAt:   (a['created_at'] ?? '').toString(),
                        profileUrl:  a['profile_image_url'] as String?,
                        aiScore:     aiScore,
                        reasons:     reasons.cast<String>(),
                        distKm:      distKm,
                        completedCount: int.tryParse(
                            (a['completed_count'] ?? '0').toString()) ?? 0,
                        mannerPoint: int.tryParse(
                            (a['manner_point'] ?? '0').toString()) ?? 0,
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.people_outline, size: 52, color: Colors.grey),
          SizedBox(height: 12),
          Text('아직 지원자가 없어요.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text('조금만 더 기다리면\n알바일주에서 알바생들이 찾아올 거예요.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black54)),
        ]),
      ),
    );
  }

  Widget _buildApplicantCard({
    required int rank,
    required int workerId,
    required String name,
    required String originalName,
    required String createdAt,
    String? profileUrl,
    double? aiScore,
    List<String> reasons = const [],
    double? distKm,
    int completedCount = 0,
    int mannerPoint = 0,
  }) {
    final hasAi     = aiScore != null;
    final scoreInt  = hasAi ? (aiScore * 100).round() : null;
    final scoreColor = hasAi ? _scoreColor(aiScore) : _label;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasAi && aiScore >= 0.80
              ? scoreColor.withOpacity(0.4)
              : _border,
          width: hasAi && aiScore >= 0.80 ? 1.5 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pushNamed(
            context, '/worker-profile', arguments: workerId),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 상단 행 ──────────────────────────────────
              Row(
                children: [
                  // 순위 배지
                  if (hasAi) ...[
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: rank <= 3
                            ? scoreColor.withOpacity(0.15)
                            : _bg,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('$rank',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: rank <= 3 ? scoreColor : _label,
                          )),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // 프로필 이미지
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: (profileUrl?.isNotEmpty == true)
                        ? NetworkImage(profileUrl!)
                        : null,
                    backgroundColor: const Color(0xFFE9ECF2),
                    child: (profileUrl == null || profileUrl.isEmpty)
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),

                  // 이름 + 지원일
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(name,
                            style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          Text('($originalName)',
                            style: const TextStyle(
                              fontSize: 12, color: Colors.black38)),
                        ]),
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.schedule,
                              size: 13, color: Colors.black45),
                          const SizedBox(width: 3),
                          Text('지원일 ${formatDate(createdAt)}',
                            style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                        ]),
                      ],
                    ),
                  ),

                  // 채팅 버튼
                  TextButton.icon(
                    onPressed: () => _goToChatRoom(workerId),
                    style: TextButton.styleFrom(
                      backgroundColor: _brandBlue.withOpacity(0.08),
                      foregroundColor: _brandBlue,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999)),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('채팅',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),

              // ── AI 스코어 영역 ────────────────────────────
              if (hasAi) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                const SizedBox(height: 10),

                Row(children: [
                  // 매칭률 + 프로그레스바
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text('매칭률',
                            style: TextStyle(
                              fontSize: 11, color: _label,
                              fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          Text('$scoreInt%',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: scoreColor)),
                        ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: aiScore,
                            minHeight: 6,
                            backgroundColor: _bg,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                scoreColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 거리 + 완료이력 + 매너점수
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (distKm != null)
                        _infoChip('📍',
                          distKm < 1
                              ? '${(distKm * 1000).round()}m'
                              : '${distKm.toStringAsFixed(1)}km'),
                      if (completedCount > 0) ...[
                        const SizedBox(height: 4),
                        _infoChip('✅', '완료 $completedCount회'),
                      ],
                      if (mannerPoint > 0) ...[
                        const SizedBox(height: 4),
                        _infoChip('👍', '매너 $mannerPoint'),
                      ],
                    ],
                  ),
                ]),

                // reasons 배지
                if (reasons.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6, runSpacing: 4,
                    children: reasons.map((r) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scoreColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color: scoreColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${_reasonIcon(r)} $r',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scoreColor,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(String icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 3),
        Text(text,
          style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: _text)),
      ]),
    );
  }
}
