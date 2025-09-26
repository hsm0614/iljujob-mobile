import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:iljujob/data/services/chat_service.dart';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';
import 'package:iljujob/presentation/screens/client_profile_screen.dart';
import '../../data/models/job.dart';
import '../../config/constants.dart';
import 'package:intl/intl.dart';
import 'full_image_view_screen.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:iljujob/presentation/screens/full_map_screen.dart';
import 'client_job_list_screen.dart';
import 'dart:io'; // Platform 사용을 위해 필요
import 'package:kakao_maps_flutter/kakao_maps_flutter.dart' as km;
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import '../../core/suspension.dart';
import '../../core/suspension_guard.dart';
import 'package:flutter/services.dart' show rootBundle;

class JobDetailScreen extends StatefulWidget {
  final Job job;

  const JobDetailScreen({super.key, required this.job});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  SuspensionState? _suspension; // /me에서 가져온 정지 상태
  bool hasApplied = false;
  int applicantCount = 0;
  int viewCount = 0;
  int bookmarkCount = 0;
  bool isLoading = true;
  Map<String, dynamic>? clientProfile;
  String? userType;
  int? myUserId;
  bool isBlocked = false;
int _currentImage = 0;
final PageController _pageController = PageController();

Future<void> _loadSuspension() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('userId');
    final type = (prefs.getString('userType') ?? 'worker').toLowerCase();
    if (id == null) throw Exception('no userId');

    final uri = Uri.parse('$baseUrl/api/public/suspension?type=$type&id=$id');
    final res = await http.get(uri); // ← 토큰 없이
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _suspension = SuspensionState(
          suspendedType:  (data['suspended_type'] ?? data['suspendedType'])?.toString(),
          suspendedUntil: (data['suspended_until'] ?? data['suspendedUntil'])?.toString(),
          suspendedReason:(data['suspended_reason'] ?? data['suspendedReason'])?.toString(),
        );
      });
      return;
    }
  } catch (_) {}

  // 기본 정상
  setState(() {
    _suspension = const SuspensionState(
      suspendedType: null, suspendedUntil: null, suspendedReason: null,
    );
  });
}
String _getWorkingPeriodText(Job job) {
  // 장기 알바
  if ((job.weekdays != null && job.weekdays!.trim().isNotEmpty)) {
    return job.weekdays!;
  }

  // 단기 알바
  if (job.startDate != null && job.endDate != null) {
    final start = _formatDate(job.startDate!);
    final end = _formatDate(job.endDate!);
    return '$start ~ $end';
  }

  return '근무 기간 미정';
}
String _formatDate(DateTime date) {
  final local = date.toLocal();           // ✅ 로컬(KST)로 변환
  return '${local.month}월 ${local.day}일';
}


bool _shouldShowReportButton() {
  // 클라이언트이고 내 공고라면 신고 버튼 숨김
  if (userType == 'client' && widget.job.clientId == myUserId) {
    return false;
  }
  return true;
}
bool get isClosed =>
    widget.job.status == 'closed' || widget.job.status == 'deleted';  @override
  Map<String, dynamic>? reviewSummary;

  
km.KakaoMapController? _kakao; // state에 컨트롤러 보관(필요시)
@override
void initState() {
  super.initState();
  _loadUserType();
  _checkAlreadyApplied();
  _initializePage();
  _incrementViewCount();
  _loadReviewSummary();
  _checkBlockStatus();

  _loadSuspension(); // ← 추가: 정지 상태 로드
}

@override
void dispose() {
  _pageController.dispose(); // 여기서만 dispose
  super.dispose();
}


String _getCompanyName() {
  if (clientProfile != null) {
    final name = clientProfile!['company_name'];
    if (name != null && name.toString().trim().isNotEmpty) return name;
  }

  if (widget.job.company != null &&
      widget.job.company!.trim().isNotEmpty) {
    return widget.job.company!;
  }

  return '회사 정보를 찾을 수 없습니다.';
}
Future<void> _initializePage() async {
  await _fetchApplicantCount();
  await _fetchClientProfile();
  await _fetchCounts();
  setState(() => isLoading = false);
}

  void didChangeDependencies() {
    super.didChangeDependencies();
    
  }
