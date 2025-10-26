import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/ai_api.dart';
// ⬇️ 네 프로젝트의 Job 모델 경로로 수정
import 'package:iljujob/data/models/job.dart';
import 'package:lottie/lottie.dart'; // 👈 꼭 추가해줘요

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
  print('📡 workerId = $workerId');

  if (workerId == null) {
    if (mounted) setState(() => loading = false);
    print('⚠️ workerId가 null이므로 추천 안 불러옴');
    return;
  }

  try {
    print('🚀 fetchRecommended 호출 시작');
    final res = await widget.api.fetchRecommended(workerId!, limit: 20);
    print('✅ fetchRecommended 결과: ${res.length}개');
    if (!mounted) return;

    setState(() {
      items = res;
      loading = false;
    });
  } catch (e) {
    print('❌ fetchRecommended 예외 발생: $e');
    if (mounted) setState(() => loading = false);
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
  // ✅ 1. 로딩 중일 때 Lottie 애니메이션 표시
  if (loading) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🔹 Lottie 파일은 프로젝트에 직접 추가해야 합니다
          Lottie.asset(
            'assets/lottie/ai_loading.json', // ⚠️ 여기에 실제 경로 입력
            width: 140,
            height: 140,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 12),
          const Text(
            'AI가 나에게 맞는 공고를 찾는 중이에요...',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ✅ 2. 추천 결과가 비어있을 때
  if (items.isEmpty) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          '아직 추천 공고가 없습니다.\n프로필을 더 작성하면 AI가 더 잘 추천해드려요!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black45, fontSize: 13),
        ),
      ),
    );
  }

  // ✅ 3. 추천 결과 표시 (기존 UI 유지)
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('AI 맞춤 추천',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      SizedBox(
        height: 188,
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
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    meta,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const Spacer(),
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
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: ElevatedButton.icon(
                      onPressed: isLoadingThis
                          ? null
                          : () => _openJobDetailById(jobId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1675f4),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      icon: isLoadingThis
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.assignment_turned_in),
                      label:
                          Text(isLoadingThis ? '불러오는 중...' : '지원하기'),
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
