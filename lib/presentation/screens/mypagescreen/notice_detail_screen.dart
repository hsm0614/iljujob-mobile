import 'package:flutter/material.dart';
import '../../../data/services/notice_service.dart';
import '../../../data/models/notice.dart';

class NoticeDetailScreen extends StatelessWidget {
  final int noticeId;

  const NoticeDetailScreen({super.key, required this.noticeId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('공지사항')),
      body: FutureBuilder<Notice>(
        future: NoticeService.fetchNoticeDetail(noticeId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(child: Text('공지사항을 불러오지 못했습니다.'));
          }

          final notice = snapshot.data!;
          final String formattedDate = DateTime.parse(notice.createdAt)
              .toLocal()
              .toString()
              .substring(0, 10);

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  formattedDate,
                  style: const TextStyle(color: Colors.grey),
                ),
                const Divider(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(notice.content),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
