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
import 'package:iljujob/widget/recommended_workers_sheet.dart';
import '../../data/services/ai_api.dart';

class ClientHomeScreen extends StatefulWidget {
  final AiApi api;

  const ClientHomeScreen({
    super.key,
    required this.api,
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
  
  // 페이지네이션 관련 변수들
  int currentPage = 1;
  int totalPages = 1;
  int totalCount = 0;
  static const int pageSize = 10; // 페이지당 항목 수를 10개로 증가
  
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

  String getExpiryText(Job job) {
    if (job.expiresAt == null) return '';
    
    final now = DateTime.now().toUtc();
    final expiresAt = job.expiresAt!.isUtc ? job.expiresAt! : job.expiresAt!.toUtc();
    
    if (expiresAt.isBefore(now)) {
      return '만료됨';
    }
    
    final diff = expiresAt.difference(now);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    
    if (hours > 24) {
      final days = hours ~/ 24;
      return '${days}일 ${hours % 24}시간 후 만료';
    } else if (hours > 0) {
      return '${hours}시간 ${minutes}분 후 만료';
    } else {
      return '${minutes}분 후 만료';
    }
  }

  @override
  void initState() {
    super.initState();
    _requestNotificationPermission();
    _saveClientFcmToken();
    _fetchClientProfile();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 0) {
        setState(() => payTypeFilter = '전체');
      } else if (_tabController.index == 1) {
        setState(() => payTypeFilter = '일급');
      } else {
        setState(() => payTypeFilter = '주급');
      }
      // 탭 변경 시 첫 페이지로 리셋
      _resetAndLoadJobs();
    });
    
