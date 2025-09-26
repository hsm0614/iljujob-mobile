import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/job.dart';
import '../../data/services/job_service.dart';
import 'package:iljujob/config/constants.dart';
import 'package:http/http.dart' as http;
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:iljujob/data/services/ai_api.dart';
import 'package:iljujob/widget/recommended_workers_sheet.dart'; // 앞서 만든 바텀시트 위젯
import '../../data/services/ai_api.dart';

class ClientHomeScreen extends StatefulWidget {
  final AiApi api; // 👈 추가

  const ClientHomeScreen({
    super.key,
    required this.api, // 👈 추가
  });

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}
DateTime _nowLocal() => DateTime.now();

bool isJobReserved(Job j) =>
    j.publishAt != null && j.publishAt!.isAfter(_nowLocal());

bool isJobPinned(Job j) =>
    j.pinnedUntil != null && j.pinnedUntil!.isAfter(_nowLocal());

String pinnedRemainText(Job j) {
  if (!isJobPinned(j)) return '';
  final diff = j.pinnedUntil!.difference(_nowLocal());
  final h = diff.inHours;
  final m = diff.inMinutes % 60;
  return h > 0 ? '고정 ${h}시간 ${m}분 남음' : '고정 ${m}분 남음';
}
class _ClientHomeScreenState extends State<ClientHomeScreen>
    with SingleTickerProviderStateMixin {
  List<Job> myJobs = [];
  bool isLoading = false;
  String filterStatus = '전체';
  String sortType = '최신순';
  String payTypeFilter = '전체';
  bool compactView = false;
  String searchQuery = '';

  int todayCount = 0;
  int weekCount = 0;
  int monthCount = 0;
  late TabController _tabController;
  bool isSafeCompany = false;
  
  @override
  void initState() {
    super.initState();
    _requestNotificationPermission(); // ✅ 알림 권한 요청
    _saveClientFcmToken(); // ✅ FCM 토큰 저장 추가 (여기!)
    _fetchClientProfile(); // ✅ 클라이언트 프로필 가져오기
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 0) {
        setState(() => payTypeFilter = '전체');
      } else if (_tabController.index == 1) {
        setState(() => payTypeFilter = '일급');
      } else {
        setState(() => payTypeFilter = '주급');
      }
    });
    if (myJobs.isEmpty) {
      _loadMyJobs();
    }
    _loadSummaryData(); // ← 이걸 추가해야 요약 데이터도 가져옴
  }

  void _requestNotificationPermission() async {
    if (!Platform.isAndroid) return; // ✅ iOS는 바로 리턴

    final settings = await FirebaseMessaging.instance.requestPermission();

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
    } else {}
  }
Future<void> _fetchClientProfile() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken');

  final response = await http.get(
    Uri.parse('$baseUrl/api/client/profile'),
    headers: {'Authorization': 'Bearer $token'},
  );

  if (response.statusCode == 200) {
    final raw = jsonDecode(response.body);
    final data = raw['data'] ?? raw;

    final String? certUrl = data['business_certificate_url'] as String?;

    setState(() {
      isSafeCompany = certUrl != null && certUrl.isNotEmpty;
    });
  } else {
    print('❌ 클라이언트 프로필 조회 실패: ${response.statusCode}');
  }
}
  Future<void> retryFcmTokenSend() async {
    final token = await FirebaseMessaging.instance.getToken();

    if (token == null) {
      print('❌ 토큰 없음');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final userPhone = prefs.getString('userPhone');
      final userType = prefs.getString('userType');

      final response = await http.post(
        Uri.parse('$baseUrl/api/user/update-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userPhone': userPhone,
          'userType': userType,
          'fcmToken': token,
        }),
      );
    } catch (e) {
      print('❌ 토큰 전송 실패: $e');
    }
  }

  Future<void> _saveClientFcmToken() async {
    if (!Platform.isAndroid) return;

    final token = await FirebaseMessaging.instance.getToken();

    if (token == null) {
      print("❌ [도급사] 토큰이 null입니다");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('userPhone');

    if (phone == null || phone.isEmpty) {
      print('❌ [도급사] userPhone 없음, FCM 저장 생략');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/update-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userPhone': phone,
          'userType': 'client',
          'fcmToken': token,
        }),
      );

      if (response.statusCode == 200) {
      } else {
        print('❌ [도급사] FCM 토큰 저장 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [도급사] 예외 발생: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

 Future<void> _loadMyJobs() async {
  if (isLoading) return;
  setState(() => isLoading = true);

  try {
    final prefs = await SharedPreferences.getInstance();
    final int? clientId = prefs.getInt('userId'); // ✅ clientId 사용
    if (clientId == null) {
      if (kDebugMode) debugPrint('❌ clientId 없음');
      return;
    }

    // 서버 조회
    final data = await JobService.fetchJobs(clientId: clientId);

    // 1) 삭제 제외만 적용 (정렬은 하지 않음!)
    var validJobs = data.where((j) => j.status != 'deleted').toList();

    // 2) (선택) 혹시 중복 id가 올 수 있으면 중복 제거
    // final map = <int, Job>{ for (final j in validJobs) j.id: j };
    // validJobs = map.values.toList();

    if (!mounted) return;
    setState(() {
      myJobs = validJobs; // ✅ 정렬하지 않고 그대로 저장
    });

    if (kDebugMode) {
      for (final j in validJobs.take(5)) {
      }
    }
  } catch (e, st) {
    if (kDebugMode) {

    }
  } finally {
    if (mounted) setState(() => isLoading = false); // ✅ 항상 내려주기
  }
}

  Future<void> _loadSummaryData() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getInt('userId') ?? 0;
    if (clientId == 0) return;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/client/summary?clientId=$clientId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          todayCount = data['todayApplicants'] ?? 0;
          weekCount = data['weekApplicants'] ?? 0;
          monthCount = data['monthApplicants'] ?? 0;
        });
      }
    } catch (e) {

    }
  }

