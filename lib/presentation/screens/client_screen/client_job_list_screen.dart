import 'package:flutter/material.dart';
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
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text('등록한 공고'),
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
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
                    return const Center(child: CircularProgressIndicator());
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
                          color: Colors.grey,
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            if (!isNegotiablePayType(job.payType))
                              Text(
                                '(${job.payType})',
                                style: const TextStyle(fontSize: 12),
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
          Icon(icon, size: 13, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// 공고가 하나도 없을 때. 문장만 남기면 사장님이 여기서 멈춘다 —
/// 홈으로 돌려보내 공고 등록을 이어가게 한다.
class _EmptyJobs extends StatelessWidget {
  const _EmptyJobs();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.work_outline_rounded,
              size: 42,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 12),
            const Text(
              '아직 등록한 공고가 없어요',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '공고를 올리면 근처 알바생에게 바로 노출돼요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed:
                    () => Navigator.popUntil(context, (r) => r.isFirst),
                child: const Text(
                  '공고 올리러 가기',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
