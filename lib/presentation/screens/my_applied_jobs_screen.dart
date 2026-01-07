// MyAppliedJobsScreen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../config/constants.dart';
import '../../data/models/job.dart';
import 'job_detail_screen.dart';
import '../chat/chat_room_screen.dart';
import '../../data/services/job_service.dart';
const kBrandBlue = Color(0xFF3B8AFF);

class MyAppliedJobsScreen extends StatefulWidget {
  const MyAppliedJobsScreen({super.key});

  @override
  State<MyAppliedJobsScreen> createState() => _MyAppliedJobsScreenState();
}

class _MyAppliedJobsScreenState extends State<MyAppliedJobsScreen> {
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
  String filterStatus = '전체'; // 전체 | active | closed
  String searchQuery = '';

  // Review status
  Map<String, bool> reviewStatusMap = {};
List<dynamic> _extractBookmarkList(dynamic decoded) {
  dynamic v = decoded;

  // 흔한 래핑 케이스들 처리
  if (v is Map) {
    v = v['data'] ?? v['result'] ?? v;
    if (v is Map) {
      v = v['bookmarks'] ??
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
int _payToInt(String s) {
  final onlyNum = s.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(onlyNum) ?? 0;
}

String _fmtPay(String s) {
  final n = _payToInt(s);
  if (n <= 0) return s; // 혹시 이상한 값이면 원본 유지
  return NumberFormat('#,###').format(n);
}
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadHiddenIds();
      await _loadAll();
    });
  }

  Future<void> _loadAll() async {
    setState(() => isLoading = true);
    await Future.wait([
      _loadAppliedJobs(),
      _loadBookmarkedJobs(),
    ]);
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
Future<Job?> _fetchJobById(String jobId, {String? token}) async {
  final headers = <String, String>{
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  final candidates = <Uri>[
    Uri.parse('$baseUrl/api/job/$jobId'),
    Uri.parse('$baseUrl/api/job/detail?jobId=$jobId'),
    Uri.parse('$baseUrl/api/job/get?jobId=$jobId'),
    Uri.parse('$baseUrl/api/job/get_job?jobId=$jobId'),
    Uri.parse('$baseUrl/api/job/job-detail?jobId=$jobId'),
  ];

  for (final uri in candidates) {
    try {
      final res = await http.get(uri, headers: headers);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        // 서버가 {job:{...}} / {...} 둘 다 가능하게
        final Map<String, dynamic>? map = (decoded is Map && decoded['job'] is Map)
            ? Map<String, dynamic>.from(decoded['job'])
            : (decoded is Map ? Map<String, dynamic>.from(decoded) : null);

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
      _showErrorSnackbar('로그인이 필요합니다. 다시 로그인해주세요.');
      appliedJobs = [];
      return;
    }

    // ✅ 너 기존 코드 그대로 유지 (endpoint 주의!)
    // 너는 위에서 /api/applications/my-jobs 를 쓰고 있는데
    // 다른 화면에서는 /api/apply/my-jobs 도 쓰더라. 프로젝트 기준에 맞춰 하나로 통일해.
    final url = Uri.parse('$baseUrl/api/applications/my-jobs?workerId=$workerId');

    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);

        final jobs = List<Job>.from(
          raw
              .map((item) => Job.fromJson(item))
              .where((job) => job.status != 'deleted'),
        );

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
    final token = prefs.getString('authToken');

    if (userId == null) {
      _showErrorSnackbar('로그인 정보가 없습니다. 다시 로그인해주세요.');
      return;
    }

    final uri = Uri.parse('$baseUrl/api/bookmark/remove');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'userId': userId, 'jobId': job.id}),
    );

