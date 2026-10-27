import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/constants.dart';
import '../../../data/models/job.dart';
import '../../../data/services/job_service.dart';
import '../../../utils/pay_display.dart';
import '../../../widget/app_ui.dart';
import '../../../widget/job_list_tile.dart';
import 'job_detail_screen.dart';

/// 최근 본 공고. 기기에만 id를 남긴다(서버 테이블 없음) — 기기를 바꾸면 사라진다.
class RecentJobs {
  static const _key = 'recent_viewed_job_ids';
  static const _max = 20;

  static Future<void> add(Object id) async {
    final p = await SharedPreferences.getInstance();
    final ids = p.getStringList(_key) ?? [];
    ids
      ..remove('$id')
      ..insert(0, '$id');
    await p.setStringList(_key, ids.take(_max).toList());
  }

  static Future<List<String>> ids() async =>
      (await SharedPreferences.getInstance()).getStringList(_key) ?? [];
}

class RecentJobsScreen extends StatefulWidget {
  const RecentJobsScreen({super.key});
  @override
  State<RecentJobsScreen> createState() => _RecentJobsScreenState();
}

class _RecentJobsScreenState extends State<RecentJobsScreen> {
  late final Future<List<Job>> _jobs = _load();

  Future<List<Job>> _load() async {
    final ids = await RecentJobs.ids();
    // 삭제·비공개된 공고는 조용히 뺀다
    final jobs = await Future.wait(
      ids.map((id) => JobService.fetchJobById(id).then<Job?>((j) => j).catchError((_) => null)),
    );
    return jobs.whereType<Job>().toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('최근 본 공고')),
      body: FutureBuilder<List<Job>>(
        future: _jobs,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const AppSkeletonList();
          }
          final jobs = snap.data!;
          if (jobs.isEmpty) {
            return const AppEmptyState(
              icon: Icons.history_rounded,
              title: '최근 본 공고가 없어요',
              message: '공고를 열어보면 여기에 모여요.',
            );
          }
          return ListView.builder(
            itemCount: jobs.length,
            itemBuilder: (context, i) {
              final job = jobs[i];
              final raw = job.imageUrls.isEmpty ? null : job.imageUrls.first;
              return JobListTile(
                pay: formatJobPay(job.pay, job.payType),
                payType: job.payType,
                negotiablePay: isNegotiablePayType(job.payType),
                title: job.title,
                schedule: job.workingHours,
                location: job.location,
                imageUrl:
                    raw == null ? null : (raw.startsWith('http') ? raw : '$baseUrl$raw'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
