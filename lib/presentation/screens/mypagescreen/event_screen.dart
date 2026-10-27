import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'event_detail_screen.dart';
import '../../../config/constants.dart'; // baseUrl
import '../../../config/app_theme.dart';
import '../../../config/messages.dart';
import '../../../widget/app_ui.dart';

/// 이벤트 (2026-10 리디자인 — 당근 이벤트 목록 참고). 파란 헤더·검색 → 일반 앱바,
/// 진행 중을 위로, 끝난 이벤트는 흐리게.
class EventScreen extends StatefulWidget {
  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  List<Map<String, dynamic>> events = [];
  bool isLoading = true;
  String? error;

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
      if (res.statusCode != 200) {
        throw Exception('이벤트 불러오기 실패 (${res.statusCode})');
      }
      final list = List<Map<String, dynamic>>.from(json.decode(res.body));
      // 진행 중 먼저 (같은 묶음 안에선 서버 순서 유지)
      final ongoing = list.where(eventOngoing).toList();
      final ended = list.where((e) => !eventOngoing(e)).toList();
      if (!mounted) return;
      setState(() {
        events = [...ongoing, ...ended];
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = Msg.server;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCard,
      appBar: AppBar(title: const Text('이벤트')),
      body: RefreshIndicator(
        onRefresh: _fetchEvents,
        child:
            isLoading
                ? const AppSkeletonList(rows: 4)
                : error != null
                ? AppEmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: '이벤트를 불러오지 못했어요',
                  message: error,
                  actionLabel: '다시 시도',
                  onAction: _fetchEvents,
                  secondaryAction: true,
                )
                : events.isEmpty
                ? const AppEmptyState(
                  icon: Icons.card_giftcard_rounded,
                  title: '지금 진행 중인 이벤트가 없어요',
                  message: '새 이벤트가 열리면 여기서 알려 드릴게요.',
                )
                : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 24),
                  itemBuilder: (context, i) => _EventItem(event: events[i]),
                ),
      ),
    );
  }
}

class _EventItem extends StatelessWidget {
  final Map<String, dynamic> event;
  const _EventItem({required this.event});

  @override
  Widget build(BuildContext context) {
    final img = eventImageUrl(event['image_url']?.toString());
    final ongoing = eventOngoing(event);
    final period = eventPeriod(event);

    final body = InkWell(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
          ),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: AppColors.bgMuted,
                child:
                    img.isEmpty
                        ? const Icon(
                          Icons.card_giftcard_rounded,
                          size: 40,
                          color: AppColors.textDisabled,
                        )
                        : Image.network(
                          img,
                          fit: BoxFit.contain,
                          errorBuilder:
                              (_, __, ___) => const Icon(
                                Icons.card_giftcard_rounded,
                                size: 40,
                                color: AppColors.textDisabled,
                              ),
                        ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            (event['title'] ?? '').toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.jobTitle,
          ),
          const SizedBox(height: 2),
          Text(
            [ongoing ? '진행 중' : '종료', if (period.isNotEmpty) period].join(' · '),
            style: AppTextStyles.jobMeta,
          ),
        ],
      ),
    );
    return ongoing ? body : Opacity(opacity: 0.5, child: body);
  }
}