    if (res.statusCode == 200) {
      bookmarkedJobs.removeWhere((j) => j.id == job.id);
      _applyFilters();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('찜에서 해제했어요.')),
      );
    } else {
      _showErrorSnackbar('찜 해제에 실패했습니다. (${res.statusCode})');
    }
  } catch (e) {
    _showErrorSnackbar('찜 해제 중 오류가 발생했습니다: $e');
  }
}
List<Map<String, dynamic>> _extractJobsList(dynamic decoded) {
  dynamic v = decoded;

  // 흔한 래핑 케이스들 처리
  if (v is Map) {
    v = v['data'] ?? v['result'] ?? v;
    if (v is Map) {
      v = v['bookmarks'] ??
          v['items'] ??
          v['results'] ??
          v['jobs'] ??
          v['list'] ??
          v;
    }
  }

  if (v is! List) return [];

  final out = <Map<String, dynamic>>[];
  for (final e in v) {
    if (e is Map) {
      out.add(Map<String, dynamic>.from(e));
    }
  }
  return out;
}

Future<void> _loadBookmarkedJobs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    final token = prefs.getString('authToken');

    if (userId == null) {
   
      bookmarkedJobs = [];
      return;
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    final candidates = <Uri>[
      Uri.parse('$baseUrl/api/bookmark/list?userId=$userId'),
      Uri.parse('$baseUrl/api/bookmark/list?workerId=$userId'),
      Uri.parse('$baseUrl/api/bookmark/list?worker_id=$userId'),
    ];

    http.Response? resp200;
    for (final uri in candidates) {
      final r = await http.get(uri, headers: headers);
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
      final maps = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      jobs = maps.map((m) => Job.fromJson(m)).toList();
    } 
    // ✅ 2) jobId만 오는 경우 -> 상세 조회로 Job 리스트 만들기
    else if (list.isNotEmpty && (list.first is String || list.first is num)) {
      final ids = list.map((e) => e.toString()).toList();

      // 병렬로 가져오기 (수량 적으니 OK)
      final fetched = await Future.wait(ids.map((id) => _fetchJobById(id, token: token)));
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

  // ✅ 찜탭: deleted만 보여주기
  b = b.where((j) => j.status == 'deleted').toList();

  // ✅ 상태 필터: 찜탭에서는 의미 없으니 applied에만 적용
  if (filterStatus != '전체') {
    a = a.where((j) => j.status == filterStatus).toList();
  }

  // 검색(둘 다 적용)
  if (searchQuery.trim().isNotEmpty) {
    final q = searchQuery.trim();
    a = a.where((j) => j.title.contains(q) || j.location.contains(q)).toList();
    b = b.where((j) => j.title.contains(q) || j.location.contains(q)).toList();
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

  Future<void> _confirmDelete(String jobId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('목록에서 숨기기'),
        content: const Text('이 항목을 목록에서 숨길까요?\n(내역은 이 기기에서만 숨겨져요)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('숨기기', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      hiddenJobIds.add(jobId);
      await _saveHiddenIds();
      _applyFilters();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('숨김 처리했어요.'),
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

  Future<void> _confirmCancel(Job job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지원 취소'),
        content: const Text('이 공고 지원을 취소할까요?\n취소 후 다시 지원하려면 새로 지원해야 할 수 있어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('닫기')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('지원 취소', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _cancelApplication(job);
    }
  }

  Future<void> _cancelApplication(Job job) async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');
    final token = prefs.getString('authToken');

    if (workerId == null || token == null) {
      _showErrorSnackbar('로그인 정보가 없습니다. 다시 로그인해주세요.');
      return;
    }

    final uri = Uri.parse('$baseUrl/api/applications/cancel');

    try {
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'jobId': job.id, 'workerId': workerId}),
      );

      if (res.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지원이 취소되었습니다.')));
        await _loadAppliedJobs();
        _applyFilters();
      } else {
        _showErrorSnackbar('지원 취소에 실패했습니다. (${res.statusCode})');
      }
    } catch (e) {
      _showErrorSnackbar('지원 취소 중 오류가 발생했습니다: $e');
    }
  }

  Future<void> _openChatRoom(Job job) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';
    final uri = Uri.parse('$baseUrl/api/chat/get-room-by-id?jobId=${job.id}&workerId=${job.workerId}');

    try {
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final chatRoomId = data['chatRoomId'];
        final jobInfo = Map<String, dynamic>.from(data['jobInfo']);

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatRoomScreen(chatRoomId: chatRoomId, jobInfo: jobInfo)),
        );
      } else {
        _showErrorSnackbar('채팅방 정보 요청 실패 (${res.statusCode})');
      }
    } catch (e) {
      _showErrorSnackbar('네트워크 오류: $e');
    }
  }

  // ---------------------------
  // UI bits (스샷 톤)
  // ---------------------------
  Widget _headerSearch() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFDDEBFF),
      ),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE6ECF5)),
        ),
        child: TextField(
          onChanged: (v) {
            searchQuery = v;
            _applyFilters();
          },
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, color: Color(0xFF9AA7B2)),
            hintText: '제목 또는 지역 검색',
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            isDense: true,
          ),
        ),
      ),
    );
  }

  Widget _topTabs() {
    final appliedCount = filteredApplied.length;
    final bookmarkedCount = filteredBookmarked.length;

    Widget tabItem({required int idx, required String title, String? sub}) {
      final selected = _tabIndex == idx;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tabIndex = idx),
          child: SizedBox(
            height: 44,
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
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected ? Colors.black87 : Colors.black54,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        sub,
                        style: const TextStyle(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.w600),
                      ),
                    ],
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
            tabItem(idx: 0, title: '지원 현황', sub: null),
            tabItem(idx: 1, title: '찜한 공고', sub: '(${bookmarkedCount}건)'),
          ],
        ),
        Container(height: 1, color: const Color(0xFFE7E7E7)),
      ],
    );
  }

  Widget _statusChips() {
    Widget chip(String key, String label) {
      final selected = filterStatus == key;
      return ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        selected: selected,
        onSelected: (_) {
          setState(() => filterStatus = key);
          _applyFilters();
        },
        selectedColor: const Color(0xFFE0E0E0),
        backgroundColor: Colors.white,
        side: BorderSide(color: selected ? Colors.transparent : const Color(0xFFD5D5D5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 10,
          children: [
            chip('전체', '전체'),
            chip('active', '채용 중'),
            chip('closed', '마감'),
          ],
        ),
      ),
    );
  }

  String _statusText(Job job) {
  if (job.status == 'deleted') return '삭제됨';
  if (job.status == 'active') return '채용중';
  if (job.status == 'hired' || job.status == 'confirmed') return '채용 확정';
  return '마감';
}