Future<void> _checkBlockStatus() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getInt('userId') ?? 0;

  final res = await http.get(Uri.parse(
    '$baseUrl/api/job/${widget.job.id}/block-status?userId=$userId',
  ));

  if (res.statusCode == 200) {
    final data = jsonDecode(res.body);
    setState(() {
      isBlocked = data['isBlocked'] == true;
    });
  }
}
Future<void> _loadUserType() async {
  final prefs = await SharedPreferences.getInstance();

  final userId = prefs.getInt('userId'); // 👈 오해 없도록 명확하게
  final userTypeFromPrefs = prefs.getString('userType');

  setState(() {
    myUserId = userId;
    userType = userTypeFromPrefs;
  });
}

  Future<void> _fetchApplicantCount() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/job/${widget.job.id}/applicant-count'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => applicantCount = data['count']);
      }
    } catch (e) {
      print('❌ 지원자 수 조회 오류: $e');
    }
  }

Future<void> _checkAlreadyApplied() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getInt('userId'); // 🔥 userPhone 말고 userId!
  final jobId = int.tryParse(widget.job.id.toString());

  if (userId == null || jobId == null) return;

  try {
    final response = await http.post(
      Uri.parse('$baseUrl/api/job/check-applied'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'workerId': userId, 'jobId': jobId}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        hasApplied = data['applied'];
      });

    } else {
      print('❌ 지원 여부 응답 오류: ${response.body}');
    }
  } catch (e) {
    print('❌ 지원 여부 확인 실패: $e');
  }
}



Future<void> _fetchClientProfile() async {
  if (widget.job.clientId == null) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    final url = Uri.parse('$baseUrl/api/client/profile?id=${widget.job.clientId}');
    final res = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (res.statusCode == 200) {
      setState(() => clientProfile = jsonDecode(res.body));
    } else {
      print('❌ 클라이언트 프로필 응답 실패: ${res.statusCode}');
    }
  } catch (e) {
    print('❌ 클라이언트 프로필 불러오기 실패: $e');
  }
}

