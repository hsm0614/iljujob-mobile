import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';
import '../chat/chat_room_screen.dart';
import '../../utiles/auth_util.dart';

class ApplicantListScreen extends StatefulWidget {
  const ApplicantListScreen({super.key});

  @override
  State<ApplicantListScreen> createState() => _ApplicantListScreenState();
}

class _ApplicantListScreenState extends State<ApplicantListScreen> {
  List<dynamic> applicants = [];
  bool isLoading = true;
  String? jobId;

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
    return name[0] + '*';
  } else if (name.length > 2) {
    return name[0] + '*' * (name.length - 2) + name[name.length - 1];
  } else {
    return name; // 한 글자인 경우 그대로
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
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          applicants = data['applicants'] ?? [];
          isLoading = false;
        });
      } else {
        print('❌ 서버 오류: ${response.statusCode}');
        setState(() => isLoading = false);
      }
    } catch (e) {
      print('❌ 네트워크 오류: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _goToChatRoom(int workerId) async {
  if (jobId == null) return;

  final getUri = Uri.parse(
    '$baseUrl/api/chat/get-room-by-id?jobId=$jobId&workerId=$workerId',
  );

  try {
    // 1) 토큰 헤더
    final headers = await authHeaders();

    // 2) 먼저 조회
    final getRes = await http.get(getUri, headers: headers);

    int? chatRoomId;
    Map<String, dynamic>? jobInfo;

    if (getRes.statusCode == 200) {
      final data = jsonDecode(getRes.body);
      chatRoomId = data['chatRoomId'] as int?;
      jobInfo = (data['jobInfo'] as Map?)?.cast<String, dynamic>();
    } else if (getRes.statusCode == 404) {
      // 3) 없으면 생성
      final startUri = Uri.parse('$baseUrl/api/chat/start');
      final startRes = await http.post(
        startUri,
        headers: headers,
        body: jsonEncode({'jobId': jobId, 'workerId': workerId}),
      );
      if (startRes.statusCode == 200) {
        final data = jsonDecode(startRes.body);
        chatRoomId = data['chatRoomId'] as int?;
        jobInfo = (data['jobInfo'] as Map?)?.cast<String, dynamic>();
      } else {
        _showSnackbar('채팅방 생성 실패 (${startRes.statusCode})');
        return;
      }
    } else if (getRes.statusCode == 401) {
      _showSnackbar('로그인이 필요합니다.');
      if (mounted) Navigator.pushNamed(context, '/login');
      return;
    } else {
  // 👇 여기 추가
  _showSnackbar('채팅방 조회 실패 (${getRes.statusCode})');
  return;
}


    if (chatRoomId == null) {
      _showSnackbar('채팅방 정보를 가져오지 못했습니다.');
      return;
    }

    // 4) 이동
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          chatRoomId: chatRoomId!,
          jobInfo: {...?jobInfo, 'worker_id': workerId},
        ),
      ),
    );
  } catch (e) {
    _showSnackbar('네트워크 오류: $e');
  }
}
  void _showSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('지원자 리스트')),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : applicants.isEmpty
              ? const Center(child: Text('지원자가 없습니다.'))
              : ListView.builder(
                itemCount: applicants.length,
                itemBuilder: (context, index) {
                  final applicant = applicants[index];

                  // 🔐 안전하게 int로 파싱
                  final dynamic rawId = applicant['worker_id'];
                  final int? workerId =
                      rawId is int
                          ? rawId
                          : int.tryParse(rawId?.toString() ?? '');

                  if (workerId == null) {
                    return const SizedBox(); // 무시
                  }

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage:
                          applicant['profile_image_url'] != null
                              ? NetworkImage(applicant['profile_image_url'])
                              : null,
                      child:
                          applicant['profile_image_url'] == null
                              ? const Icon(Icons.person)
                              : null,
                    ),
                    title: Text(applicant['name'] ?? '이름 없음'),
                    subtitle: Text(
                      '지원일자: ${formatDate(applicant['created_at'])}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.chat_bubble_outline),
                      onPressed: () {
                        _goToChatRoom(workerId);
                      },
                    ),
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        '/worker-profile',
                        arguments: workerId,
                      );
                    },
                  );
                },
              ),
    );
  }
}
