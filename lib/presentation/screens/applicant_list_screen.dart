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
  String? jobId;

  // 브랜드 컬러
  static const Color _brandBlue = Color(0xFF3B8AFF);

  String formatDate(String isoDate) {
    try {
      final dateTime = DateTime.parse(isoDate).toLocal();
      return DateFormat('yyyy.MM.dd').format(dateTime);
    } catch (e) {
      return isoDate;
    }
  }

  String maskName(String name) {
    if (name.isEmpty) return name;
    if (name.length == 2) {
      return '${name[0]}*';
    } else if (name.length > 2) {
      return name[0] + ('*' * (name.length - 2)) + name[name.length - 1];
    } else {
      // 한 글자
      return name;
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
      final headers = await authHeaders(); // 토큰 포함

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          applicants
            ..clear()
            ..addAll(data['applicants'] ?? []);
          isLoading = false;
        });
      } else if (response.statusCode == 401) {
        setState(() => isLoading = false);
        _showSnackbar('로그인이 필요한 기능입니다.');
        if (mounted) {
          Navigator.pushNamed(context, '/login');
        }
      } else {
        setState(() => isLoading = false);
        _showSnackbar('지원자 정보를 불러오지 못했어요. (코드 ${response.statusCode})');
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackbar('네트워크 오류가 발생했어요. 잠시 후 다시 시도해주세요.');
      debugPrint('❌ 네트워크 오류: $e');
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

      // 1) 기존 채팅방 조회
      final getRes = await http.get(getUri, headers: headers);

      if (getRes.statusCode == 200) {
        final data = jsonDecode(getRes.body);
        chatRoomId = data['chatRoomId'] as int?;
        jobInfo = (data['jobInfo'] as Map?)?.cast<String, dynamic>();
      } else if (getRes.statusCode == 404) {
        // 2) 없으면 새로 생성
        final startUri = Uri.parse('$baseUrl/api/chat/start');
        final startRes = await http.post(
          startUri,
          headers: headers,
          body: jsonEncode({
            'jobId': jobId,
            'workerId': workerId,
          }),
        );

        if (startRes.statusCode == 200) {
          final data = jsonDecode(startRes.body);
          chatRoomId = data['chatRoomId'] as int?;
          jobInfo = (data['jobInfo'] as Map?)?.cast<String, dynamic>();
        } else {
          _showSnackbar('채팅방 생성에 실패했어요. (코드 ${startRes.statusCode})');
          return;
        }
      } else if (getRes.statusCode == 401) {
        _showSnackbar('로그인이 필요한 기능입니다.');
        if (mounted) {
          Navigator.pushNamed(context, '/login');
        }
        return;
      } else {
        _showSnackbar('채팅방 정보를 불러오지 못했어요. (코드 ${getRes.statusCode})');
        return;
      }

      if (chatRoomId == null) {
        _showSnackbar('채팅방 정보를 가져오지 못했어요.');
        return;
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            chatRoomId: chatRoomId!,
            jobInfo: {
              ...?jobInfo,
              'worker_id': workerId,
            },
          ),
        ),
      );
    } catch (e) {
      _showSnackbar('네트워크 오류가 발생했어요. 잠시 후 다시 시도해주세요.');
      debugPrint('❌ 채팅방 이동 오류: $e');
    }
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.fixed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
     appBar: AppBar(
  backgroundColor: Colors.white,
  foregroundColor: const Color(0xFF3B8AFF), // <- 여기만 변경
  elevation: 0.4,
  title: const Text(
    '지원자 목록',
    style: TextStyle(
      fontFamily: 'jalnan2ttf',
      fontWeight: FontWeight.w700,
    ),
  ),
),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : applicants.isEmpty
              ? _buildEmptyState()
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: ListView.separated(
                    itemCount: applicants.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final applicant = applicants[index];

                      final dynamic rawId = applicant['worker_id'];
                      final int? workerId = rawId is int
                          ? rawId
                          : int.tryParse(rawId?.toString() ?? '');

                      if (workerId == null) {
                        // worker_id 없으면 렌더링 스킵
                        return const SizedBox.shrink();
                      }

                      final String name =
                          (applicant['name'] ?? '이름 비공개').toString();
                      final String masked = maskName(name);
                      final String createdAt =
                          (applicant['created_at'] ?? '').toString();

                      final String? profileUrl =
                          applicant['profile_image_url'] as String?;

                      return _buildApplicantCard(
                        workerId: workerId,
                        name: masked,
                        originalName: name,
                        createdAt: createdAt,
                        profileUrl: profileUrl,
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.people_outline,
              size: 52,
              color: Colors.grey,
            ),
            SizedBox(height: 12),
            Text(
              '아직 지원자가 없어요.',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '조금만 더 기다리면\n알바일주에서 알바생들이 찾아올 거예요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplicantCard({
    required int workerId,
    required String name,
    required String originalName,
    required String createdAt,
    String? profileUrl,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE3E5EB),
          width: 0.8,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.pushNamed(
            context,
            '/worker-profile',
            arguments: workerId,
          );
        },
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundImage:
                  (profileUrl != null && profileUrl.isNotEmpty)
                      ? NetworkImage(profileUrl)
                      : null,
              backgroundColor: const Color(0xFFE9ECF2),
              child: (profileUrl == null || profileUrl.isEmpty)
                  ? const Icon(
                      Icons.person,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 이름 + 실제 이름 힌트
                  Row(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${originalName})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black38,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 15,
                        color: Colors.black45,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '지원일 ${formatDate(createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => _goToChatRoom(workerId),
              style: TextButton.styleFrom(
                backgroundColor: _brandBlue.withOpacity(0.08),
                foregroundColor: _brandBlue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(
                Icons.chat_bubble_outline,
                size: 18,
              ),
              label: const Text(
                '채팅하기',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