Color _statusColor(Job job) {
  if (job.status == 'deleted') return Colors.grey;
  if (job.status == 'active') return Colors.indigo;
  if (job.status == 'hired' || job.status == 'confirmed') return Colors.green;
  return Colors.grey;
}


  Widget _emptyView({required bool forBookmark}) {
    final title = forBookmark ? '찜한 공고가 아직 없어요.' : '아직 지원한 알바가 없어요.';
    final desc = forBookmark ? '마음에 드는 공고를 하트로 저장해두면\n나중에 빠르게 다시 볼 수 있어요.' : '지금 바로 동네 알바를 찾아볼까요?';
    final cta = forBookmark ? '공고 둘러보기' : '공고보러 가기';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                onPressed: () {
                  // 홈으로 보내는 안전한 기본 동작
                  Navigator.popUntil(context, (r) => r.isFirst);
                },
                child: Text(cta, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobRow(Job job, {required bool bookmarkedTab}) {
    final reviewKey = '${job.clientId}-${job.title}';
    final reviewed = reviewStatusMap[reviewKey] == true;
final isDeleted = job.status == 'deleted';
    final appliedAt = job.createdAt != null ? DateFormat('MM.dd').format(job.createdAt!) : '';
    final start = job.startDate != null ? DateFormat('MM.dd').format(job.startDate!) : '';
    final end = job.endDate != null ? DateFormat('MM.dd').format(job.endDate!) : '';

    final statusText = _statusText(job);
    final statusColor = _statusColor(job);

    // 이미지 (있으면)
    Widget thumb() {
      final hasImage = job.imageUrls.isNotEmpty;
      if (!hasImage) return const SizedBox(width: 74, height: 74);
      final raw = job.imageUrls.first;
      final url = raw.startsWith('http') ? raw : '$baseUrl$raw';

      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: 74,
          height: 74,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 74,
            height: 74,
            color: const Color(0xFFF2F4F7),
            child: const Icon(Icons.image_not_supported_outlined, color: Colors.black26),
          ),
        ),
      );
    }

  return InkWell(
  onTap: (bookmarkedTab && isDeleted)
      ? null
      : () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
          );
        },
     child: Opacity(
        opacity: (bookmarkedTab && isDeleted) ? 0.55 : 1.0,
         child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // location + status
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 16, color: kBrandBlue),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          job.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: Colors.black54, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(color: statusColor, fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  Text(
                    job.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),

                  Text(
                    '$start ~ $end  ·  ${job.workingHours}',
                    style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),

                if (job.pay.isNotEmpty)
  Text(
    '${job.payType} ${_fmtPay(job.pay)}원${bookmarkedTab ? '' : '   ·   지원일 $appliedAt'}',
    style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w700),
  ),

                  const SizedBox(height: 10),

                  // Bottom actions (지원현황 탭에서만)
                  if (!bookmarkedTab)
                    Row(
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _confirmCancel(job),
                          icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                          label: const Text('지원 취소', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: reviewed
                              ? null
                              : () {
                                  Navigator.pushNamed(
                                    context,
                                    '/review',
                                    arguments: {
                                      'jobId': job.id,
                                      'clientId': job.clientId,
                                      'jobTitle': job.title,
                                      'companyName': job.company,
                                    },
                                  );
                                },
                          icon: Icon(Icons.edit_note, size: 18, color: reviewed ? Colors.grey : kBrandBlue),
                          label: Text(
                            reviewed ? '후기 작성 완료' : '후기 남기기',
                            style: TextStyle(color: reviewed ? Colors.grey : kBrandBlue, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Right: image + heart
            Stack(
              children: [
                thumb(),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    bookmarkedTab ? Icons.favorite : Icons.favorite_border,
                    color: bookmarkedTab ? kBrandBlue : Colors.black26,
                    size: 22,
                  ),
                ),
              ],
            ),

            // trailing actions (chat/hide)
            const SizedBox(width: 6),
         Column(
  children: [
    if (bookmarkedTab && isDeleted) ...[
      IconButton(
        icon: const Icon(Icons.favorite, size: 22),
        color: Colors.redAccent,
        tooltip: '찜 해제',
        onPressed: () => _removeBookmark(job),
      ),
    ] else ...[
      IconButton(
        icon: const Icon(Icons.chat_bubble_outline, size: 20),
        color: Colors.indigo,
        tooltip: '채팅하기',
        onPressed: () => _openChatRoom(job),
      ),
      IconButton(
        icon: const Icon(Icons.delete_outline, size: 22),
        color: Colors.redAccent,
        tooltip: '목록에서 숨기기',
        onPressed: () => _confirmDelete(job.id),
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

  // ---------------------------
  // Build
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final list = _tabIndex == 0 ? filteredApplied : filteredBookmarked;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          iconTheme: const IconThemeData(color: Colors.black),
          title: const Text(
            '내 활동',
            style: TextStyle(
              fontFamily: 'Jalnan2TTF',
              color: kBrandBlue,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          actions: [
            IconButton(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh, color: Colors.black54),
              tooltip: '새로고침',
            ),
          ],
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _headerSearch(),
                  _topTabs(),
                  _statusChips(),
                  Expanded(
                    child: list.isEmpty
                        ? _emptyView(forBookmark: _tabIndex == 1)
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1),
                            itemBuilder: (context, i) => _jobRow(
                              list[i],
                              bookmarkedTab: _tabIndex == 1,
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
