// File: notice_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/services/notice_service.dart';
import '../../../data/models/notice.dart';
import 'notice_detail_screen.dart';
import 'notice_create_screen.dart';

class NoticeListScreen extends StatefulWidget {
  const NoticeListScreen({super.key});

  @override
  State<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends State<NoticeListScreen> {
  List<Notice> _notices = [];
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }
String _formatDate(String dateStr) {
  try {
    final date = DateTime.parse(dateStr);
    return "${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}";
  } catch (e) {
    return dateStr; // 파싱 실패 시 원본 반환
  }
}
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final isAdmin = prefs.getBool('isAdmin') ?? false;
    

    setState(() {
      _isAdmin = isAdmin;
    });

    try {
      final notices = await NoticeService.fetchNotices();
      setState(() {
        _notices = notices;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 공지사항 로딩 실패: $e');
      setState(() => _isLoading = false);
    }
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text(
        '공지사항',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 1,
    ),
    backgroundColor: const Color(0xFFF6F7FB),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _notices.isEmpty
            ? const Center(
                child: Text(
                  '등록된 공지사항이 없습니다',
                  style: TextStyle(color: Colors.grey, fontSize: 15),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _notices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final notice = _notices[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              NoticeDetailScreen(noticeId: notice.id),
                        ),
                      );
                    },
                    child: Card(
                      elevation: 2,
                      shadowColor: Colors.black12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 상단: 제목
                            Text(
                              notice.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            // 작성자 + 날짜
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  notice.writer,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  _formatDate(notice.createdAt),
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
    floatingActionButton: _isAdmin
        ? FloatingActionButton(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NoticeCreateScreen()),
              );
              if (result == true) _loadData();
            },
            tooltip: '공지 작성',
            backgroundColor: Colors.indigo,
            child: const Icon(Icons.add),
          )
        : null,
  );
}

}