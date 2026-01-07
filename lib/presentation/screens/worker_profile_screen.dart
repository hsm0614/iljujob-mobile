import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkerProfileScreen extends StatefulWidget {
  final int workerId;

  const WorkerProfileScreen({Key? key, required this.workerId})
      : super(key: key);

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
      return name[0] + '*';
    } else if (name.length > 2) {
      return name[0] + '*' * (name.length - 2) + name[name.length - 1];
    } else {
      return name; // 한 글자인 경우 그대로
    }
  }

  Future<void> _fetchProfile(int workerId) async {
    try {
      final profileRes = await http.get(
        Uri.parse('$baseUrl/api/worker/profile?id=$workerId'),
      );
      final expRes = await http.get(
        Uri.parse('$baseUrl/api/worker/experiences?workerId=$workerId'),
      );
      final licenseRes = await http.get(
        Uri.parse('$baseUrl/api/worker/licenses?workerId=$workerId'),
      );

      print(
        '📥 프로필 응답: ${profileRes.statusCode}, '
        '경력 응답: ${expRes.statusCode}, '
        '자격증 응답: ${licenseRes.statusCode}',
      );

      if (profileRes.statusCode == 200) {
        final profileData = jsonDecode(profileRes.body);

        // 워커가 이력서 열람에 동의했는지
        final resumeAllowed = _parseResumeFlag(profileData['resume_consent']);

        setState(() {
          profile = profileData;
          canViewResume = resumeAllowed;
        });
      }

      if (expRes.statusCode == 200) {
        final expData = jsonDecode(expRes.body);
        setState(() {
          experiences = List<Map<String, dynamic>>.from(expData);
        });
      }

      if (licenseRes.statusCode == 200) {
        final licenseData = jsonDecode(licenseRes.body);
        setState(() {
          licenses = List<Map<String, dynamic>>.from(licenseData);
        });
      }
    } catch (e) {
      print('❌ 프로필 불러오기 실패: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  String getBirthYear() {
    final raw = profile?['birth_year']?.toString() ?? '';
    return raw.length >= 4 ? raw.substring(0, 4) : '없음';
  }

  void _showBlockDialog(String targetType, int targetId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('사용자 차단'),
        content: const Text(
          '해당 사용자를 차단하시겠습니까?\n'
          '차단 시 더 이상 채팅 및 지원 등의 상호작용이 제한됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.block),
            label: const Text('차단'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);

              final prefs = await SharedPreferences.getInstance();
              final userId = prefs.getInt('userId') ?? 0;

              final response = await http.post(
                Uri.parse('$baseUrl/api/user-block/block'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'userId': userId,
                  'targetId': targetId,
                  'targetType': targetType, // 'worker'
                }),
              );

              if (response.statusCode == 200) {
                setState(() => isBlocked = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('해당 사용자를 차단했습니다.')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('차단 실패: ${response.body}')),
                );
              }
            },
          ),
        ],
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
      builder: (_) => AlertDialog(
        title: const Text('사용자 신고'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              items: reasonOptions
                  .map(
                    (reason) => DropdownMenuItem<String>(
                      value: reason,
                      child: Text(reason),
                    ),
                  )
                  .toList(),
              value: selectedReason,
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
              style: TextStyle(fontSize: 12, color: Colors.grey),
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

              final response = await http.post(
                Uri.parse('$baseUrl/api/user-report'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'reporterId': reporterId,
                  'targetId': targetId,
                  'targetType': targetType,
                  'reasonCategory': selectedReason,
                  'reasonDetail': reasonController.text.trim(),
                }),
              );

              Navigator.pop(context);

              if (response.statusCode == 200) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('신고가 접수되었습니다.')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('신고 실패: ${response.body}')),
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
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          '알바생 프로필',
          style: TextStyle(
            fontFamily: 'Jalnan2TTF',
            color: Color(0xFF3B8AFF),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.report, color: Colors.red),
            onPressed: () => _showReportDialog('worker', widget.workerId),
          ),
          IconButton(
            icon: Icon(
              isBlocked ? Icons.block_flipped : Icons.block,
              color: isBlocked ? Colors.grey : Colors.black,
            ),
            tooltip: isBlocked ? '차단 해제' : '차단하기',
            onPressed: () => _showBlockDialog('worker', widget.workerId),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : profile == null
              ? const Center(child: Text('프로필 정보를 불러올 수 없습니다.'))
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ===== 헤더: 아바타 + 통계 =====
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundImage:
                                  (profile!['profile_image_url'] != null &&
                                          (profile!['profile_image_url'] as String)
                                              .isNotEmpty)
                                      ? NetworkImage(
                                          profile!['profile_image_url'],
                                        )
                                      : null,
                              child: (profile!['profile_image_url'] == null ||
                                      (profile!['profile_image_url'] as String)
                                          .isEmpty)
                                  ? const Icon(Icons.person, size: 40)
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            _statWrap(),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ===== 이력서 열람 안내 카드 =====
                      _resumeInfoCard(),
                      const SizedBox(height: 8),
                      Text(
                        canViewResume
                            ? '강점, 희망 분야, 경력, 자격증까지 확인할 수 있습니다.'
                            : '이 알바생은 이력서 열람에 동의하지 않았습니다.\n기본 정보만 확인할 수 있어요.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),

                      // ===== 기본 정보 (항상 표시) =====
                      const SizedBox(height: 24),
                      const _SectionTitle('기본 정보'),
                      const SizedBox(height: 8),
                      _buildInfoTile(
                        '이름',
                        maskName(profile!['name'] ?? '없음'),
                      ),
                      _buildInfoTile(
                        '성별',
                        profile!['gender'] ?? '없음',
                      ),
                      _buildInfoTile(
                        '출생년도',
                        getBirthYear(),
                      ),

                      // ===== 이력서 상세 (동의한 경우에만) =====
                      if (canViewResume) ...[
                        const SizedBox(height: 24),
                        const _SectionTitle('이력서 상세'),
                        const SizedBox(height: 8),
                        _buildInfoTile(
                          '강점',
                          profile!['strengths'] ?? '없음',
                        ),
                        _buildInfoTile(
                          '성격',
                          profile!['traits'] ?? '없음',
                        ),
                        _buildInfoTile(
                          '업무 희망 분야',
                          profile!['desired_work'] ?? '없음',
                        ),
                        _buildInfoTile(
                          '가능 요일',
                          profile!['available_days'] ?? '없음',
                        ),
                        _buildInfoTile(
                          '가능 시간대',
                          profile!['available_times'] ?? '없음',
                        ),
                        _buildInfoTile(
                          '자기소개',
                          profile!['introduction'] ?? '없음',
                        ),
                        const SizedBox(height: 20),
                        _buildExperienceList(),
                        const SizedBox(height: 20),
                        _buildLicenseChips(),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _statWrap() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _squareStatCard(
          Icons.verified,
          '채용 확정',
          '${profile!['confirmed_count'] ?? 0}',
          Colors.green,
        ),
        _squareStatCard(
          Icons.check_circle,
          '알바 완료',
          '${profile!['completed_count'] ?? 0}',
          Colors.blue,
        ),
        _squareStatCard(
          Icons.thumb_up,
          '매너 칭찬',
          '${profile!['manner_point'] ?? 0}',
          Colors.purple,
        ),
        _squareStatCard(
          Icons.warning,
          '패널티',
          '${profile!['penalty_point'] ?? 0}',
          Colors.red,
        ),
      ],
    );
  }

  Widget _resumeInfoCard() {
    final enabled = canViewResume;
    final icon = enabled ? Icons.visibility : Icons.visibility_off;
    final title = enabled ? '이력서 열람 가능' : '이력서 열람 불가';
    final desc = enabled
        ? '이 알바생은 이력서 열람에 동의했어요.\n강점, 경력, 자격증까지 확인해보세요.'
        : '이 알바생은 이력서 열람에 동의하지 않았어요.\n기본 정보만 확인 가능합니다.';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF1675F4).withOpacity(.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF1675F4)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _squareStatCard(
    IconData icon,
    String label,
    String count,
    Color color,
  ) {
    const double boxSize = 86;

    return SizedBox(
      width: boxSize,
      height: boxSize,
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              count,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$title:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildExperienceList() {
    if (experiences.isEmpty) {
      return _buildInfoTile('경력', '없음');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('경력', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...experiences.map(
          (exp) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.work_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exp['place'] ?? ''),
                      if ((exp['description'] ?? '').toString().isNotEmpty)
                        Text(
                          exp['description'],
                          style: const TextStyle(color: Colors.black87),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLicenseChips() {
    if (licenses.isEmpty) {
      return _buildInfoTile('자격·면허', '없음');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('자격·면허', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: licenses
              .map(
                (lic) => Chip(
                  label: Text('${lic['name']} (${lic['issued_at']})'),
                  backgroundColor: Colors.indigo.shade50,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF1675F4),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey.shade300,
          ),
        ),
      ],
    );
  }
}
