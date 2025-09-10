import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/job.dart';
import '../../data/services/job_service.dart';
import 'job_detail_screen.dart';

/// ------------------------------------------------------------
/// BookmarkedJobsScreen (refactor)
/// - 안정적인 로딩/에러/빈 상태 처리
/// - userId 하드코딩 제거(SharedPreferences에서 읽음)
/// - 당겨서 새로고침, 검색 디바운스, 필터(공고중/마감)
/// - 북마크 삭제(서버 제거 + 로컬 목록 즉시 반영)
/// - 재시도/스낵바 안내 + 상세 로그(debugPrint)
/// ------------------------------------------------------------
class BookmarkedJobsScreen extends StatefulWidget {
  const BookmarkedJobsScreen({super.key});

  @override
  State<BookmarkedJobsScreen> createState() => _BookmarkedJobsScreenState();
}

class _BookmarkedJobsScreenState extends State<BookmarkedJobsScreen> {
  final _searchCtrl = TextEditingController();
  final _debouncer = _Debouncer(const Duration(milliseconds: 300));

  List<Job> _bookmarkedJobs = [];
  bool _isLoading = true;
  bool _isError = false;
  String _filterStatus = '전체';
  String _searchQuery = '';

  // 환경에 맞게 교체하세요.
  static const String baseUrl = String.fromEnvironment('BASE_URL', defaultValue: 'https://albailju.co.kr');

  @override
  void initState() {
    super.initState();
    _loadBookmarkedJobs();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  Future<int?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('userId');
  }

  Future<void> _loadBookmarkedJobs() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      final userId = await _getUserId();
      if (userId == null) {
        debugPrint('❌ BookmarkedJobs: userId=null');
        setState(() {
          _bookmarkedJobs = [];
          _isLoading = false;
          _isError = true;
        });
        return;
      }

      // 1) 우선 JobService에 구현되어 있으면 사용
      List<Job> jobs = [];
      try {
        jobs = await JobService.fetchBookmarkedJobs(userId);
      } catch (e) {
        // 2) Fallback: 서버에서 직접 호출 (/api/bookmark/list?userId=.. 가 공고 배열 반환)
        final uri = Uri.parse('$baseUrl/api/bookmark/list?userId=$userId');
        final resp = await http.get(uri);
        if (resp.statusCode != 200) {
          throw Exception('bookmark list http ${resp.statusCode}: ${resp.body}');
        }
        final raw = jsonDecode(resp.body);
        if (raw is! List) throw Exception('unexpected payload: ${resp.body}');
        jobs = raw.map<Job>((e) => Job.fromJson(e as Map<String, dynamic>)).toList();
      }

      if (!mounted) return;
      setState(() {
        _bookmarkedJobs = jobs;
        _isLoading = false;
        _isError = false;
      });
    } catch (e, st) {
      debugPrint('❌ loadBookmarkedJobs error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isError = true;
      });
    }
  }

  Future<void> _removeBookmark(Job job) async {
    try {
      final userId = await _getUserId();
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 정보가 없습니다.')),
        );
        return;
      }

      final body = jsonEncode({'userId': userId, 'jobId': job.id});
      final uri = Uri.parse('$baseUrl/api/bookmark/remove');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (resp.statusCode == 200) {
        // 서버가 bookmarks 배열을 내려줄 수도 있음
        try {
          final j = jsonDecode(resp.body);
          if (j is Map && j['bookmarks'] is List) {
            final ids = (j['bookmarks'] as List).map((e) => e.toString()).toSet();
            if (!mounted) return;
            setState(() {
              _bookmarkedJobs = _bookmarkedJobs.where((it) => ids.contains(it.id.toString())).toList();
            });
          } else {
            if (!mounted) return;
            setState(() {
              _bookmarkedJobs.removeWhere((it) => it.id == job.id);
            });
          }
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _bookmarkedJobs.removeWhere((it) => it.id == job.id);
          });
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('찜 삭제: ${job.title}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: ${resp.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 중 오류: $e')),
      );
    }
  }

  List<Job> get _filteredJobs {
    final q = _searchQuery.trim();
    final lower = q.toLowerCase();

    return _bookmarkedJobs.where((job) {
      final statusOk = _filterStatus == '전체' ||
          (_filterStatus == '공고중' && job.status == 'active') ||
          (_filterStatus == '마감' && job.status != 'active');

      if (!statusOk) return false;
      if (lower.isEmpty) return true;

      bool match(String? s) => (s ?? '').toLowerCase().contains(lower);
      return match(job.title) || match(job.location) || match(job.category);
    }).toList();
  }

  Future<void> _onRefresh() async {
    await _loadBookmarkedJobs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내가 찜한 공고'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBookmarkedJobs,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndFilter(),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const _Loading()
                : _isError
                    ? _Error(onRetry: _loadBookmarkedJobs)
                    : RefreshIndicator(
                        onRefresh: _onRefresh,
                        child: _filteredJobs.isEmpty
                            ? const _Empty()
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _filteredJobs.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final job = _filteredJobs[index];
                                  return _JobTile(
                                    job: job,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => JobDetailScreen(job: job),
                                        ),
                                      );
                                    },
                                    onDelete: () => _removeBookmark(job),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (val) => _debouncer(() {
              setState(() => _searchQuery = val);
            }),
            decoration: InputDecoration(
              hintText: '제목/지역/분야 검색',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['전체', '공고중', '마감'].map((status) {
              final selected = _filterStatus == status;
              return ChoiceChip(
                label: Text(status),
                selected: selected,
                onSelected: (_) => setState(() => _filterStatus = status),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  final Job job;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _JobTile({
    required this.job,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = job.status == 'active';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _StatusBadge(isActive: isActive),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '[${job.category}] ${job.title}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.place_outlined, size: 16),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                job.location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.schedule_outlined, size: 16),
                            const SizedBox(width: 4),
                            Text(_formatDateRange(job)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.attach_money, size: 16),
                            const SizedBox(width: 4),
                            Text('₩${job.pay} (${job.payType})'),
                            const SizedBox(width: 8),
                            Text('등록일 ${_formatDate(job.createdAt)}', style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline, color: Colors.indigo),
                        tooltip: '채팅',
                        onPressed: () {
                          // TODO: 채팅 화면 이동 연결
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('채팅 기능 준비중')),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: '찜 삭제',
                        onPressed: onDelete,
                      ),
                    ],
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return '${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  static String _formatDateRange(Job job) {
    String f(DateTime? dt) => _formatDate(dt);
    final start = f(job.startDate);
    final end = f(job.endDate);
    return start == end ? start : '$start ~ $end';
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.blue.shade100 : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isActive ? '채용중' : '마감',
        style: TextStyle(
          fontSize: 12,
          color: isActive ? Colors.blue : Colors.grey.shade800,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('찜한 공고가 없습니다.'),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  final VoidCallback onRetry;
  const _Error({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('불러오기 실패'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 간단 디바운서
class _Debouncer {
  _Debouncer(this.delay);
  final Duration delay;
  Timer? _timer;
  void call(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }
  void dispose() => _timer?.cancel();
}
