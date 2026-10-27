// File: notice_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/services/notice_service.dart';
import '../../../data/models/notice.dart';
import 'notice_detail_screen.dart';
import 'notice_create_screen.dart';
import '../../../config/app_theme.dart';
import '../../../config/messages.dart';
import '../../../widget/app_ui.dart';

/// 공지사항 (2026-10 리디자인). 파란 160px 헤더·검색·카드 → 일반 앱바 + 흰 줄.
/// 공지가 몇 개 안 돼 검색은 뺐다.
class NoticeListScreen extends StatefulWidget {
  const NoticeListScreen({super.key});

  @override
  State<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends State<NoticeListScreen> {
  List<Notice> _notices = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    _isAdmin = prefs.getBool('isAdmin') ?? false;

    try {
      final items = await NoticeService.fetchNotices();
      if (!mounted) return;
      setState(() {
        _notices = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = Msg.server;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCard,
      appBar: AppBar(title: const Text('공지사항')),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? AppEmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: '공지사항을 불러오지 못했어요',
                  message: _error,
                  actionLabel: '다시 시도',
                  onAction: _loadData,
                  secondaryAction: true,
                )
                : _notices.isEmpty
                ? const AppEmptyState(
                  icon: Icons.campaign_outlined,
                  title: '아직 공지사항이 없어요',
                  message: '새 공지가 올라오면 여기서 볼 수 있어요.',
                )
                : ListView.builder(
                  itemCount: _notices.length,
                  itemBuilder: (context, i) {
                    final n = _notices[i];
                    return InkWell(
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NoticeDetailScreen(noticeId: n.id),
                            ),
                          ),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppColors.borderSub),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.jobTitle,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              noticeDate(n.createdAt),
                              style: AppTextStyles.jobMeta,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      ),
      floatingActionButton:
          _isAdmin
              ? FloatingActionButton(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NoticeCreateScreen()),
                  );
                  if (result == true) _loadData();
                },
                tooltip: '공지 작성',
                child: const Icon(Icons.add),
              )
              : null,
    );
  }
}
