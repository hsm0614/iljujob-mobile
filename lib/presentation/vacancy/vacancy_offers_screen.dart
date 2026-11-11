import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../data/services/vacancy_service.dart';
import '../../main.dart' show openChatRoomById;
import '../../widget/app_ui.dart';

/// 알바생: 받은 대체 근무 제안 — [할게요] 먼저 누른 한 명만 확정 (2026-11-11)
class VacancyOffersScreen extends StatefulWidget {
  const VacancyOffersScreen({super.key});

  @override
  State<VacancyOffersScreen> createState() => _VacancyOffersScreenState();
}

class _VacancyOffersScreenState extends State<VacancyOffersScreen> {
  List<Map<String, dynamic>>? _offers;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await VacancyService.myOffers();
    if (mounted) setState(() => _offers = list);
  }

  Future<void> _answer(Map<String, dynamic> o, bool accept) async {
    final id = (o['offerId'] as num).toInt();
    setState(() => _busyId = id);
    try {
      final roomId = await VacancyService.respond(id, accept);
      if (!mounted) return;
      if (accept && roomId != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('근무가 확정됐어요.')));
        openChatRoomById(roomId);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busyId = null);
      _load();
    }
  }

  String _when(Map<String, dynamic> o) {
    final d = DateTime.tryParse(o['workDate']?.toString() ?? '');
    final day = d == null ? '' : '${d.month}월 ${d.day}일(${'월화수목금토일'[d.weekday - 1]})';
    String hm(Object? t) => (t?.toString() ?? '').padRight(5).substring(0, 5);
    return '$day ${hm(o['startTime'])}~${hm(o['endTime'])}';
  }

  @override
  Widget build(BuildContext context) {
    final offers = _offers;
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AppBar(title: const Text('대체 근무 제안')),
      body: offers == null
          ? const AppSkeletonList(rows: 3)
          : offers.isEmpty
              ? const AppEmptyState(
                  icon: Icons.inbox_outlined,
                  title: '받은 제안이 없어요',
                  message: '이미 마감됐거나 다른 분이 먼저 수락했을 수 있어요.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: offers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final o = offers[i];
                      final busy = _busyId == (o['offerId'] as num).toInt();
                      final wage = (o['wage'] as num?)?.toInt() ?? 0;
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o['company']?.toString() ?? '사장님', style: AppTextStyles.h3),
                            const SizedBox(height: 4),
                            Text(
                              '${_when(o)}${wage > 0 ? ' · ${NumberFormat('#,###').format(wage)}원' : ''}',
                              style: AppTextStyles.body1,
                            ),
                            if ((o['location']?.toString() ?? '').isNotEmpty)
                              Text(o['location'].toString(), style: AppTextStyles.body2),
                            const SizedBox(height: 12),
                            Text(o['message']?.toString() ?? '', style: AppTextStyles.body2),
                            // AI 기본법: 생성형 AI가 쓴 글은 받는 사람에게 표시
                            if (o['aiWritten'] == 1 || o['aiWritten'] == true) ...[
                              const SizedBox(height: 4),
                              const Text('AI가 쓴 안내문이에요', style: AppTextStyles.caption),
                            ],
                            const SizedBox(height: 16),
                            Row(children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy ? null : () => _answer(o, false),
                                  child: const Text('어려워요'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                  onPressed: busy ? null : () => _answer(o, true),
                                  child: const Text('할게요'),
                                ),
                              ),
                            ]),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