List<Job> _filteredJobs() {
  // ---- 로컬 헬퍼들 (이 함수 안에서만 사용) ----
  DateTime _asLocal(DateTime? dt) =>
      dt == null ? DateTime.fromMillisecondsSinceEpoch(0) : (dt.isUtc ? dt.toLocal() : dt);

  // 게시일: publishAt 우선, 없으면 createdAt → 항상 로컬 DateTime
  DateTime _postedAt(Job j) => _asLocal(j.publishAt ?? j.createdAt);

  // 급여 안전 파싱 ("100,000원"도 OK)
  int _payToInt(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  // id 정렬용(타이브레이커)
  int _idInt(Job j) => int.tryParse(j.id.toString()) ?? 0;

  // 제목/지역 검색(대소문자/공백 무시)
bool _matchesQuery(Job j, String q) {
  final qq = q.trim().toLowerCase();
  if (qq.isEmpty) return true;

  // 안전 소문자 변환
  String lc(Object? s) => (s?.toString() ?? '').toLowerCase();

  return lc(j.title).contains(qq) ||
         lc(j.location).contains(qq) ||
         lc((j as dynamic).locationCity).contains(qq) ||   // 모델에 있으면 유지, 없으면 이 줄 삭제
         lc((j as dynamic).description).contains(qq);       // 모델에 있으면 유지, 없으면 이 줄 삭제
}
  // ---- 원본 보호 ----
  var filtered = List<Job>.of(myJobs);

  // 상태 필터
  if (filterStatus == '공고중') {
    filtered = filtered.where((j) => j.status == 'active').toList();
  } else if (filterStatus == '마감') {
    filtered = filtered.where((j) => j.status == 'closed').toList();
  }

  // 급여 타입 필터
  if (payTypeFilter != '전체') {
    filtered = filtered.where((j) => j.payType == payTypeFilter).toList();
  }

  // 검색
  if (searchQuery.trim().isNotEmpty) {
    filtered = filtered.where((j) => _matchesQuery(j, searchQuery)).toList();
  }

  // 정렬 (⚠️ 핀/상단고정은 전혀 고려하지 않음)
  switch (sortType) {
    case '급여 높은 순':
      filtered.sort((a, b) {
        final cmp = _payToInt(b.pay).compareTo(_payToInt(a.pay));
        if (cmp != 0) return cmp;
        // 동률이면 최신순 → 같은 시간엔 id 내림차순
        final t = _postedAt(b).compareTo(_postedAt(a));
        if (t != 0) return t;
        return _idInt(b).compareTo(_idInt(a));
      });
      break;

    case '오래된 순':
      filtered.sort((a, b) {
        final cmp = _postedAt(a).compareTo(_postedAt(b)); // 오래된 순(오름차순)
        if (cmp != 0) return cmp;
        // 동률이면 id 내림차순(리스트 흔들림 방지)
        return _idInt(b).compareTo(_idInt(a));
      });
      break;

    default: // 최신순
      filtered.sort((a, b) {
        final cmp = _postedAt(b).compareTo(_postedAt(a)); // 최신순(내림차순)
        if (cmp != 0) return cmp;
        // 동률이면 id 내림차순
        return _idInt(b).compareTo(_idInt(a));
      });
      break;
  }

  // 디버그: 로컬 기준으로 찍기 (UTC처럼 보이면 헷갈림)
  for (final j in filtered) {
    final raw = j.publishAt ?? j.createdAt;
    final local = _postedAt(j);
  }

  return filtered;
}
Future<void> _openRecommendedWorkersByJobId(String jobIdStr) async {
  final jid = int.tryParse(jobIdStr);
  if (jid == null) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('잘못된 공고 ID 입니다.')),
    );
    return;
  }

  // ✅ 구독 확인
  final api = AiApi(baseUrl);
  final sub = await api.fetchMySubscription();
  final isSubscribed = sub.active && (sub.plan != null && sub.plan!.toLowerCase() != 'free');

  if (!isSubscribed) {
    if (!mounted) return;
    await _showPaywall();                 // 결제 유도 모달
    return;                               // 🔒 여기서 종료
  }

  if (!mounted) return;
  // ✅ 통과하면 시트 열기
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.90,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Material(
          color: Colors.white,
          child: RecommendedWorkersSheet(
            api: AiApi(baseUrl),
            jobId: jid,
          ),
        ),
      ),
    ),
  );
}
Future<void> _showPaywall() async {
  if (!mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,                 // ✅ 시스템 인셋 자동 반영
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      final bottomInset = mq.viewInsets.bottom;  // 키보드
      final bottomPad   = mq.padding.bottom;     // 제스처/3버튼 네비 바

      return FractionallySizedBox(
        
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Material(
            color: Colors.white,
            child: SafeArea(
              top: false, // 상단은 둥근 모서리 살리기
              child: SingleChildScrollView(
                // ✅ 하단이 겹치지 않도록 여유 패딩 추가
                padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset + bottomPad),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 32, color: Color(0xFF4F46E5)),
                    const SizedBox(height: 8),
                    const Text('맞춤 인재 보기는 구독 전용',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text(
                      'AI가 공고와 잘 맞는 인재를 추천합니다.\n구독 후 이용해 보세요!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('나중에'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.pushNamed(context, '/subscribe');
                            },
                            child: const Text('구독하기', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}


  @override
  Widget build(BuildContext context) {
    final jobs = _filteredJobs();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
       title: Text( // ❌ const 제거
  '알바일주 사장님',
  style: TextStyle(
    fontFamily: 'Jalnan2TTF', // ✅ 폰트명 명시
    color: Color(0xFF3B8AFF),
 
    fontSize: 20,
  ),
),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.black,
          tabs: const [Tab(text: '전체'), Tab(text: '일급'), Tab(text: '주급')],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final clientId = prefs.getInt('userId');

              if (clientId == null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('로그인 정보가 없습니다')));
                return;
              }

              try {
                final response = await http.get(
                  Uri.parse(
                    '$baseUrl/api/client/business-info-status?clientId=$clientId',
                  ),
                );

                if (response.statusCode == 200) {
                  final data = jsonDecode(response.body);
                  final hasInfo = data['hasInfo'] == true;
                  final needsUpdate = data['needsUpdate'] == true;

                  if (hasInfo && !needsUpdate) {
                    Navigator.pushNamed(context, '/post_job');
                  } else {
                    Navigator.pushNamed(context, '/client_business_info');
                  }
                } else {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('사업자 정보 확인 실패')));
                }
              } catch (e) {
                print('❌ 사업자 확인 오류: $e');
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('서버 통신 오류')));
              }
            },
            icon: const Icon(Icons.add_circle_outline, color: Colors.indigo),
            label: const Text(
              '공고 등록',
              style: TextStyle(
                color: Colors.indigo,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: TextButton.styleFrom(foregroundColor: Colors.indigo),
          ),
        ],
      ),
     body: CustomScrollView(
  slivers: [
    // 1) 요약 섹션 (오늘/이번주/이번달) — 고정 아님, 스크롤되며 사라짐
    SliverToBoxAdapter(child: _buildSummarySection()),

    // 2) 안심기업 배너 (조건부)
    if (!isSafeCompany)
  SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // 전체 여백 줄임
      child: Container(
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.shade300),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // 내부 여백 줄임
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, color: Colors.orange, size: 18), // 아이콘 작게
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '🔒 안심기업 인증 시\n지원율이 올라갑니다!',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500), // 폰트 작게
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // 버튼 여백 축소
                minimumSize: Size.zero,
              ),
              onPressed: () {
                Navigator.pushNamed(context, '/edit_profile');
              },
              child: const Text('인증', style: TextStyle(fontSize: 13)), // 버튼 텍스트 작게
            ),
          ],
        ),
      ),
    ),
  ),


    // 3) 검색 + 필터 + 정렬/뷰토글 블록 — 일단 고정 아님 (다음 단계에서 고정으로 바꿀 수 있음)
    // 🔒 3-A) 검색창만 고정
