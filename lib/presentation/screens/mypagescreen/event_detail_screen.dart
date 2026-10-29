import 'package:flutter/material.dart';
import 'package:iljujob/config/constants.dart';
import '../../../config/app_theme.dart';

// 이벤트 날짜는 DATE 컬럼(벽시계) — 앞 10자리만 쓴다. 시간대 변환 금지 (CLAUDE.md)
String _ymd(dynamic v) {
  final s = (v ?? '').toString();
  return s.length >= 10 ? s.substring(0, 10) : '';
}

String eventImageUrl(String? url) {
  if (url == null || url.trim().isEmpty) return '';
  if (url.startsWith('http')) return url;
  return '$baseUrl/${url.replaceFirst(RegExp(r'^/+'), '')}';
}

String eventPeriod(Map e) {
  final s = _ymd(e['start_date']).replaceAll('-', '.');
  final d = _ymd(e['end_date']).replaceAll('-', '.');
  if (s.isEmpty && d.isEmpty) return '';
  if (s.isEmpty) return '~ $d';
  if (d.isEmpty) return '$s ~';
  return '$s ~ $d';
}

/// 기간이 비어 있으면 진행 중으로 본다
bool eventOngoing(Map e, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today =
      '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  final s = _ymd(e['start_date']);
  final d = _ymd(e['end_date']);
  return (s.isEmpty || s.compareTo(today) <= 0) &&
      (d.isEmpty || d.compareTo(today) >= 0);
}

class EventDetailScreen extends StatelessWidget {
  final Map<String, dynamic> event;

  const EventDetailScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final imageUrl = eventImageUrl(event['image_url']?.toString());
    final period = eventPeriod(event);
    final description = (event['description'] ?? '').toString().replaceAll(
      r'\n',
      '\n',
    );

    return Scaffold(
      backgroundColor: AppColors.bgCard,
      appBar: AppBar(title: const Text('이벤트')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((event['title'] ?? '').toString(), style: AppTextStyles.h2),
            if (period.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${eventOngoing(event) ? '진행 중' : '종료'} · $period',
                style: AppTextStyles.jobMeta,
              ),
            ],
            const SizedBox(height: 20),
            if (imageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text(description, style: AppTextStyles.body1.copyWith(height: 1.7)),
          ],
        ),
      ),
    );
  }
}
