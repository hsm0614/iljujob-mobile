import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'event_detail_screen.dart';
import '../../../config/constants.dart'; // baseUrl

class EventScreen extends StatefulWidget {
  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  List<dynamic> events = [];
  bool isLoading = true;
  String? error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/events'));
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        setState(() {
          events = List.from(decoded);
          isLoading = false;
        });
      } else {
        throw Exception('이벤트 불러오기 실패 (${res.statusCode})');
      }
    } catch (e) {
      setState(() {
        error = '이벤트를 불러오지 못했습니다.';
        isLoading = false;
      });
    }
  }

  // ---- Helpers ----
  String _resolveImage(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    if (url.startsWith('http')) return url;
    // 중복 슬래시 방지
    final path = url.replaceFirst(RegExp(r'^/+'), '');
    return '$baseUrl/$path';
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '';
    try {
      final s = v.toString();
      final date =
          DateTime.tryParse(s) ??
          DateTime.tryParse(s.split(' ').first) ??
          DateTime.now();
      return '${date.year}.${_2(date.month)}.${_2(date.day)}';
    } catch (_) {
      return v.toString();
    }
  }

  String _period(Map e) {
    final s = _fmtDate(e['start_date']);
    final d = _fmtDate(e['end_date']);
    if (s.isEmpty && d.isEmpty) return '';
    if (s.isEmpty) return '~ $d';
    if (d.isEmpty) return '$s ~';
    return '$s ~ $d';
  }

  bool _isOngoing(Map e) {
    try {
      final now = DateTime.now();
      final s =
          DateTime.tryParse(e['start_date'] ?? '') ??
          now.subtract(const Duration(days: 9999));
      final d =
          DateTime.tryParse(e['end_date'] ?? '') ??
          now.add(const Duration(days: 9999));
      return !now.isBefore(s) && !now.isAfter(d);
    } catch (_) {
      return true;
    }
  }

  String _badgeText(Map e) => _isOngoing(e) ? '진행중' : '종료';
  Color _badgeColor(Map e) =>
      _isOngoing(e) ? const Color(0xFF3B8AFF) : Colors.grey;

  @override
  Widget build(BuildContext context) {
    // 검색 필터
    final q = _query.trim().toLowerCase();
    final filtered =
        events.where((e) {
          if (q.isEmpty) return true;
          final title = (e['title'] ?? '').toString().toLowerCase();
          final desc = (e['description'] ?? '').toString().toLowerCase();
          return title.contains(q) || desc.contains(q);
        }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: RefreshIndicator(
        onRefresh: _fetchEvents,
        color: const Color(0xFF3B8AFF),
        child: CustomScrollView(
          slivers: [
            // 헤더
            SliverAppBar(
              pinned: true,
              elevation: 0,
              backgroundColor: Colors.white,
              expandedHeight: 170,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3B8AFF), Color(0xFF6EB6FF)],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ✅ 상단: 뒤로가기 + 타이틀
                          Row(
                            children: [
                              InkWell(
                                onTap: () => Navigator.maybePop(context),
                                borderRadius: BorderRadius.circular(999),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_back_ios_new,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                '이벤트',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // ✅ 검색
                          _SearchField(
                            hintText: '이벤트 검색',
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

            if (isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _SkeletonList(),
              )
            else if (error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorState(message: error!, onRetry: _fetchEvents),
              )
            else if (filtered.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: Icons.celebration_outlined,
                  title: '진행 중인 이벤트가 없습니다.',
                  subtitle: '새로운 이벤트가 오면 여기로 모아둘게요.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder:
                      (context, i) => _EventCard(
                        event: filtered[i] as Map,
                        resolveImage: _resolveImage,
                        periodText: _period,
                        badgeText: _badgeText,
                        badgeColor: _badgeColor,
                        onTap: (e) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => EventDetailScreen(
                                    event: e as Map<String, dynamic>,
                                  ),
                            ),
                          );
                        },
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------- UI Parts ----------

class _EventCard extends StatelessWidget {
  final Map event;
  final String Function(String?) resolveImage;
  final String Function(Map) periodText;
  final String Function(Map) badgeText;
  final Color Function(Map) badgeColor;
  final void Function(Map) onTap;

  const _EventCard({
    required this.event,
    required this.resolveImage,
    required this.periodText,
    required this.badgeText,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final img = resolveImage(event['image_url']);
    final title = (event['title'] ?? '').toString();
    final description = (event['description'] ?? '').toString().replaceAll(
      r'\n',
      '\n',
    );
    final period = periodText(event);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: () => onTap(event),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 썸네일
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: const Color(0xFFE9EEF8), // ✅ 빈 공간 배경
                  child:
                      img.isNotEmpty
                          ? Image.network(
                            img,
                            fit: BoxFit.contain, // ✅ 온전하게 보이게
                            errorBuilder:
                                (_, __, ___) => const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    size: 40,
                                    color: Colors.black26,
                                  ),
                                ),
                          )
                          : const Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 40,
                              color: Colors.black26,
                            ),
                          ),
                ),
              ),
            ),

            // 본문
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 뱃지 + 기간
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor(event).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badgeText(event),
                          style: TextStyle(
                            color: badgeColor(event),
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      if (period.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '📅 $period',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 제목
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  // 설명
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.25,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
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
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: widget.hintText,
                border: InputBorder.none,
              ),
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
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
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
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
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => _SkeletonCard(),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // 썸네일 자리
          Container(
            height: 160, // 16:9 근사
            decoration: const BoxDecoration(
              color: Color(0xFFEDEFF5),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _shimmerLine(width: 60, height: 18),
                const SizedBox(height: 10),
                _shimmerLine(width: double.infinity, height: 16),
                const SizedBox(height: 6),
                _shimmerLine(width: double.infinity, height: 16),
                const SizedBox(height: 6),
                _shimmerLine(width: 180, height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmerLine({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEDEFF5),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

// utils
String _2(int n) => n < 10 ? '0$n' : '$n';