SliverPersistentHeader(
  pinned: true,
  floating: false,
  delegate: _SearchHeaderDelegate(
    minExtent: 50,
    maxExtent: 50,
    child: Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        style: const TextStyle(fontSize: 14), // 입력 글자 크기
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search, size: 20), // 아이콘 크기 조정
          hintText: '공고 제목 또는 지역 검색',
          hintStyle: TextStyle(fontSize: 14, color: Colors.grey), // 힌트 글자 크기
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (val) => setState(() => searchQuery = val),
      ),
    ),
  ),
),
// 🧱 3-B) 필터칩 + 정렬/뷰토글 (고정 아님)
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('전체'),
              selected: filterStatus == '전체',
              onSelected: (_) => setState(() => filterStatus = '전체'),
            ),
            FilterChip(
              label: const Text('공고중'),
              selected: filterStatus == '공고중',
              onSelected: (_) => setState(() => filterStatus = '공고중'),
            ),
            FilterChip(
              label: const Text('마감'),
              selected: filterStatus == '마감',
              onSelected: (_) => setState(() => filterStatus = '마감'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            DropdownButton<String>(
              value: sortType,
              items: ['최신순', '오래된 순', '급여 높은 순']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (val) => setState(() => sortType = val!),
            ),
            IconButton(
              icon: Icon(compactView ? Icons.view_agenda : Icons.view_list),
              onPressed: () => setState(() => compactView = !compactView),
            ),
          ],
        ),
      ],
    ),
  ),
),

    // 4) 리스트 영역
    if (isLoading)
      const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      )
    else if (jobs.isEmpty)
      const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text('등록한 공고가 없습니다 📝')),
      )
    else
      SliverList.builder(
        itemCount: jobs.length,
        itemBuilder: (context, index) =>
            compactView ? _buildCompactJobCard(jobs[index])
                        : _buildJobCard(jobs[index]),
      ),
  ],
),

    );
  }

  Widget _buildSummarySection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryCard('오늘 지원', todayCount, Colors.blue),
          _buildSummaryCard('이번 주', weekCount, Colors.green),
          _buildSummaryCard('이번 달', monthCount, Colors.orange),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, int count, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

