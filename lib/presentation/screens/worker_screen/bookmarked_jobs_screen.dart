import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:iljujob/widget/app_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/constants.dart';
import '../../../data/models/job.dart';
import '../../../data/services/authenticated_http_client.dart';
import '../../../data/services/job_service.dart';
import 'job_detail_screen.dart';
import 'package:iljujob/utils/pay_display.dart';
import '../../../config/app_theme.dart';
import '../../../config/messages.dart';
import '../../../widget/job_list_tile.dart';


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

  List<Job> _bookmarkedJobs = [];
  bool _isLoading = true;
  bool _isError = false;


  @override
  void initState() {
    super.initState();
    _loadBookmarkedJobs();
  }

  @override
  void dispose() {
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
        final resp = await AuthenticatedHttpClient.get(uri);
        if (resp.statusCode != 200) {
          throw Exception(
            'bookmark list http ${resp.statusCode}: ${resp.body}',
          );
        }
        final raw = jsonDecode(resp.body);
        if (raw is! List) throw Exception('unexpected payload: ${resp.body}');
        jobs =
            raw
                .map<Job>((e) => Job.fromJson(e as Map<String, dynamic>))
                .toList();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(Msg.loginRequired)));
        return;
      }

      final uri = Uri.parse('$baseUrl/api/bookmark/remove');
      final resp = await AuthenticatedHttpClient.postJson(
        uri,
        body: {'userId': userId, 'jobId': job.id},
      );

      if (resp.statusCode == 200) {
        // 서버가 bookmarks 배열을 내려줄 수도 있음
        try {
          final j = jsonDecode(resp.body);
          if (j is Map && j['bookmarks'] is List) {
            final ids =
                (j['bookmarks'] as List).map((e) => e.toString()).toSet();
            if (!mounted) return;
            setState(() {
              _bookmarkedJobs =
                  _bookmarkedJobs
                      .where((it) => ids.contains(it.id.toString()))
                      .toList();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('관심 공고에서 뺐어요.')));
      } else {
        debugPrint('찜 삭제 실패: ${resp.statusCode}');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(Msg.deleteFailed)));
      }
    } catch (e) {
      debugPrint('찜 삭제 중 오류: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(Msg.deleteFailed)));
    }
  }

  // 2026-10 리디자인: 홈과 같은 공고 줄(JobListTile)로. '준비중' 채팅 버튼·빨간 휴지통 대신 하트,
  // 검색은 찜이 몇 개 안 돼 뺐다. 모집 중을 위로, 마감은 아래로
  List<Job> get _sortedJobs => [
    ..._bookmarkedJobs.where((j) => j.status == 'active'),
    ..._bookmarkedJobs.where((j) => j.status != 'active'),
  ];

  @override
  Widget build(BuildContext context) {
    final jobs = _sortedJobs;
    return Scaffold(
      backgroundColor: AppColors.bgCard,
      appBar: AppBar(title: const Text('관심 공고')),
      body:
          _isLoading
              ? const AppSkeletonList()
              : _isError
              ? AppEmptyState(
                icon: Icons.wifi_off_rounded,
                title: '관심 공고를 불러오지 못했어요',
                message: Msg.server,
                actionLabel: '다시 시도',
                onAction: _loadBookmarkedJobs,
                secondaryAction: true,
              )
              : RefreshIndicator(
                onRefresh: _loadBookmarkedJobs,
                child:
                    jobs.isEmpty
                        ? ListView(
                          children: [
                            const SizedBox(height: 80),
                            AppEmptyState(
                              icon: Icons.favorite_border_rounded,
                              title: '관심 공고가 없어요',
                              message: '공고의 하트를 누르면 여기에 모여요.',
                              actionLabel: '공고 둘러보기',
                              onAction:
                                  () => Navigator.popUntil(
                                    context,
                                    (r) => r.isFirst,
                                  ),
                            ),
                          ],
                        )
                        : ListView.builder(
                          itemCount: jobs.length,
                          itemBuilder: (context, i) {
                            final job = jobs[i];
                            final raw =
                                job.imageUrls.isEmpty
                                    ? null
                                    : job.imageUrls.first;
                            final company = (job.company ?? '').trim();
                            return JobListTile(
                              pay: formatJobPay(job.pay, job.payType),
                              payType: job.payType,
                              negotiablePay: isNegotiablePayType(job.payType),
                              title: job.title,
                              schedule:
                                  [
                                    if (formatWeekdays(job.weekdays)
                                        case final w?)
                                      w,
                                    if (job.workingHours.trim().isNotEmpty)
                                      job.workingHours.trim(),
                                  ].join(' · ').nullIfEmpty,
                              location: [
                                if (job.status != 'active') '마감',
                                company.isNotEmpty
                                    ? company
                                    : job.location
                                        .split(RegExp(r'\s+'))
                                        .take(3)
                                        .join(' '),
                              ].join(' · '),
                              divider: i < jobs.length - 1,
                              imageUrl:
                                  raw == null
                                      ? null
                                      : (raw.startsWith('http')
                                          ? raw
                                          : '$baseUrl$raw'),
                              isBookmarked: true,
                              onBookmark: () => _removeBookmark(job),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => JobDetailScreen(job: job),
                                  ),
                                );
                                // 상세에서 하트를 풀었을 수 있다
                                _loadBookmarkedJobs();
                              },
                            );
                          },
                        ),
              ),
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