Future<void> _loadReviewSummary() async {
  final clientId = widget.job.clientId;
  if (clientId == null) {
    print('❌ clientId가 null임');
    return;
  }

  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/review/summary?clientId=$clientId'),
    );


    if (response.statusCode == 200) {
      setState(() {
        reviewSummary = jsonDecode(response.body);
      });
    } else {
      print('❌ review summary 응답 오류: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ 리뷰 요약 불러오기 실패: $e');
  }
}
  Future<void> _fetchCounts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/job/${widget.job.id}/counts'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          viewCount = data['views'] ?? 0;
          bookmarkCount = data['bookmarks'] ?? 0;
        });
      } else {
        print('❌ 카운트 불러오기 실패: ${response.body}');
      }
    } catch (e) {
      print('❌ 카운트 네트워크 오류: $e');
    }
  }

  Future<void> _incrementViewCount() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/job/${widget.job.id}/increment-view'),
      );
      if (response.statusCode != 200) {
        print('❌ 조회수 증가 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 조회수 증가 중 예외 발생: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

Future<void> _applyToJob() async {
  
  // 0) 정지(차단) 가드: _suspension이 없다면 기본값(정상)으로 판단
  final s = _suspension ??
      const SuspensionState(
        suspendedType: null,
        suspendedUntil: null,
        suspendedReason: null,
      );
  if (!guardSuspended(context, s)) return; // 정지면 토스트 띄우고 중단

  // 1) 기본 검증
  final prefs = await SharedPreferences.getInstance();
  final workerId = prefs.getInt('userId');
  final clientId = widget.job.clientId;
  final String jobId = widget.job.id.toString();

  if (workerId == null || clientId == null || jobId.isEmpty) {
    _showSnack('❗ 로그인 또는 채용공고 정보가 올바르지 않습니다.');
    return;
  }

  // 2) 요청
  final applyUrl = Uri.parse('$baseUrl/api/job/apply');

  try {
    final response = await http.post(
      applyUrl,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'workerId': workerId,
        'jobId': widget.job.id, // int로 직접 전달
      }),
    );

    // 2-1) 서버가 정지 계정으로 막을 경우(권장: 423 Locked 또는 403)
    if (response.statusCode == 423 || response.statusCode == 403) {
      var msg = '정지 상태에서는 지원할 수 없습니다.';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && (data['code'] == 'SUSPENDED' || data['message'] != null)) {
          msg = data['message']?.toString() ?? msg;
        }
      } catch (_) {}
      _showSnack('❌ $msg');
      return;
    }

    // 2-2) 정상 처리
    if (response.statusCode == 200) {
      _showSnack('✅ 지원 완료');
      await _fetchApplicantCount();
      setState(() => hasApplied = true);

      final roomId = await startChatRoom(workerId, jobId, clientId);
      if (roomId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatRoomScreen(
              chatRoomId: roomId,
              jobInfo: {
                'title': widget.job.title,
                'pay': widget.job.pay,
                'posted_at': widget.job.postedAtUtc?.toUtc().toIso8601String() ?? '',
                'publish_at': widget.job.publishAt?.toUtc().toIso8601String() ?? '',
                'created_at': widget.job.createdAt?.toUtc().toIso8601String() ?? '',
                'client_id': clientId,
                'worker_id': workerId,
                'client_company_name': clientProfile?['company_name'] ?? widget.job.company ?? '기업',
                'client_thumbnail_url': clientProfile?['logo_url'] ?? '',
              },
            ),
          ),
        );
      } else {
        _showSnack('❌ 채팅방 생성 실패');
      }
    } else if (response.statusCode == 409) {
      _showSnack('⚠️ 이미 지원했습니다');
      setState(() => hasApplied = true);
    } else {
      _showSnack('❌ 오류 발생: ${response.body}');
    }
  } catch (e) {
    print('❌ 지원 중 예외: $e');
    _showSnack('❌ 네트워크 오류가 발생했습니다');
  }
}

  Future<void> _submitReport(String category, String detail, int jobId, int userId) async {
  final prefs = await SharedPreferences.getInstance();
  final userPhone = prefs.getString('userPhone');

  try {
    final response = await http.post(
      Uri.parse('$baseUrl/api/report/job'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jobId': jobId,
        'userId': userId,
        'userPhone': userPhone,
        'reasonCategory': category,
        'reasonDetail': detail,
      }),
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('신고가 접수되었습니다. 신고 내용은 24시간 이내 조치됩니다.'),
        ),
      );
    } else {
      _showSnack('신고 전송 실패: ${response.body}');
    }
  } catch (e) {
    print('❌ 예외 발생: $e');
    _showSnack('신고 중 오류가 발생했습니다.');
  }
}


  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

Widget _buildApplyButton() {
  if (isLoading) return const SizedBox();
  final isSuspended = _suspension?.isSuspended ?? false; // ← 추가
  final isButtonDisabled = hasApplied || isClosed || isBlocked || isSuspended; // ← 추가

  return SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isButtonDisabled ? Colors.grey : Colors.blue,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: isButtonDisabled ? null : _applyToJob,
        child: Text(
          isClosed ? '마감된 공고'
          : hasApplied ? '지원 완료'
          : isBlocked ? '차단된 기업'
          : isSuspended ? '정지된 계정' // ← 추가(원하면)
          : '지원하기',
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
      ),
    ),
  );
}

  void _showReportDialog() {
  final TextEditingController _reasonDetailController = TextEditingController();
  String? _selectedCategory;

  final List<String> reasonCategories = [
    '사기 또는 허위 공고',
    '불법 또는 음란성 콘텐츠',
    '중복/도배/광고성',
    '연락 불가/잠수',
    '기타'
  ];

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('공고 신고하기'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('문제가 되는 내용을 선택해주세요.\n운영팀이 확인 후 24시간 이내 조치합니다.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            onChanged: (val) => _selectedCategory = val,
            items: reasonCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            decoration: const InputDecoration(
              labelText: '신고 사유',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonDetailController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '상세한 내용을 작성해주세요 (선택)',
              border: OutlineInputBorder(),
            ),
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
            final category = _selectedCategory;
            final detail = _reasonDetailController.text.trim();

            if (category == null || category.isEmpty) {
              _showSnack('신고 사유를 선택해주세요.');
              return;
            }

            final prefs = await SharedPreferences.getInstance();
            final userId = prefs.getInt('userId');
            final jobId = int.tryParse(widget.job.id.toString());

            if (userId != null && jobId != null) {
              Navigator.pop(context);
              await _submitReport(category, detail, jobId, userId);
            } else {
              _showSnack('로그인 정보 또는 공고 정보가 올바르지 않습니다.');
            }
          },
          child: const Text('신고하기'),
        ),
      ],
    ),
  );
}

