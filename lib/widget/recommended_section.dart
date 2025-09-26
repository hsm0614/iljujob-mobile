import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/ai_api.dart';
// ⬇️ 네 프로젝트의 Job 모델 경로로 수정
import 'package:iljujob/data/models/job.dart';

class RecommendedSection extends StatefulWidget {
  final AiApi api;
  const RecommendedSection({super.key, required this.api});

  @override
  State<RecommendedSection> createState() => _RecommendedSectionState();
}

class _RecommendedSectionState extends State<RecommendedSection> {
  int? workerId;
  List<dynamic> items = [];
  bool loading = true;
  final Set<int> seen = {};
  int? _loadingJobId; // 현재 상세 로딩 중인 jobId (버튼 로딩 상태 표시용)

  @override
  void initState() {
    super.initState();
    _loadAndFetch();
  }

  Future<void> _loadAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    workerId = prefs.getInt('userId');
    if (workerId == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    final res = await widget.api.fetchRecommended(workerId!, limit: 20);
    if (!mounted) return;
    setState(() {
      items = res;
      loading = false;
    });

    // 노출 로깅
    for (final it in res) {
      final id = (it['jobId'] as num).toInt();
      if (seen.add(id)) {
        widget.api.logEvent(workerId!, id, 'impression', ctx: {'from': 'home'});
      }
    }
  }

  Future<void> _openJobDetailById(int jobId) async {
    // 클릭 로그
    if (workerId != null) {
      widget.api.logEvent(workerId!, jobId, 'click', ctx: {'from': 'home'});
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

      // ✅ 기존 라우트 유지: '/job-detail'는 Job 객체를 기대
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

  @override
  Widget build(BuildContext context) {
    if (loading) return const _SkeletonRow();
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('AI 맞춤 추천', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 188, // 버튼 공간 조금 여유
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final it = items[i];
              final jobId = (it['jobId'] as num).toInt();
              final title = (it['title'] ?? '') as String;
              final meta =
                  '${it['location_city'] ?? ''} · ${it['category'] ?? ''} · ${it['distKm'] ?? ''}km';
              final chips = (it['reasons'] as List? ?? []).cast<String>();

              final isLoadingThis = _loadingJobId == jobId;

              return Container(
                width: 280,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 제목
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    // 위치/카테고리/거리
                    Text(
                      meta,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const Spacer(),
                    // 이유 배지
                    Wrap(
                      spacing: 6,
                      runSpacing: -6,
                      children: chips.take(3).map((r) {
                        return Chip(
                          label: Text(r, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    // 지원하기 버튼 → 상세 진입
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: ElevatedButton.icon(
                        onPressed: isLoadingThis ? null : () => _openJobDetailById(jobId),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1675f4), // 브랜드 컬러
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        icon: isLoadingThis
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.assignment_turned_in),
                        label: Text(isLoadingThis ? '불러오는 중...' : '지원하기'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 188,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Container(
          width: 280,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
