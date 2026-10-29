import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';
import '../../../config/constants.dart';
import '../../../data/services/authenticated_http_client.dart';
import '../../../data/services/job_service.dart';
import '../../../widget/app_ui.dart';
import 'job_detail_screen.dart';

/// 받은 알림 (최근 14일, 서버 push_logs). 공고 알림이면 탭해서 공고로.
class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key});
  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  late Future<List<Map<String, dynamic>>> _items = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final resp = await AuthenticatedHttpClient.get(
      Uri.parse('$baseUrl/api/notification-settings/inbox'),
    ).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) throw Exception('${resp.statusCode}');
    final d = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((d['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _open(Map<String, dynamic> it) async {
    final id = it['job_id'];
    if (id == null) return;
    try {
      final job = await JobService.fetchJobById('$id');
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마감됐거나 삭제된 공고예요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          IconButton(
            tooltip: '알림 설정',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/notifications'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _items = _load());
          await _items;
        },
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _items,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return AppEmptyState(
                icon: Icons.error_outline_rounded,
                title: '알림을 불러오지 못했어요',
                actionLabel: '다시 시도',
                onAction: () => setState(() => _items = _load()),
                secondaryAction: true,
              );
            }
            final items = snap.data!;
            if (items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  AppEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: '최근 받은 알림이 없어요',
                    message: '2주 안에 받은 알림이 여기에 모여요.',
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, i) {
                final it = items[i];
                return InkWell(
                  onTap: it['job_id'] == null ? null : () => _open(it),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${it['title'] ?? ''}',
                          style: AppTextStyles.body1.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if ('${it['body'] ?? ''}'.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${it['body']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body2,
                          ),
                        ],
                        const SizedBox(height: 6),
                        // 서버가 KST 문자열로 준다 (push_logs.sent_at 은 KST 컬럼)
                        Text(
                          '${it['sent_at_kst'] ?? ''}',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
