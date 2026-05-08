import 'package:flutter/material.dart';
import 'package:iljujob/data/services/job_service.dart';
import 'package:iljujob/data/models/job.dart';
import '../worker_screen/job_detail_screen.dart';


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

    List<Job> filtered = _allJobs
        .where((job) => job.title.toLowerCase().contains(query))
        .toList();

   if (_sortOption == '최신순') {
  filtered.sort((a, b) =>
    (b.createdAt ?? DateTime(2000))
        .compareTo(a.createdAt ?? DateTime(2000)));
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
          iconTheme: const IconThemeData(color: Colors.black),
          title: const Text(
            '등록한 공고',
            style: TextStyle(
              color: Color(0xFF3B8AFF),
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
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
                    return const Center(child: Text('등록한 공고가 없습니다.'));
                  }

                  return ListView.separated(
                    itemCount: _filteredJobs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final job = _filteredJobs[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        leading: const Icon(Icons.work_outline, size: 32, color: Colors.grey),
                        title: Text(
                          job.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('📍 ${job.location}'),
                            Text('🕒 ${job.workingHours}'),
                            Text('💼 업종: ${job.category}'),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${job.pay}원',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue),
                            ),
                            Text('(${job.payType})',
                                style: const TextStyle(fontSize: 12)),
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
}
