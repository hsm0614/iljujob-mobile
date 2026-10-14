import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';
import 'package:iljujob/data/services/job_service.dart';
import 'package:iljujob/data/services/screen_analytics_service.dart';
import 'package:iljujob/main.dart' show openChatRoomById;
import 'package:iljujob/utils/pay_display.dart';
import 'job_detail_screen.dart';

/// 구직자 홈 상단 카드 두 장 (서버 GET /api/worker/home-nudges).
///  - 사장님이 먼저 연락한 제안: 채팅 목록에 묻혀 86%가 안 읽혔다.
///  - 답 없는 지원 → 근처 비슷한 공고: 지원 후 무응답이 30일 지원방의 57%.
/// 둘 다 없으면 아무것도 그리지 않는다.
class HomeNudges extends StatefulWidget {
  const HomeNudges({super.key});

  @override
  State<HomeNudges> createState() => _HomeNudgesState();
}

class _HomeNudgesState extends State<HomeNudges> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _proposals = const [];
  Map<String, dynamic>? _waiting;
  bool _viewLogged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final resp = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/worker/home-nudges'),
      );
      if (resp.statusCode != 200 || !mounted) return;
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      setState(() {
        _proposals = List<Map<String, dynamic>>.from(d['proposals'] ?? []);
        _waiting =
            d['waiting'] is Map ? Map<String, dynamic>.from(d['waiting']) : null;
      });
      if (!_viewLogged && (_proposals.isNotEmpty || _waiting != null)) {
        _viewLogged = true;
        ScreenAnalyticsService.instance.logEvent(
          'home_nudge_view',
          params: {
            'proposals': _proposals.length,
            'waiting': _waiting == null ? 0 : 1,
          },
        );
      }
    } catch (_) {
      // 홈 본문을 막지 않는다
    }
  }

  void _log(String kind) => ScreenAnalyticsService.instance.logEvent(
    'home_nudge_tap',
    params: {'kind': kind},
  );

  Future<void> _openProposal(Map<String, dynamic> p) async {
    final roomId = int.tryParse('${p['chat_room_id']}');
    if (roomId == null) return;
    _log('proposal');
    await openChatRoomById(roomId);
    // 채팅방은 named route 로 열려 돌아오는 시점을 못 잡는다 — 잠시 뒤 다시 읽는다.
    Future.delayed(const Duration(seconds: 2), _load);
  }

  Future<void> _openJob(Map<String, dynamic> j) async {
    final id = int.tryParse('${j['job_id']}');
    if (id == null) return;
    _log('similar_job');
    final token = await AuthenticatedHttpClient.accessToken();
    final job = await JobService.fetchJobByIdWithToken(id, token);
    if (job == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final similar = List<Map<String, dynamic>>.from(_waiting?['similar'] ?? []);
    if (_proposals.isEmpty && similar.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_proposals.isNotEmpty)
          _section(
            title: '사장님이 먼저 연락했어요',
            subtitle: '24시간 안에 답하면 채용 가능성이 높아요',
            rows: [
              for (final p in _proposals)
                _row(
                  title: '${p['company_name'] ?? '사장님'} · ${p['title'] ?? ''}',
                  meta: _meta(p),
                  action: '확인',
                  onTap: () => _openProposal(p),
                ),
            ],
          ),
        if (similar.isNotEmpty)
          _section(
            title: '아직 사장님이 확인 전이에요',
            subtitle:
                "'${_waiting?['jobTitle'] ?? ''}' 기다리는 동안 근처 비슷한 공고도 보세요",
            rows: [
              for (final j in similar)
                _row(
                  title: '${j['title'] ?? ''}',
                  meta: _meta(j),
                  action: '보기',
                  onTap: () => _openJob(j),
                ),
            ],
          ),
      ],
    );
  }

  String _meta(Map<String, dynamic> m) {
    final parts = <String>[];
    if (m['pay'] != null) {
      parts.add(
        formatJobPay('${m['pay']}', m['pay_type']?.toString(), includeType: true),
      );
    }
    final dist = double.tryParse('${m['distance_m'] ?? ''}');
    if (dist != null) {
      parts.add(
        dist < 1000
            ? '${dist.round()}m'
            : '${(dist / 1000).toStringAsFixed(1)}km',
      );
    }
    return parts.join(' · ');
  }

  Widget _section({
    required String title,
    required String subtitle,
    required List<Widget> rows,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.body1.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          ...rows,
        ],
      ),
    );
  }

  Widget _row({
    required String title,
    required String meta,
    required String action,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body2.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              action,
              style: AppTextStyles.captionBold.copyWith(
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
