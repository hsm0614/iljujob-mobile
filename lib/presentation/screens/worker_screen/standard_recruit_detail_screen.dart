import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_theme.dart';
import '../../../config/constants.dart';
import '../../../data/services/ad_banner_service.dart';
import '../../../data/services/job_service.dart';
import 'job_detail_screen.dart';

class StandardRecruitDetailScreen extends StatefulWidget {
  const StandardRecruitDetailScreen({super.key, required this.bannerId});
  final int bannerId;

  @override
  State<StandardRecruitDetailScreen> createState() =>
      _StandardRecruitDetailScreenState();
}

class _StandardRecruitDetailScreenState
    extends State<StandardRecruitDetailScreen> {
  late final Future<Map<String, dynamic>> _detail = _load();

  Future<Map<String, dynamic>> _load() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/ad-requests/public/${widget.bannerId}'),
    );
    if (response.statusCode != 200) throw Exception('종료되었거나 볼 수 없는 채용 광고입니다.');
    return Map<String, dynamic>.from(
      jsonDecode(response.body)['detail'] as Map,
    );
  }

  Future<void> _apply() async {
    try {
      final current = await _load();
      if (current['destination_type'] == 'internal_job') {
        final job = await JobService.fetchJobById('${current['job_id']}');
        if (!mounted) return;
        AdBannerService.instance.logEvent(
          widget.bannerId,
          'landing_cta',
          'app_partner_recruit',
        );
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => JobDetailScreen(job: job)),
        );
      } else {
        final uri = Uri.tryParse('${current['destination_url']}');
        if (uri == null || uri.scheme != 'https') throw Exception();
        AdBannerService.instance.logEvent(
          widget.bannerId,
          'landing_cta',
          'app_partner_recruit',
        );
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('지원 페이지를 열 수 없습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('채용 광고')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData)
          return Center(
            child: Text(snapshot.error.toString(), style: AppTextStyles.body1),
          );
        final detail = snapshot.data!;
        return SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      detail['company_name'] as String,
                      style: AppTextStyles.body2,
                    ),
                    const SizedBox(height: 8),
                    Text(detail['title'] as String, style: AppTextStyles.h2),
                    if ((detail['subtitle'] as String?)?.isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 12),
                      Text(
                        detail['subtitle'] as String,
                        style: AppTextStyles.body1,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text('채용 내용', style: AppTextStyles.h3),
                    const SizedBox(height: 12),
                    Text(
                      detail['description'] as String? ?? '',
                      style: AppTextStyles.body1,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('지원하기'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