Widget _buildReviewSummary() {
  if (reviewSummary == null) return const SizedBox();

  final tags = reviewSummary!['tags'] as Map<String, dynamic>;
  final satisfaction = reviewSummary!['satisfaction'] as Map<String, dynamic>;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('알바 후기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      const SizedBox(height: 10),

      // 🔹 태그 시각화
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tags.entries.take(5).map((entry) {
          return Chip(
            label: Text('${entry.key} (${entry.value})'),
            backgroundColor: Colors.grey.shade200,
            labelStyle: const TextStyle(fontSize: 13),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          );
        }).toList(),
      ),

      const SizedBox(height: 16),
      const Text('지원자 만족도', style: TextStyle(fontWeight: FontWeight.w600)),

      const SizedBox(height: 6),
      _buildProgressRow('추천해요', satisfaction['recommend'], Colors.orange),
      const SizedBox(height: 6),
      _buildProgressRow('만족해요', satisfaction['okay'], Colors.grey),
      const SizedBox(height: 6),
      _buildProgressRow('아쉬워요', satisfaction['bad'], Colors.grey[400]!),
    ],
  );
}

Widget _buildProgressRow(String label, int count, Color color) {
  final int total = (reviewSummary?['total'] ?? 0) as int;
  // 0으로 나눔 방지 + [0,1] 클램프
  final double percent = (total > 0) ? (count / total).clamp(0.0, 1.0) : 0.0;

  return Row(
    children: [
      SizedBox(
        width: 80,
        child: Text(label, style: const TextStyle(fontSize: 14)),
      ),
      Expanded(
        child: LinearProgressIndicator(
          value: percent,
          color: color,
          backgroundColor: Colors.grey[200],
          minHeight: 10,
        ),
      ),
      const SizedBox(width: 8),
      Text('$count명', style: const TextStyle(fontSize: 13)),
    ],
  );
}
  @override
  Widget build(BuildContext context) {
      final postedUtc = widget.job.postedAtUtc; // == widget.job.publishAt ?? widget.job.createdAt (둘 다 UTC)
  final postedLabel = widget.job.isScheduled ? '게시 예정' : '게시일';
     final List<String> imageUrls = widget.job.imageUrls
      .map((u) => u.startsWith('http') ? u : '$baseUrl$u')
      .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('공고 상세'),
        actions: [
         if (_shouldShowReportButton())
      IconButton(
        icon: const Icon(Icons.report, color: Colors.red),
        onPressed: () => _showReportDialog(),
      ),
        ],

      ),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                children: [
                  if (isClosed)
                    Container(
                      color: Colors.red.shade100,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.all(16),
                      child: const Text(
                        '⛔ 이 공고는 마감되었습니다.',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

               // 여러 장 이미지 캐러셀
if (widget.job.imageUrls.isNotEmpty)
  SizedBox(
    height: 200,
    child: PageView.builder(
      itemCount: widget.job.imageUrls.length,
      itemBuilder: (context, index) {
        final raw = widget.job.imageUrls[index];
        final fullUrl = raw.startsWith('http') ? raw : '$baseUrl$raw';

        return GestureDetector(
          onTap: () {
   Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => FullImageGalleryScreen(
      urls: imageUrls, // ✅ build 초반에 만든 정규화된 URL 리스트
      initialIndex: index, // ← 현재 보고 있던 장으로 시작
    ),
  ),
);

  

          },
          child: Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              image: DecorationImage(
                image: NetworkImage(fullUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    ),
  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.job.category,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.job.title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      postedLabel,
      style: const TextStyle(fontSize: 12, color: Colors.grey),
    ),
    const SizedBox(height: 2),
    Text(
      postedUtc != null
          ? DateFormat('yyyy-MM-dd HH:mm').format(postedUtc.toLocal())
          : '',
      style: const TextStyle(fontSize: 13, color: Colors.grey),
    ),
  ],
)
                      ],
                    ),
                  ),
                  const Divider(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoRow(
                          Icons.monetization_on,
                          '${NumberFormat('#,###').format(int.tryParse(widget.job.pay) ?? 0)}원 (${widget.job.payType})',
                        ),
                        const SizedBox(height: 8),
_infoRow(
  Icons.calendar_today,
  _getWorkingPeriodText(widget.job),
),
                        const SizedBox(height: 8),
                        _infoRow(Icons.access_time, widget.job.workingHours),
                        const SizedBox(height: 16),
                        Text(
                          widget.job.description ?? '상세 설명이 없습니다.',
                          style: const TextStyle(fontSize: 14, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                             Icon(
                              Icons.remove_red_eye,
                              size: 24, // 기존 20 → 24로 키움
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$viewCount',
                              style: const TextStyle(
                                fontSize: 13, // 텍스트도 1정도 키워도 균형 좋아짐
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 12),
                             Icon(
                              Icons.bookmark,
                              size: 24, // 기존 20 → 24
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$bookmarkCount',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.group,
                              size: 20,
                              color: Colors.blueAccent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '지원자 $applicantCount명',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 32),
                  if (widget.job.lat != 0 && widget.job.lng != 0)
                    Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '근무 위치',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
         Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => FullMapScreen(
      lat: double.parse(widget.job.lat.toString()),
      lng: double.parse(widget.job.lng.toString()),
      address: widget.job.location?.toString(),
    ),
  ),
);

          },
                            child: Container(
                              height: 200,
                              width: double.infinity,
                               decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
                              child: Stack(
                                children: [
SizedBox(
  height: 200,
  child: Stack(
    clipBehavior: Clip.none,
    children: [
      // 1) 지도
      Positioned.fill(
        child: km.KakaoMap(
          initialPosition: km.LatLng(
            latitude: double.parse(widget.job.lat.toString()),
            longitude: double.parse(widget.job.lng.toString()),
          ),
          initialLevel: 17,
          onMapCreated: (c) async {
            final pos = km.LatLng(
              latitude: double.parse(widget.job.lat.toString()),
              longitude: double.parse(widget.job.lng.toString()),
            );
            await c.moveCamera(
              cameraUpdate: km.CameraUpdate.fromLatLng(pos),
              animation: const km.CameraAnimation(
                duration: 300, autoElevation: true, isConsecutive: false),
            );
          },
        ),
      ),

      // 2) 아무 곳이나 탭 → 풀맵 화면
      Positioned.fill(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
           onTap: () {
  final lat = double.parse(widget.job.lat.toString());
  final lng = double.parse(widget.job.lng.toString());
  final address = widget.job.location?.toString().trim(); // ← 사람이 읽을 주소

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FullMapScreen(
        lat: lat,
        lng: lng,
        address: (address?.isNotEmpty ?? false) ? address : null, // 전달!
      ),
    ),
  );
},
          ),
        ),
      ),

      // 3) 중앙 핀 (마커 대용)
      const Align(
        alignment: Alignment.center,
        child: IgnorePointer(
          child: Icon(Icons.location_pin, size: 32, color: Colors.red),
        ),
      ),

      // 4) 하단 주소 바 (Stack 안에 넣어 높이 초과 방지)
      Positioned(
        left: 8, right: 8, bottom: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  (widget.job.location?.toString().trim().isNotEmpty ?? false)
                      ? widget.job.location.toString().trim()
                      : '위치: ${double.parse(widget.job.lat.toString()).toStringAsFixed(6)}, '
                        '${double.parse(widget.job.lng.toString()).toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  ),
)
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                 InkWell(
  borderRadius: BorderRadius.circular(16),
  onTap: userType == 'worker' && widget.job.clientId != null
      ? () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClientProfileScreen(
                clientId: widget.job.clientId!,
              ),
            ),
          );
        }
      : null,
  child: Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ===== 상단 프로필 헤더 =====
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 로고(원형 테두리)
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade200, width: 2),
              ),
              child: CircleAvatar(
                radius: 26,
                backgroundImage: clientProfile != null &&
                        clientProfile!['logo_url'] != null
                    ? NetworkImage(clientProfile!['logo_url'])
                    : null,
                child: (clientProfile == null ||
                        clientProfile!['logo_url'] == null)
                    ? const Icon(Icons.business, color: Colors.grey)
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            // 회사명/설명/배지
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 회사명
                  Text(
                    _getCompanyName(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // 배지 + 설명 한 줄
                  Row(
                    children: [
                      if (widget.job.isCertifiedCompany == true) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.verified, size: 14, color: Colors.green),
                              SizedBox(width: 4),
                              Text(
                                '안심기업',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          clientProfile?['description'] ?? widget.job.locationCity,
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 액션 (워커만)
            if (userType == 'worker') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FB),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      '사업자 정보',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                  ],
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 16),
        const Divider(height: 1),

        // ===== 하단 통계 카드 2개 =====
        const SizedBox(height: 12),
        Row(
          children: [
            // 등록한 공고
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    if (userType == 'worker' && widget.job.clientId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ClientJobListScreen(
                            clientId: widget.job.clientId!,
                          ),
                        ),
                      );
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.assignment_outlined,
                          size: 24,
                          color: Colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${clientProfile?['job_count'] ?? 0}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '등록한 공고',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 채용 확정
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_outline,
                        size: 24,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${clientProfile?['hire_count'] ?? 0}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '채용 확정',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
        const Divider(height: 1),

        // 리뷰 요약 섹션(기존 함수 사용)
        const SizedBox(height: 12),
        _buildReviewSummary(),
      ],
    ),
  ),
)
                ],
              ),
      bottomNavigationBar: userType == 'worker' ? _buildApplyButton() : null,
    );
  }
}

