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
  static const brandBlue = Color(0xFF3B8AFF);
  static const brandBlueLight = Color(0xFF6EB6FF);

  List<Notice> _notices = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _formatDate(String dateStr) {
    try {
      final d = DateTime.tryParse(dateStr) ?? DateTime.tryParse(dateStr.split(' ').first);
      if (d == null) return dateStr;
      return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
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
        _error = '공지사항을 불러오지 못했습니다.';
        _isLoading = false;
      });
    }
  }

  bool _isPinned(Notice n) {
    // 모델에 pinned 같은 필드 없으면 항상 false
    // 있으면 n.isPinned 같은걸로 바꿔서 활용해도 됨
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();

    final filtered = _notices.where((n) {
      if (q.isEmpty) return true;
      final t = n.title.toLowerCase();
      final w = (n.writer).toLowerCase();
      return t.contains(q) || w.contains(q);
    }).toList();

    // 고정 공지(있다면) 위로
    filtered.sort((a, b) {
      final ap = _isPinned(a) ? 1 : 0;
      final bp = _isPinned(b) ? 1 : 0;
      return bp.compareTo(ap);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: brandBlue,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              elevation: 0,
              backgroundColor: Colors.white,
              expandedHeight: 160,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [brandBlue, brandBlueLight],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '공지사항',
                            style: TextStyle(
                              fontFamily: 'Jalnan2TTF',
                              color: Colors.white,
                              fontSize: 22,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SearchField(
                            hintText: '공지 검색',
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              toolbarHeight: 0,
            ),

            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _SkeletonList(),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorState(
                  message: '공지사항을 불러오지 못했습니다.',
                ),
              )
            else if (filtered.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: Icons.campaign_outlined,
                  title: '등록된 공지사항이 없습니다.',
                  subtitle: '새 공지가 올라오면 여기서 확인할 수 있어요.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final n = filtered[i];
                    return _NoticeCard(
                      notice: n,
                      dateText: _formatDate(n.createdAt),
                      pinned: _isPinned(n),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NoticeDetailScreen(noticeId: n.id),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NoticeCreateScreen()),
                );
                if (result == true) _loadData();
              },
              tooltip: '공지 작성',
              backgroundColor: brandBlue,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

// ---------- UI Parts ----------

class _NoticeCard extends StatelessWidget {
  final Notice notice;
  final String dateText;
  final bool pinned;
  final VoidCallback onTap;

  const _NoticeCard({
    required this.notice,
    required this.dateText,
    required this.pinned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = notice.title;
    final writer = notice.writer;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 아이콘/뱃지 자리
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  pinned ? Icons.push_pin : Icons.campaign,
                  color: const Color(0xFF3B8AFF),
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 뱃지
                    if (pinned) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B8AFF).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '중요',
                          style: TextStyle(
                            color: Color(0xFF3B8AFF),
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    Text(
                      title,
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            writer,
                            style: const TextStyle(color: Colors.black54, fontSize: 12.8),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          dateText,
                          style: const TextStyle(color: Colors.black45, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final String hintText;
  const _SearchField({required this.onChanged, this.hintText = '검색'});
  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(hintText: widget.hintText, border: InputBorder.none),
              onChanged: (v) {
                widget.onChanged(v);
                setState(() {});
              },
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              onPressed: () {
                controller.clear();
                widget.onChanged('');
                setState(() {});
              },
              icon: const Icon(Icons.close, size: 18, color: Colors.black38),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _EmptyState({
    this.icon = Icons.inbox_outlined,
    this.title = '항목이 없어요',
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.black26),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: const TextStyle(color: Colors.black54)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
            SizedBox(height: 12),
            Text('오류가 발생했습니다.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('다시 시도해주세요.', style: TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 7,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => _SkeletonCard(),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEDEFF5),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _line(width: double.infinity, height: 16),
                const SizedBox(height: 8),
                _line(width: 220, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: const Color(0xFFEDEFF5), borderRadius: BorderRadius.circular(8)),
    );
  }
}