    _loadMyJobs();
    _loadSummaryData();
  }

  // 페이지 리셋하고 첫 페이지 로드
  void _resetAndLoadJobs() {
    setState(() {
      currentPage = 1;
      myJobs.clear();
    });
    _loadMyJobs();
  }

  void _requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
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

  Future<void> _saveClientFcmToken() async {
    if (!Platform.isAndroid) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('userPhone');
    if (phone == null || phone.isEmpty) return;

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
    } catch (e) {
      print('❌ [도급사] 예외 발생: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 수정된 _loadMyJobs 메서드
  Future<void> _loadMyJobs({int? page}) async {
    
    if (isLoading) return;

    final targetPage = page ?? currentPage;
    
    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getInt('userId');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/job/my-jobs?clientId=$clientId&page=$targetPage&limit=$pageSize'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final jobs = (data['jobs'] as List)
        
            .map((json) => Job.fromJson(json))
            .toList();
        
        setState(() {
          myJobs = jobs; // 페이지네이션에서는 항상 새로운 데이터로 교체
          currentPage = targetPage;
          totalPages = data['pagination']['totalPages'] ?? 1;
          totalCount = data['pagination']['totalCount'] ?? 0;
        });
        print('📋 Jobs count: ${(data['jobs'] as List?)?.length ?? 0}');
    print('📋 Pagination: ${data['pagination']}');
      }
    } catch (e) {
      debugPrint('공고 로딩 실패: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  // 특정 페이지로 이동
  void _goToPage(int page) {
    if (page >= 1 && page <= totalPages && page != currentPage) {
      _loadMyJobs(page: page);
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
      // 에러 처리
    }
  }

  // 페이지네이션 위젯
  Widget _buildPaginationWidget() {
    if (totalPages <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: [
          // 페이지 정보
          Text(
            '총 ${totalCount}개 공고 · ${currentPage}/${totalPages} 페이지',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          
          // 페이지 버튼들 - 컴팩트한 크기로 조정
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 첫 페이지 - 작은 크기
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    onPressed: currentPage > 1 ? () => _goToPage(1) : null,
                    icon: const Icon(Icons.first_page, size: 18),
                    tooltip: '첫 페이지',
                    padding: EdgeInsets.zero,
                  ),
                ),
                
                // 이전 페이지 - 작은 크기
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    onPressed: currentPage > 1 ? () => _goToPage(currentPage - 1) : null,
                    icon: const Icon(Icons.chevron_left, size: 18),
                    tooltip: '이전 페이지',
                    padding: EdgeInsets.zero,
                  ),
                ),
                
                // 페이지 번호들 (현재 페이지 근처만 표시)
                ..._buildPageNumbers(),
                
                // 다음 페이지 - 작은 크기
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    onPressed: currentPage < totalPages ? () => _goToPage(currentPage + 1) : null,
                    icon: const Icon(Icons.chevron_right, size: 18),
                    tooltip: '다음 페이지',
                    padding: EdgeInsets.zero,
                  ),
                ),
                
                // 마지막 페이지 - 작은 크기
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    onPressed: currentPage < totalPages ? () => _goToPage(totalPages) : null,
                    icon: const Icon(Icons.last_page, size: 18),
                    tooltip: '마지막 페이지',
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 페이지 번호 버튼들 생성
  List<Widget> _buildPageNumbers() {
    List<Widget> pageButtons = [];
    
    // 현재 페이지 기준으로 앞뒤 1페이지씩만 표시 (더 적게)
    int startPage = (currentPage - 1).clamp(1, totalPages);
    int endPage = (currentPage + 1).clamp(1, totalPages);
    
    // 시작 부분에 ... 표시
    if (startPage > 1) {
      pageButtons.add(
        SizedBox(
          width: 32,
          height: 32,
          child: TextButton(
            onPressed: () => _goToPage(1),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('1', style: TextStyle(fontSize: 12)),
          ),
        ),
      );
      if (startPage > 2) {
        pageButtons.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('...', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        );
      }
    }
    
    // 페이지 번호들
    for (int i = startPage; i <= endPage; i++) {
      pageButtons.add(
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          width: 32,
          height: 32,
          child: TextButton(
            onPressed: i == currentPage ? null : () => _goToPage(i),
            style: TextButton.styleFrom(
              backgroundColor: i == currentPage ? Colors.blue : null,
              foregroundColor: i == currentPage ? Colors.white : Colors.blue,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text('$i', style: const TextStyle(fontSize: 12)),
          ),
        ),
      );
    }
    
    // 끝 부분에 ... 표시
    if (endPage < totalPages) {
      if (endPage < totalPages - 1) {
        pageButtons.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('...', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        );
      }
      pageButtons.add(
        SizedBox(
          width: 32,
          height: 32,
          child: TextButton(
            onPressed: () => _goToPage(totalPages),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('$totalPages', style: const TextStyle(fontSize: 12)),
          ),
        ),
      );
    }
    
    return pageButtons;
  }

  // 필터나 검색 변경 시 호출
  void _onFilterChanged() {
    _resetAndLoadJobs();
  }

  List<Job> _filteredJobs() {
    DateTime _asLocal(DateTime? dt) =>
        dt == null ? DateTime.fromMillisecondsSinceEpoch(0) : (dt.isUtc ? dt.toLocal() : dt);

    DateTime _postedAt(Job j) => _asLocal(j.publishAt ?? j.createdAt);

    int _payToInt(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    int _idInt(Job j) => int.tryParse(j.id.toString()) ?? 0;

    bool _matchesQuery(Job j, String q) {
      final qq = q.trim().toLowerCase();
      if (qq.isEmpty) return true;

      String lc(Object? s) => (s?.toString() ?? '').toLowerCase();

      return lc(j.title).contains(qq) ||
             lc(j.location).contains(qq) ||
             lc((j as dynamic).locationCity).contains(qq) ||
             lc((j as dynamic).description).contains(qq);
    }

    var filtered = List<Job>.of(myJobs);

    if (filterStatus == '공고중') {
      filtered = filtered.where((j) => j.status == 'active').toList();
    } else if (filterStatus == '마감') {
      filtered = filtered.where((j) => j.status == 'closed').toList();
    }

    if (payTypeFilter != '전체') {
      filtered = filtered.where((j) => j.payType == payTypeFilter).toList();
    }

    if (searchQuery.trim().isNotEmpty) {
      filtered = filtered.where((j) => _matchesQuery(j, searchQuery)).toList();
    }

    switch (sortType) {
      case '급여 높은 순':
        filtered.sort((a, b) {
          final cmp = _payToInt(b.pay).compareTo(_payToInt(a.pay));
          if (cmp != 0) return cmp;
          final t = _postedAt(b).compareTo(_postedAt(a));
          if (t != 0) return t;
          return _idInt(b).compareTo(_idInt(a));
        });
        break;

      case '오래된 순':
        filtered.sort((a, b) {
          final cmp = _postedAt(a).compareTo(_postedAt(b));
          if (cmp != 0) return cmp;
          return _idInt(b).compareTo(_idInt(a));
        });
        break;

      default:
        filtered.sort((a, b) {
          final cmp = _postedAt(b).compareTo(_postedAt(a));
          if (cmp != 0) return cmp;
          return _idInt(b).compareTo(_idInt(a));
        });
        break;
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

    final api = AiApi(baseUrl);
    final sub = await api.fetchMySubscription();
    final isSubscribed = sub.active && (sub.plan != null && sub.plan!.toLowerCase() != 'free');

    if (!isSubscribed) {
      if (!mounted) return;
      await _showPaywall();
      return;
    }

    if (!mounted) return;
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
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final bottomInset = mq.viewInsets.bottom;
        final bottomPad = mq.padding.bottom;

        return FractionallySizedBox(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Material(
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
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
        title: Text(
          '알바일주 사장님',
          style: TextStyle(
            fontFamily: 'Jalnan2TTF',
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
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('로그인 정보가 없습니다')));
                return;
              }

              try {
                final response = await http.get(
                  Uri.parse('$baseUrl/api/client/business-info-status?clientId=$clientId'),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('사업자 정보 확인 실패')));
                }
              } catch (e) {
                print('❌ 사업자 확인 오류: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('서버 통신 오류')));
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
          SliverToBoxAdapter(child: _buildSummarySection()),

          if (!isSafeCompany)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline, color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '🔒 안심기업 인증 시\n지원율이 올라갑니다!',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                        ),
                        onPressed: () {
                          Navigator.pushNamed(context, '/edit_profile');
                        },
                        child: const Text('인증', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

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
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: '공고 제목 또는 지역 검색',
                    hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    setState(() => searchQuery = val);
                    _onFilterChanged(); // 검색 시 첫 페이지로 리셋
                  },
                ),
              ),
            ),
          ),

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
                        onSelected: (_) {
                          setState(() => filterStatus = '전체');
                          _onFilterChanged();
                        },
                      ),
                      FilterChip(
                        label: const Text('공고중'),
                        selected: filterStatus == '공고중',
                        onSelected: (_) {
                          setState(() => filterStatus = '공고중');
                          _onFilterChanged();
                        },
                      ),
                      FilterChip(
                        label: const Text('마감'),
                        selected: filterStatus == '마감',
                        onSelected: (_) {
                          setState(() => filterStatus = '마감');
                          _onFilterChanged();
                        },
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
                        onChanged: (val) {
                          setState(() => sortType = val!);
                          _onFilterChanged();
                        },
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
          else ...[
            SliverList.builder(
              itemCount: jobs.length,
              itemBuilder: (context, index) =>
                  compactView ? _buildCompactJobCard(jobs[index])
                              : _buildJobCard(jobs[index]),
            ),
            
            // 페이지네이션 위젯 추가
            SliverToBoxAdapter(child: _buildPaginationWidget()),
          ],
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
    final nowUtc = DateTime.now().toUtc();
    final isClosed = job.status == 'closed';
    final isReserved = job.publishAt != null && job.publishAt!.isAfter(DateTime.now());
    final isPinned = job.pinnedUntil != null && job.pinnedUntil!.isAfter(nowUtc);

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
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (isReserved) pill('예약됨', Colors.orange, icon: Icons.schedule),
                  if (isPinned) pill('상단고정', Colors.deepOrange, icon: Icons.push_pin_outlined),
                  if (isPinned) pill(pinRemain(), Colors.deepOrange),
                  if (isClosed) pill('마감됨', Colors.grey, icon: Icons.stop_circle_outlined),
                  if (job.expiresAt != null && !isClosed)
                    pill(getExpiryText(job), Colors.red.shade600, icon: Icons.access_time),
                ],
              ),
              if (isReserved || isPinned || isClosed) const SizedBox(height: 6),
              Text('📍 ${job.location}', maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('💰 $formattedPay원 · ⏰ ${job.workingHours}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
          trailing: PopupMenuButton<String>(
            tooltip: '메뉴',
            itemBuilder: (context) => [
              if (isReserved)
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
                case 'publish-now':
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
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
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
    final isWeekly = job.payType == '주급';
    final formattedPay = NumberFormat('#,###').format(int.parse(job.pay));
    final isClosed = job.status == 'closed';
    final isPinned = job.pinnedUntil != null &&
        job.pinnedUntil!.isAfter(DateTime.now().toUtc());

    final titleStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: isClosed ? Colors.grey : Colors.black,
      decoration: isClosed ? TextDecoration.lineThrough : null,
    );

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
            if (isReserved || isPinned || isClosed) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (isReserved) pill('예약됨', Colors.orangeAccent, icon: Icons.schedule),
                  if (isPinned) pill('상단고정', Colors.deepOrange, icon: Icons.push_pin_outlined),
                  if (isPinned) pill(remainingPinText(), Colors.deepOrange),
                  if (isClosed) pill('마감됨', Colors.grey, icon: Icons.stop_circle_outlined),
                ],
              ),
              const SizedBox(height: 6),
            ],

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
            if (job.expiresAt != null && !isClosed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.red.shade600),
                    const SizedBox(width: 4),
                    Text(
                      getExpiryText(job),
                      style: TextStyle(
                        color: Colors.red.shade600,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
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
                      foregroundColor: Colors.orange,
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
                  ),
                if (!isClosed)
                  Tooltip(
                    message: 'AI가 이 공고와 잘 맞는 인재를 추천해요',
                    child: TextButton.icon(
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.group_add_outlined),
                          const Positioned(
                            left: -8, bottom: -8,
                            child: Icon(Icons.auto_awesome, size: 14, color: Color(0xFF4F46E5)),
                          ),
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

                if (!isClosed)
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: '수정',
                    onPressed: () {
                      Navigator.pushNamed(context, '/edit_job', arguments: job.id);
                    },
                  ),

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
                      _loadMyJobs();
                    }
                  },
                ),

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
      elevation: overlapsContent ? 2 : 0,
      child: SizedBox.expand(child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchHeaderDelegate old) =>
      old.minExtent != minExtent ||
      old.maxExtent != maxExtent ||
      old.child != child;
}