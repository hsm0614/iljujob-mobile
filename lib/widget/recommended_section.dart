import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';

import '../../data/services/ai_api.dart';
import 'package:iljujob/data/models/job.dart';

class RecommendedSection extends StatefulWidget {
  final AiApi api;

  /// 시트/페이지에서 타이틀을 이미 그리고 있으면 false 추천
  final bool showHeader;

  /// 바깥 패딩을 시트에서 주는 경우가 많아서 기본은 0
  final EdgeInsetsGeometry padding;

  const RecommendedSection({
    super.key,
    required this.api,
    this.showHeader = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<RecommendedSection> createState() => _RecommendedSectionState();
}

class _RecommendedSectionState extends State<RecommendedSection> {
  int? workerId;
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  int? _loadingJobId;

  @override
  void initState() {
    super.initState();
    _loadAndFetch();
  }

  Future<void> _loadAndFetch() async {
    setState(() => loading = true);

    final prefs = await SharedPreferences.getInstance();
    workerId = prefs.getInt('userId');

    if (workerId == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    try {
      final res = await widget.api.fetchRecommended(workerId!, limit: 20);
      if (!mounted) return;

      setState(() {
        items = (res as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        items = [];
        loading = false;
      });
    }
  }

  Future<void> _openJobDetailById(int jobId) async {
    if (workerId != null) {
      widget.api.logEvent(workerId!, jobId, 'click', ctx: {'from': 'ai_sheet'});
    }

    setState(() => _loadingJobId = jobId);
    try {
      final raw = await widget.api.fetchJobDetailRaw(jobId);
      if (!mounted) return;

      if (raw == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공고 상세를 불러오지 못했습니다.')),
        );
        return;
      }

      final job = Job.fromJson(raw);
      Navigator.pushNamed(context, '/job-detail', arguments: job);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingJobId = null);
    }
  }

  String _metaText(Map<String, dynamic> it) {
    final city = (it['location_city'] ?? '').toString().trim();
    final category = (it['category'] ?? '').toString().trim();

    final distRaw = it['distKm'];
    String dist = '';
    if (distRaw != null) {
      final d = double.tryParse(distRaw.toString());
      if (d != null) dist = d < 10 ? d.toStringAsFixed(1) : d.toStringAsFixed(0);
    }

    final parts = <String>[];
    if (city.isNotEmpty) parts.add(city);
    if (category.isNotEmpty) parts.add(category);
    if (dist.isNotEmpty) parts.add('${dist}km');

    return parts.isEmpty ? '추천 공고' : parts.join(' · ');
  }

  List<String> _reasons(Map<String, dynamic> it) {
    final r = it['reasons'];
    if (r is List) {
      return r.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 로딩
    if (loading) {
      return Padding(
        padding: widget.padding,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset(
                'assets/lottie/ai_loading.json',
                width: 130,
                height: 130,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 10),
              const Text(
                'AI가 나에게 맞는 공고를 찾는 중이에요...',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // ✅ 빈 상태
    if (items.isEmpty) {
      return Padding(
        padding: widget.padding,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 18, color: Color(0xFF3B8AFF)),
                  SizedBox(width: 8),
                  Text(
                    '아직 추천 공고가 없어요',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '프로필(성별/희망직종)과 위치를 채우면 추천 정확도가 확 올라가요.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.2),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: _loadAndFetch,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('다시 불러오기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3B8AFF),
                      side: BorderSide(color: const Color(0xFF3B8AFF).withOpacity(.35)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ✅ 세로 리스트 (가로 스와이프 제거)
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showHeader) ...[
            const Text(
              'AI 맞춤 추천',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '총 ${items.length}개 추천',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 10),
          ],

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(), // ✅ 바깥(시트)이 스크롤 담당
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final it = items[i];
              final jobId = (it['jobId'] as num).toInt();
              final title = (it['title'] ?? '').toString();
              final meta = _metaText(it);
              final chips = _reasons(it);
              final isLoadingThis = _loadingJobId == jobId;

              return _AiJobCard(
                title: title,
                meta: meta,
                reasons: chips,
                loading: isLoadingThis,
                onTap: () => _openJobDetailById(jobId),
              );
            },
          ),

          const SizedBox(height: 8),
         
        ],
      ),
    );
  }
}

class _AiJobCard extends StatelessWidget {
  final String title;
  final String meta;
  final List<String> reasons;
  final bool loading;
  final VoidCallback onTap;

  const _AiJobCard({
    required this.title,
    required this.meta,
    required this.reasons,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shown = reasons.take(3).toList();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 타이틀 + 메타
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                meta,
                style: const TextStyle(fontSize: 12.5, color: Colors.black54),
              ),

              if (shown.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: shown.map((r) => _ReasonChip(text: r)).toList(),
                ),
              ],

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  onPressed: loading ? null : onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1675f4),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (loading) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        const Text('불러오는 중...', style: TextStyle(fontWeight: FontWeight.w800)),
                      ] else ...[
                        const Icon(Icons.send_rounded, size: 18),
                        const SizedBox(width: 8),
                        const Text('지원하기', style: TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String text;
  const _ReasonChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF3B8AFF).withOpacity(.22)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1E2A3A),
        ),
      ),
    );
  }
}
