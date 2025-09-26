import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/job.dart';
import '../../data/services/job_service.dart';
import 'job_detail_screen.dart';
const kBrand  = Color(0xFF3B8AFF);
const kBorder = Color(0xFFE2E7EF);
const kBg     = Color(0xFFF7F9FC);
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
    backgroundColor: kBg,
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: const Text(
        '내가 찜한 공고',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: kBrand,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.black87),
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
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                              itemCount: _filteredJobs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
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
  InputDecoration deco(String hint) => InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBrand, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
    child: Column(
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (val) => _debouncer(() => setState(() => _searchQuery = val)),
          decoration: deco('제목/지역/분야 검색'),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['전체', '공고중', '마감'].map((status) {
              final selected = _filterStatus == status;
              return FilterChip(
                label: Text(
                  status,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? kBrand : Colors.black87,
                  ),
                ),
                selected: selected,
                onSelected: (_) => setState(() => _filterStatus = status),
                showCheckmark: true,
                checkmarkColor: kBrand,
                backgroundColor: Colors.white,
                selectedColor: kBrand.withOpacity(0.12),
                side: BorderSide(color: selected ? kBrand : kBorder, width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              );
            }).toList(),
          ),
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.04),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상태 뱃지 (세로)
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 2),
                child: _StatusBadge(isActive: isActive),
              ),

              // 본문
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 카테고리 + 타이틀
                    Text(
                      '[${job.category}] ${job.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // 위치
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 16, color: Colors.black54),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            job.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // 날짜
                    Row(
                      children: [
                        const Icon(Icons.schedule_outlined, size: 16, color: Colors.black54),
                        const SizedBox(width: 4),
                        Text(_formatDateRange(job),
                            style: const TextStyle(color: Colors.black87)),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // 급여 + 등록일 (필)
                    Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _pill('₩${job.pay} · ${job.payType}'),
                        Text(
                          '등록일 ${_formatDate(job.createdAt)}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 액션
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, color: kBrand),
                    tooltip: '채팅',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('채팅 기능 준비중')),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    tooltip: '찜 삭제',
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kBrand.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kBrand.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: kBrand,
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
    final bg  = isActive ? kBrand.withOpacity(0.12) : Colors.grey.shade300;
    final txt = isActive ? kBrand : Colors.grey.shade800;
    final icn = isActive ? Icons.flash_on : Icons.pause_circle_outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isActive ? kBrand : Colors.grey.shade400),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icn, size: 14, color: txt),
          const SizedBox(width: 4),
          Text(
            isActive ? '채용중' : '마감',
            style: TextStyle(
              fontSize: 12,
              color: txt,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.bookmark_border, size: 42, color: Colors.black38),
            SizedBox(height: 10),
            Text(
              '찜한 공고가 없습니다.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 4),
            Text(
              '마음에 드는 공고를 찜해 보세요.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
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
