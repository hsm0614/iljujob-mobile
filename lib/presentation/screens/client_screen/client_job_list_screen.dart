import 'package:flutter/material.dart';
import 'package:iljujob/widget/app_ui.dart';
import 'package:iljujob/data/services/job_service.dart';
import 'package:iljujob/data/models/job.dart';
import 'package:iljujob/data/services/screen_analytics_service.dart';
import 'package:iljujob/utils/pay_display.dart';
import '../worker_screen/job_detail_screen.dart';
import '../../../config/app_theme.dart';

class ClientJobListScreen extends StatefulWidget {
  final int clientId;
  const ClientJobListScreen({super.key, required this.clientId});

  @override
  State<ClientJobListScreen> createState() => _ClientJobListScreenState();
}

class _ClientJobListScreenState extends State<ClientJobListScreen> {
  late Future<List<Job>> _jobsFuture;
  List<Job> _allJobs = [];
  List<Job> _filteredJobs = [];
  final TextEditingController _searchController = TextEditingController();
  String _sortOption = '최신순';

  @override
  void initState() {
    super.initState();
    ScreenAnalyticsService.instance.logScreenView('client_job_list');
    _jobsFuture = _loadJobs();
  }

  Future<List<Job>> _loadJobs() async {
    final jobs = await JobService.fetchJobs(clientId: widget.clientId);
    _allJobs = jobs;
    _applyFilterAndSort();
    return jobs;
  }

  void _applyFilterAndSort() {
    final query = _searchController.text.toLowerCase();

    List<Job> filtered =
        _allJobs
            .where((job) => job.title.toLowerCase().contains(query))
            .toList();

    if (_sortOption == '최신순') {
      filtered.sort(
        (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
          a.createdAt ?? DateTime(2000),
        ),
      );
    } else if (_sortOption == '급여높은순') {
      filtered.sort((a, b) => int.parse(b.pay).compareTo(int.parse(a.pay)));
    }

    setState(() {
      _filteredJobs = filtered;
    });
  }

  void _onSearchChanged(String query) {
    _applyFilterAndSort();
  }

  void _onSortChanged(String? newValue) {
    if (newValue != null) {
      setState(() => _sortOption = newValue);
      _applyFilterAndSort();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // 키보드 내림
      child: Scaffold(
        appBar: AppBar(
          title: const Text('이 기업의 공고'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: '공고 제목 검색',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: AppColors.bgMuted,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _sortOption,
                    items: const [
                      DropdownMenuItem(value: '최신순', child: Text('최신순')),
                      DropdownMenuItem(value: '급여높은순', child: Text('급여높은순')),
                    ],
                    onChanged: _onSortChanged,
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Job>>(
                future: _jobsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const AppSkeletonList();
                  }

                  if (_filteredJobs.isEmpty) {
                    return const _EmptyJobs();
                  }

                  return ListView.separated(
                    itemCount: _filteredJobs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final job = _filteredJobs[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        leading: const Icon(
                          Icons.work_outline,
                          size: 32,
                          color: AppColors.textTertiary,
                        ),
                        title: Text(
                          job.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            _jobMeta(Icons.place_outlined, job.location),
                            _jobMeta(Icons.schedule_outlined, job.workingHours),
                            _jobMeta(Icons.work_outline, '업종: ${job.category}'),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatJobPay(job.pay, job.payType),
                              // 급여는 잉크색 — 파랑은 누르는 것에만
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (!isNegotiablePayType(job.payType))
                              Text(
                                '(${job.payType})',
                                style: const TextStyle(fontSize: AppFontSize.meta),
                              ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => JobDetailScreen(job: job),
                            ),
                          );
                        },
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

  Widget _jobMeta(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppColors.textTertiary),
          const SizedBox(width: 4),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// 공고 상세의 기업 칸에서 들어온다 — 대개 알바생이 본다. 예전엔 사장님 문구('공고 올리러 가기')였다
class _EmptyJobs extends StatelessWidget {
  const _EmptyJobs();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.work_outline_rounded,
      title: '지금 모집 중인 공고가 없어요',
      message: '새 공고가 올라오면 홈에서 볼 수 있어요',
    );
  }
}