Widget _buildCompactJobCard(Job job) {
  final formattedPay = NumberFormat('#,###').format(int.parse(job.pay));
  final nowUtc     = DateTime.now().toUtc();
  final isClosed   = job.status == 'closed';
  final isReserved = job.publishAt != null && job.publishAt!.isAfter(DateTime.now());
  final isPinned   = job.pinnedUntil != null && job.pinnedUntil!.isAfter(nowUtc);

  // 작은 알약형 배지
  Widget pill(String text, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.1,
              )),
        ],
      ),
    );
  }

  String pinRemain() {
    
    if (!isPinned) return '';
    final diff = job.pinnedUntil!.difference(nowUtc);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '고정 ${h}시간 ${m}분';
    return '고정 ${m}분';
  }

  return InkWell(
    onTap: () {
      Navigator.pushNamed(context, '/applicants', arguments: job.id);
    },
    child: Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        title: Row(
          children: [
            Expanded(
              child: Text(
                job.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: isClosed ? Colors.grey : Colors.black,
                  decoration: isClosed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 급여 타입 작은 배지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (job.payType == '주급'
                        ? Colors.green
                        : Colors.deepOrange)
                    .withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: job.payType == '주급'
                      ? Colors.green
                      : Colors.deepOrange,
                ),
              ),
              child: Text(
                job.payType,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: job.payType == '주급'
                      ? Colors.green.shade700
                      : Colors.deepOrange,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            // 상태 배지들
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (isReserved) pill('예약됨', Colors.orange, icon: Icons.schedule),
                if (isPinned)   pill('상단고정', Colors.deepOrange, icon: Icons.push_pin_outlined),
                if (isPinned)   pill(pinRemain(), Colors.deepOrange),
                if (isClosed)   pill('마감됨', Colors.grey, icon: Icons.stop_circle_outlined),
              ],
            ),
            if (isReserved || isPinned || isClosed) const SizedBox(height: 6),
            // 기본 정보
            Text('📍 ${job.location}', maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('💰 $formattedPay원 · ⏰ ${job.workingHours}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        // 우측 액션은 팝업 메뉴로 정리
        trailing: PopupMenuButton<String>(
          tooltip: '메뉴',
          itemBuilder: (context) => [
             if (isReserved) // ✅ 예약 상태에서만
  PopupMenuItem(
    value: 'publish-now',
    child: ListTile(
      dense: true,
      leading: Icon(Icons.flash_on, color: Colors.orange),
      title: const Text('즉시 게시'),
    ),
  ),
            if (!isClosed)
              const PopupMenuItem(value: 'edit', child: ListTile(
                dense: true, leading: Icon(Icons.edit), title: Text('수정'),
              )),
            const PopupMenuItem(value: 'detail', child: ListTile(
              dense: true, leading: Icon(Icons.info_outline), title: Text('상세보기'),
            )),
            const PopupMenuItem(value: 'applicants', child: ListTile(
              dense: true, leading: Icon(Icons.people), title: Text('지원자 보기'),
            )),
            if (isClosed)
              const PopupMenuItem(value: 'repost', child: ListTile(
                dense: true, leading: Icon(Icons.replay_circle_filled), title: Text('재공고'),
              )),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'delete', child: ListTile(
              dense: true, leading: Icon(Icons.delete, color: Colors.red), title: Text('삭제', style: TextStyle(color: Colors.red)),
            )),
          ],
          onSelected: (v) async {
            switch (v) {
              case 'edit':
                Navigator.pushNamed(context, '/edit_job', arguments: job.id);
                break;
                 case 'publish-now': // ✅ 즉시 게시
                try {
                await JobService.publishNow(int.parse(job.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('공고가 즉시 게시되었습니다.')),
                  );
                  _loadMyJobs(); // 리스트 새로고침
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('즉시 게시 실패: $e')),
                  );
                }
                break;
              case 'detail':
                Navigator.pushNamed(context, '/job-detail', arguments: job);
                break;
              case 'applicants':
                Navigator.pushNamed(context, '/applicants', arguments: job.id);
                break;
              case 'repost':
                Navigator.pushNamed(
                  context,
                  '/post_job',
                  arguments: {'isRepost': true, 'existingJob': job},
                );
                break;
              case 'delete':
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('공고 삭제'),
                    content: const Text('정말 이 공고를 삭제하시겠습니까?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                      TextButton(onPressed: () => Navigator.pop(context, true),  child: const Text('삭제')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await JobService.deleteJob(job.id);
                  _loadMyJobs();
                }
                break;
            }
          },
        ),
      ),
    ),
  );
}

