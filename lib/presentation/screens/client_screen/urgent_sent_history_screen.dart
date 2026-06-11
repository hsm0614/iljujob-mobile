// lib/presentation/screens/client_screen/urgent_sent_history_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../../config/app_theme.dart';
import '../../../config/constants.dart';
import '../../chat/chat_room_screen.dart';

class UrgentSentHistoryScreen extends StatefulWidget {
  final int clientId;
  final int? jobId;
  final String? jobTitle;

  const UrgentSentHistoryScreen({
    super.key,
    required this.clientId,
    this.jobId,
    this.jobTitle,
  });

  @override
  State<UrgentSentHistoryScreen> createState() => _UrgentSentHistoryScreenState();
}

class _UrgentSentHistoryScreenState extends State<UrgentSentHistoryScreen> {
  List<dynamic> _logs = [];
  bool _loading = true;
  String? _token;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('authToken') ?? '';
    setState(() => _loading = true);
    try {
      final params = {
        'clientId': '${widget.clientId}',
        if (widget.jobId != null) 'jobId': '${widget.jobId}',
      };
      final uri = Uri.parse('$baseUrl/api/direct-messages/sent-history')
          .replace(queryParameters: params);
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $_token'});
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _logs = data['logs'] ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _statusLabel(String s) => switch (s) {
    'sent'          => '대기중',
    'accepted'      => '수락됨',
    'time_adjusted' => '시간 조정',
    'rejected'      => '거절됨',
    'no_response'   => '무응답',
    _               => s,
  };

  Color _statusColor(String s) => switch (s) {
    'accepted'      => const Color(0xFF22C55E),
    'rejected' || 'no_response' => const Color(0xFFEF4444),
    'time_adjusted' => const Color(0xFFFF9500),
    _               => const Color(0xFF9CA3AF),
  };

  String _grade(int score) {
    if (score >= 100) return 'S';
    if (score >= 70)  return 'A';
    if (score >= 40)  return 'B';
    if (score >= 20)  return 'C';
    return 'NEW';
  }

  Color _gradeColor(int score) {
    if (score >= 100) return const Color(0xFFAB47BC);
    if (score >= 70)  return const Color(0xFFEF4444);
    if (score >= 40)  return AppColors.primary;
    if (score >= 20)  return const Color(0xFF6B7280);
    return const Color(0xFF9CA3AF);
  }

  String _relTime(String? raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return '방금 전';
      if (diff.inHours < 1) return '${diff.inMinutes}분 전';
      if (diff.inHours < 24) return '${diff.inHours}시간 전';
      if (diff.inDays < 7) return '${diff.inDays}일 전';
      return DateFormat('M/d').format(dt);
    } catch (_) {
      return '';
    }
  }

  void _openChat(dynamic log) {
    final chatRoomId = log['chat_room_id'];
    if (chatRoomId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          chatRoomId: chatRoomId,
          jobInfo: {
            'id': widget.jobId,
            'title': widget.jobTitle ?? '긴급 호출',
            'client_id': widget.clientId,
            'worker_id': log['worker_id'],
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.jobTitle != null ? '⚡ ${widget.jobTitle}' : '⚡ 긴급호출 발송이력',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _logs.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _logs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _buildItem(_logs[i]),
                  ),
                ),
    );
  }

  Widget _buildItem(dynamic log) {
    final score = (log['activity_score'] as num?)?.toInt() ?? 0;
    final grade = _grade(score);
    final gradeColor = _gradeColor(score);
    final status = log['status']?.toString() ?? 'sent';
    final statusColor = _statusColor(status);
    final rawName = log['worker_name']?.toString() ?? '알바생';
    final maskedName = rawName.length > 1
        ? rawName[0] + ('*' * (rawName.length - 1))
        : rawName;
    final hasChatRoom = log['chat_room_id'] != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // 프로필 아바타
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.bgMuted,
            backgroundImage: log['profile_image_url'] != null
                ? NetworkImage(log['profile_image_url']) as ImageProvider
                : null,
            child: log['profile_image_url'] == null
                ? const Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 22)
                : null,
          ),
          const SizedBox(width: 12),

          // 이름 + 시간
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(maskedName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: gradeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(grade,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: gradeColor)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(_relTime(log['sent_at']?.toString()),
                    style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),

          // 상태 + 채팅 버튼
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(_statusLabel(status),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
              ),
              if (hasChatRoom) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _openChat(log),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('채팅 보기',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.flash_off_rounded, size: 48, color: AppColors.textDisabled),
          SizedBox(height: 12),
          Text('발송이력이 없어요',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          SizedBox(height: 6),
          Text('긴급호출을 보내면 여기서 응답 현황을 확인할 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
        ],
      ),
    );
  }
}
