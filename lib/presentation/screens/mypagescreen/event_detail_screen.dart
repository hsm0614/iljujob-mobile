import 'package:flutter/material.dart';
import 'package:iljujob/config/constants.dart';

class EventDetailScreen extends StatelessWidget {
  final Map<String, dynamic> event;

  const EventDetailScreen({super.key, required this.event});

  /// 날짜 형식: 2025-07-01 형태로 변환
  String formatDate(String isoDate) {
    return isoDate.split('T').first;
  }

  /// 이미지 경로를 전체 URL로 변환
  String getFullImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return '';
    if (imageUrl.startsWith('http')) return imageUrl;
    return '$baseUrl$imageUrl';
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = getFullImageUrl(event['image_url']);
    final startDate = event['start_date'] != null ? formatDate(event['start_date']) : '';
    final endDate = event['end_date'] != null ? formatDate(event['end_date']) : '';
    final description = (event['description'] ?? '').replaceAll(r'\n', '\n');

    return Scaffold(
      appBar: AppBar(title: Text(event['title'] ?? '이벤트')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ 이벤트 기간 상단 표시
            if (startDate.isNotEmpty && endDate.isNotEmpty)
              Text(
                '📅 기간: $startDate ~ $endDate',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            const SizedBox(height: 16),

            // ✅ 이미지
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 24),

            // ✅ 설명
            Text(
              description,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}