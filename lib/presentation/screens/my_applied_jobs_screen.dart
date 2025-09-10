// 리팩터링된 내 지원 공고 리스트 (채팅 연동 포함, 삭제 기능 SharedPreferences 유지)
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';
import '../../data/models/job.dart';
import 'job_detail_screen.dart';
import '../chat/chat_room_screen.dart';
import 'package:intl/intl.dart';

class MyAppliedJobsScreen extends StatefulWidget {
  const MyAppliedJobsScreen({super.key});

  @override
  State<MyAppliedJobsScreen> createState() => _MyAppliedJobsScreenState();
}

class _MyAppliedJobsScreenState extends State<MyAppliedJobsScreen> {
  List<Job> appliedJobs = [];
  List<Job> filteredJobs = [];
  Set<String> hiddenJobIds = {}; // ✅ 삭제된 항목 추적용 (SharedPreferences)
  bool isLoading = true;
  String filterStatus = '전체';
  String searchQuery = '';
  Map<String, bool> reviewStatusMap = {};
  Map<String, dynamic>? clientProfile;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadHiddenIds();
      await _loadAppliedJobs();
    });
  }

Future<bool> _checkIfReviewed({
  required int clientId,
  required String jobTitle,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final workerId = prefs.getInt('userId');
  if (workerId == null) {
    print('❗️workerId 없음 (로그인 필요)');
    return false;
  }

  final encodedTitle = Uri.encodeComponent(jobTitle.trim());
  final url = Uri.parse(
    '$baseUrl/api/review/has-reviewed?clientId=$clientId&workerId=$workerId&jobTitle=$encodedTitle',
  );

  try {
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['hasReviewed'] == true;
    } else {
      print('❌ 리뷰 여부 응답 오류: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ 네트워크 오류: $e');
  }
  return false;
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

  Future<void> _loadAppliedJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');

    if (workerId == null) {
      _showErrorSnackbar('로그인이 필요합니다. 다시 로그인해주세요.');
      setState(() => isLoading = false);
      return;
    }

    final url = Uri.parse(
      '$baseUrl/api/applications/my-jobs?workerId=$workerId',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final rawData = jsonDecode(response.body);

        final jobs = List<Job>.from(
          rawData
              .map((item) => Job.fromJson(item))
              .where((job) => job.status != 'deleted'),
        );
for (final job in jobs) {
  if (job.clientId == null) continue;

  final reviewKey = '${job.clientId}-${job.title}';
  final hasReviewed = await _checkIfReviewed(
    clientId: job.clientId!,
    jobTitle: job.title,
  );
  reviewStatusMap[reviewKey] = hasReviewed; // 🔁 여기!
}

        setState(() {
          appliedJobs = jobs;
          _applyFilters();
          isLoading = false;
        });
      } else {
        _showErrorSnackbar('공고 불러오기에 실패했습니다 (${response.statusCode})');
        setState(() {
          appliedJobs = [];
          filteredJobs = [];
          isLoading = false;
        });
      }
    } catch (e) {
      _showErrorSnackbar('네트워크 오류: $e');
      setState(() => isLoading = false);
    }
  }

  void _deleteFromList(String jobId) async {
    hiddenJobIds.add(jobId);
    await _saveHiddenIds();
    _applyFilters();
  }

  void _applyFilters() {
    List<Job> temp = appliedJobs;

    // ✅ 먼저 삭제된 항목 제거
    temp = temp.where((job) => !hiddenJobIds.contains(job.id)).toList();
    temp = temp.where((job) => job.status != 'deleted').toList(); // 🔥 여기 추가!!

    // ✅ 상태 필터
    if (filterStatus != '전체') {
      temp = temp.where((job) => job.status == filterStatus).toList();
    }

    // ✅ 검색 필터
    if (searchQuery.isNotEmpty) {
      temp =
          temp
              .where(
                (job) =>
                    job.title.contains(searchQuery) ||
                    job.location.contains(searchQuery),
              )
              .toList();
    }

    setState(() {
      filteredJobs = temp;
    });
  }
