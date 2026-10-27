import 'package:flutter/material.dart';
import '../../../data/services/notice_service.dart';
import '../../../data/models/notice.dart';
import '../../../config/app_theme.dart';

/// 목록·상세가 같은 날짜를 보이게 (전엔 목록만 UTC 날짜라 밤 공지가 하루 어긋났다)
String noticeDate(String raw) {
  final d = DateTime.tryParse(raw)?.toLocal();
  if (d == null) return raw;
  return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}

class NoticeDetailScreen extends StatelessWidget {
  final int noticeId;

  const NoticeDetailScreen({super.key, required this.noticeId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCard,
      appBar: AppBar(title: const Text('공지사항')),
      body: FutureBuilder<Notice>(
        future: NoticeService.fetchNoticeDetail(noticeId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(
              child: Text('공지사항을 불러오지 못했어요.', style: AppTextStyles.body2),
            );
          }

          final notice = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notice.title, style: AppTextStyles.h2),
                const SizedBox(height: 6),
                Text(noticeDate(notice.createdAt), style: AppTextStyles.jobMeta),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(height: 1, color: AppColors.border),
                ),
                Text(
                  notice.content,
                  style: AppTextStyles.body1.copyWith(height: 1.7),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