Widget _buildJobCard(Job job) {
  final isWeekly   = job.payType == '주급';
  final formattedPay = NumberFormat('#,###').format(int.parse(job.pay));
  final isClosed   = job.status == 'closed';

  // 🔥 상단고정 여부 (서버 UTC 기준)
  final isPinned = job.pinnedUntil != null &&
      job.pinnedUntil!.isAfter(DateTime.now().toUtc());

  final titleStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: isClosed ? Colors.grey : Colors.black,
    decoration: isClosed ? TextDecoration.lineThrough : null,
  );

  // 🏷️ 작은 알약형 배지
  Widget pill(String text, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  String remainingPinText() {
    if (!isPinned) return '';
    final diff = job.pinnedUntil!.difference(DateTime.now().toUtc());
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '고정 ${h}시간 ${m}분 남음';
    return '고정 ${m}분 남음';
  }

  final bool isReserved =
      job.publishAt != null && job.publishAt!.isAfter(DateTime.now());

  return InkWell(
    onTap: () => Navigator.pushNamed(context, '/applicants', arguments: job.id),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⏱️ 예약/상단고정 배지 줄 (있을 때만)
          if (isReserved || isPinned || isClosed) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (isReserved) pill('예약됨', Colors.orangeAccent, icon: Icons.schedule),
                if (isPinned)   pill('상단고정', Colors.deepOrange, icon: Icons.push_pin_outlined),
                if (isPinned)   pill(remainingPinText(), Colors.deepOrange),
                if (isClosed)   pill('마감됨', Colors.grey, icon: Icons.stop_circle_outlined),
              ],
            ),
            const SizedBox(height: 6),
          ],

          // 제목 + 급여 태그
          Row(
            children: [
              Expanded(child: Text(job.title, style: titleStyle)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isWeekly
                      ? Colors.green.withOpacity(0.08)
                      : Colors.deepOrange.withOpacity(0.08),
                  border: Border.all(
                    color: isWeekly ? Colors.green : Colors.deepOrange,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  job.payType,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isWeekly ? Colors.green.shade700 : Colors.deepOrange,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Text('💰 $formattedPay원 · ⏰ ${job.workingHours}'),
          Text('📍 ${job.location} · ${job.category}'),

          if (job.description?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                job.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54),
              ),
            ),

          const SizedBox(height: 12),

          // 액션 버튼들
          Row(
            
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.info_outline),
                label: const Text('상세보기'),
                onPressed: () {
                  Navigator.pushNamed(context, '/job-detail', arguments: job);
                },
              ),
          if (isReserved)
  TextButton(
    style: TextButton.styleFrom(
      foregroundColor: Colors.orange, // 텍스트 색상
    ),
    onPressed: () async {
      try {
        await JobService.publishNow(int.parse(job.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공고가 즉시 게시되었습니다.')),
        );
        _loadMyJobs();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('즉시 게시 실패: $e')),
        );
      }
    },
    child: const Text('즉시 게시'),
  ), if (!isClosed)
  Tooltip(
    message: 'AI가 이 공고와 잘 맞는 인재를 추천해요',
    child: TextButton.icon(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.group_add_outlined),
          // ✨ 스파클
          const Positioned(
            left: -8, bottom: -8,
            child: Icon(Icons.auto_awesome, size: 14, color: Color(0xFF4F46E5)),
          ),
          // 🏷️ AI 배지
          Positioned(
            right: -10, top: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'AI',
                style: TextStyle(
                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
      label: const Text('맞춤 인재'),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF4F46E5),
      ),
   onPressed: () => _openRecommendedWorkersByJobId(job.id.toString()),
    ),
  ),

              IconButton(
                icon: const Icon(Icons.people),
                tooltip: '지원자 보기',
                onPressed: () {
                  Navigator.pushNamed(context, '/applicants', arguments: job.id);
                },
              ),

              // ✏️ 수정은 active일 때만
              if (!isClosed)
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: '수정',
                  onPressed: () {
                    Navigator.pushNamed(context, '/edit_job', arguments: job.id);
                  },
                ),

              // 🗑️ 삭제는 closed/active 모두 노출
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: '삭제',
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('공고 삭제'),
                      content: const Text('정말 이 공고를 삭제하시겠습니까?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('취소'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('삭제'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await JobService.deleteJob(job.id);
                    _loadMyJobs(); // 목록 갱신
                  }
                },
              ),

              // 🔁 마감된 경우 재공고
              if (isClosed)
                TextButton.icon(
                  icon: const Icon(Icons.replay_circle_filled),
                  label: const Text('재공고'),
                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/post_job',
                      arguments: {'isRepost': true, 'existingJob': job},
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    ),
  );
}


}
class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SearchHeaderDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.child,
  });

  @override
  final double minExtent;
  @override
  final double maxExtent;
  final Widget child;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      elevation: overlapsContent ? 2 : 0, // 스크롤 시 살짝 그림자
      child: SizedBox.expand(child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchHeaderDelegate old) =>
      old.minExtent != minExtent ||
      old.maxExtent != maxExtent ||
      old.child != child;
}