class _ImagesCarousel extends StatelessWidget {
  final List<String> imageUrls;
  final String baseUrl;

  const _ImagesCarousel({
    Key? key,
    required this.imageUrls,
    required this.baseUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final normalizedUrls = imageUrls
        .map((u) => u.startsWith('http') ? u : '$baseUrl$u')
        .toList();

    return SizedBox(
      height: 200,
      child: PageView.builder(
        itemCount: normalizedUrls.length,
        itemBuilder: (context, index) {
          final fullUrl = normalizedUrls[index];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FullImageGalleryScreen(
                    urls: normalizedUrls,
                    initialIndex: index,
                  ),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                image: DecorationImage(
                  image: NetworkImage(fullUrl),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}


class MapWithSafeMarker extends StatefulWidget {
  final double lat, lng;
  const MapWithSafeMarker({super.key, required this.lat, required this.lng});
  @override
  State<MapWithSafeMarker> createState() => _MapWithSafeMarkerState();
}

class _MapWithSafeMarkerState extends State<MapWithSafeMarker> {
  km.KakaoMapController? _c;
  bool _done = false;

  Future<void> _place() async {
    if (_c == null || _done) return;

    // 1) 프레임이 실제로 붙을 때까지 대기
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // 사이즈 0이면 또 대기
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.height < 10) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    final pos = km.LatLng(latitude: widget.lat, longitude: widget.lng);

    // 2) 최대 10회, 100ms 간격 재시도
    Exception? last;
    for (var i = 0; i < 10; i++) {
      try {
        // 레이어 “워밍업” (엔진 쿡 찌르기)
        await _c!.setPoiVisible(isVisible: true);

        await _c!.moveCamera(
          cameraUpdate: km.CameraUpdate.fromLatLng(pos),
          animation: const km.CameraAnimation(
            duration: 200, autoElevation: true, isConsecutive: false),
        );

        await _c!.addMarker(
          markerOption: km.MarkerOption(
            id: 'one_pin',
            latLng: pos,
          ),
        );

        // (시각 확인용) 인포윈도우
        await _c!.addInfoWindow(
          infoWindowOption: km.InfoWindowOption(
            id: 'iw_one_pin',
            latLng: pos,
            title: '여기',
          ),
        );

        _done = true;
        return;
      } catch (e) {
        last = e is Exception ? e : Exception(e.toString());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    debugPrint('[KAKAO] still failing: $last');
  }

  @override
  Widget build(BuildContext context) {
    final pos = km.LatLng(latitude: widget.lat, longitude: widget.lng);
    return SizedBox(
      height: 200, // 0이 아니게 확실히 고정
      child: km.KakaoMap(
        initialPosition: pos,
        initialLevel: 17,
        onMapCreated: (c) {
          _c = c;
          WidgetsBinding.instance.addPostFrameCallback((_) => _place());
        },
      ),
    );
  }
}