Future<void> _confirmDelete(String jobId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('삭제 확인'),
      content: const Text('해당 공고를 목록에서 삭제하시겠습니까? (내역은 기기에서만 숨겨집니다)'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('삭제', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    // 실제 숨김 처리
    _deleteFromList(jobId);

    if (!mounted) return;
    // 되돌리기 스낵바
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('삭제되었습니다.'),
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
}

  void _openChatRoom(Job job) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';
    final uri = Uri.parse(
      '$baseUrl/api/chat/get-room-by-id?jobId=${job.id}&workerId=${job.workerId}',
    );

    try {
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final chatRoomId = data['chatRoomId'];
        final jobInfo = Map<String, dynamic>.from(data['jobInfo']);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) =>
                    ChatRoomScreen(chatRoomId: chatRoomId, jobInfo: jobInfo),
          ),
        );
      } else {
        _showErrorSnackbar('채팅방 정보 요청 실패 (${response.statusCode})');
      }
    } catch (e) {
      _showErrorSnackbar('네트워크 오류: $e');
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case '제조':
        return Icons.factory;
      case '물류':
        return Icons.local_shipping;
      case '서비스':
        return Icons.support_agent;
      case '건설':
        return Icons.engineering;
      case '사무':
        return Icons.work;
      case '청소':
        return Icons.cleaning_services;
      default:
        return Icons.more_horiz;
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // 키보드 닫기
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          iconTheme: const IconThemeData(color: Colors.black),
          title:  Text(
            '내가 지원한 공고',
            style: TextStyle(
              fontFamily: 'Jalnan2TTF', // ✅ 폰트명 명시
              color: Color(0xFF3B8AFF),
              fontSize: 20,
            ),
          ),
        ),
        body:
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: '제목 또는 지역 검색',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              searchQuery = val;
                              _applyFilters();
                            },
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children:
                                ['전체', 'active', 'closed'].map((status) {
                                  return ChoiceChip(
                                    label: Text(
                                      status == '전체'
                                          ? '전체'
                                          : (status == 'active' ? '공고중' : '마감'),
                                    ),
                                    selected: filterStatus == status,
                                    onSelected: (_) {
                                      filterStatus = status;
                                      _applyFilters();
                                    },
                                  );
                                }).toList(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child:
                          filteredJobs.isEmpty
                              ? const Center(child: Text('😥 아직 지원한 공고가 없습니다.'))
                              : ListView.separated(
                                itemCount: filteredJobs.length,
                                separatorBuilder:
                                    (_, __) => const Divider(
                                      height: 1,
                                      thickness: 1,
                                      indent: 16,
                                      endIndent: 16,
                                    ),
                                itemBuilder: (context, index) {
                                   final job = filteredJobs[index];
final reviewKey = '${job.clientId}-${job.title}';
final isReviewed = reviewStatusMap[reviewKey] == true;
                                  final appliedAt =
                                      job.createdAt != null
                                          ? DateFormat(
                                            'MM.dd',
                                          ).format(job.createdAt!)
                                          : '';
                                  final start =
                                      job.startDate != null
                                          ? DateFormat(
                                            'MM.dd',
                                          ).format(job.startDate!)
                                          : '';
                                  final end =
                                      job.endDate != null
                                          ? DateFormat(
                                            'MM.dd',
                                          ).format(job.endDate!)
                                          : '';

                                  String statusText = '';
                                  Color statusColor = Colors.indigo;
                                  if (job.status == 'active') {
                                    statusText = '채용중';
                                    statusColor = Colors.indigo;
                                  } else if (job.status == 'hired' ||
                                      job.status == 'confirmed') {
                                    statusText = '채용 확정';
                                    statusColor = Colors.green;
                                  } else {
                                    statusText = '마감';
                                    statusColor = Colors.grey;
                                  }

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: 20,
                                    ),
                                    leading: Icon(
                                      _getCategoryIcon(job.category),
                                      color: Colors.indigo,
                                    ),
                                    title: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '[${job.category}] ${job.title}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: statusColor.withOpacity(
                                                  0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                statusText,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${job.location}  |  $start ~ $end',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        const SizedBox(height: 4),
                                        if (job.pay.isNotEmpty)
                                          Text(
                                            '💸 ${job.payType} ${job.pay}원   지원일: $appliedAt',
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        const SizedBox(height: 6),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed:
                                                isReviewed
                                                    ? null
                                                    : () {
                                                      Navigator.pushNamed(
                                                        context,
                                                        '/review',
                                                        arguments: {
                                                          'jobId': job.id,
                                                          'clientId':
                                                              job.clientId,
                                                          'jobTitle': job.title,
                                                          'companyName':
                                                              job.company,
                                                        },
                                                      );
                                                    },
                                            icon: Icon(
                                              Icons.edit_note,
                                              size: 18,
                                              color:
                                                  isReviewed
                                                      ? Colors.grey
                                                      : Colors.blue,
                                            ),
                                            label: Text(
                                              isReviewed
                                                  ? '후기 작성 완료'
                                                  : '후기 남기기',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color:
                                                    isReviewed
                                                        ? Colors.grey
                                                        : Colors.blue,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Wrap(
                                      spacing: 8,
                                      children: [
                                        if (job.chatRoomId != null)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.chat_bubble_outline,
                                              size: 20,
                                            ),
                                            color: Colors.indigo,
                                            tooltip: '채팅하기',
                                            onPressed: () => _openChatRoom(job),
                                          ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          color: Colors.redAccent,
                                          tooltip: '삭제',
                                          onPressed:
                                              () => _confirmDelete(job.id),

                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) =>
                                                  JobDetailScreen(job: job),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                    ),
                  ],
                ),
      ),
    );
  }
}
