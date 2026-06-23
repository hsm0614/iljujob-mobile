// 📁 lib/presentation/screens/job_insight_sheet.dart
// ─ GET /api/job/:jobId/insight 단일 엔드포인트 사용
// ─ worker_events 기반 실시간 통계 + 급여/지원자 벤치마크 통합

import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:iljujob/data/services/job_insight_service.dart';
import 'package:iljujob/presentation/screens/subscription_plans_screen.dart';

class JobInsightSheet extends StatefulWidget {
  final int jobId;
  final String jobTitle;

  const JobInsightSheet({
    super.key,
    required this.jobId,
    required this.jobTitle,
  });

  static Future<void> show(
    BuildContext context, {
    required int jobId,
    required String jobTitle,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => JobInsightSheet(jobId: jobId, jobTitle: jobTitle),
    );
  }

  @override
  State<JobInsightSheet> createState() => _JobInsightSheetState();
}

class _JobInsightSheetState extends State<JobInsightSheet> {
  static const _blue = AppColors.primary;
  static const _bg = AppColors.bgPage;
  static const _border = AppColors.border;
  static const _text = AppColors.textPrimary;
  static const _label = AppColors.textTertiary;

  JobInsight? _data;
  bool _isLoading = true;
  bool _needsSubscription = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; _needsSubscription = false; });
    try {
      final d = await JobInsightService.getJobInsight(widget.jobId.toString());
      if (!mounted) return;
      setState(() { _data = d; _isLoading = false; });
    } on InsightSubscriptionRequiredException {
      if (!mounted) return;
      setState(() { _needsSubscription = true; _isLoading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = '인사이트를 불러오지 못했어요'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder:
          (_, ctrl) => Column(
            children: [
              // ── 핸들 ──
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),

              // ── 헤더 ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3182F6), Color(0xFF6C5CE7)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('✨', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AI 공고 인사이트',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: _text,
                            ),
                          ),
                          Text(
                            widget.jobTitle,
                            style: const TextStyle(fontSize: 12, color: _label),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),

              // ── 본문 ──
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_blue)))
                    : _needsSubscription
                    ? _buildSubscriptionGate()
                    : _error != null
                    ? _buildError()
                    : _buildContent(ctrl),
              ),
            ],
          ),
    );
  }

  Widget _buildSubscriptionGate() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3182F6), Color(0xFF6C5CE7)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text('✨', style: TextStyle(fontSize: 32)),
          ),
          const SizedBox(height: 16),
          const Text(
            '구독자 전용 기능이에요',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            '공고 인사이트는 구독 플랜에서\n이용할 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionPlansScreen()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('구독 플랜 보기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 40, color: Colors.grey),
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: Color(0xFF6B7280))),
        const SizedBox(height: 16),
        TextButton(onPressed: _load, child: const Text('다시 시도')),
      ],
    ),
  );

  Widget _buildContent(ScrollController ctrl) {
    final d = _data!;
    final fmt = NumberFormat('#,###');

    // 데이터 파싱
    final views = d.views;
    final applies = d.applies;
    final bookmarks = d.bookmarks;
    final applyRate = d.applyRate;
    final myHourly = d.myHourly;
    final avgHourly = d.avgHourly;
    final payLevel = d.payLevel;
    final similarCount = d.similarCount;
    final avgApplicants = d.avgApplicants;
    final peakHour = d.peakViewHour;

    return ListView(
      controller: ctrl,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        // ── 수치 카드 3개 ──
        Row(
          children: [
            _statCard(
              '조회수',
              '$views회',
              Icons.remove_red_eye_outlined,
              Colors.grey,
            ),
            const SizedBox(width: 10),
            _statCard('지원자', '$applies명', Icons.people_outline, _blue),
            const SizedBox(width: 10),
            _statCard(
              '북마크',
              '$bookmarks개',
              Icons.bookmark_outline,
              Colors.purple,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── 지원율 ──
        if (views > 0) ...[
          _sectionTitle('📊 전환율'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '조회→지원 전환율',
                      style: TextStyle(fontSize: 13, color: _label),
                    ),
                    Text(
                      '$applyRate%',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color:
                            applyRate >= d.benchApplyRate
                                ? Colors.green.shade600
                                : Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (applyRate / 100).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: _border,
                    valueColor: AlwaysStoppedAnimation(
                      applyRate >= d.benchApplyRate
                          ? Colors.green.shade400
                          : Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '업종 평균 ${d.benchApplyRate}%',
                      style: const TextStyle(fontSize: 11, color: _label),
                    ),
                    Text(
                      d.rateVsBench == 'above'
                          ? '평균보다 높아요 🔥'
                          : d.rateVsBench == 'below'
                          ? '평균보다 낮아요'
                          : '평균 수준',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color:
                            d.rateVsBench == 'above'
                                ? Colors.green.shade600
                                : _label,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── 시급 비교 ──
        if (myHourly > 0 && avgHourly > 0) ...[
          _sectionTitle('💰 시급 비교'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                _compareRow('내 시급', '${fmt.format(myHourly)}원', null),
                const SizedBox(height: 8),
                _compareRow(
                  '평균 시급',
                  '${fmt.format(avgHourly)}원',
                  payLevel == 'low'
                      ? Colors.red
                      : payLevel == 'high'
                      ? Colors.green
                      : Colors.orange,
                ),
                const SizedBox(height: 10),
                _payCompareBar(myHourly, avgHourly),
                const SizedBox(height: 8),
                _payLevelBadge(payLevel, myHourly, avgHourly, fmt),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── 지원자 비교 ──
        _sectionTitle('👥 지원자 비교'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Expanded(
                child: _bigNumber(
                  '$applies명',
                  '내 공고 지원자',
                  applies >= avgApplicants
                      ? Colors.green.shade600
                      : Colors.orange,
                ),
              ),
              Container(width: 1, height: 50, color: _border),
              Expanded(
                child: _bigNumber('$avgApplicants명', '업종 평균 지원자', Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── 피크 시간 ──
        if (peakHour >= 0 && views > 0) ...[
          _sectionTitle('⏰ 활동 패턴'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _blue.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Text('⏰', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$peakHour시에 알바생들이 가장 많이 공고를 봐요',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── AI 메시지 ──
        if (d.messages.isNotEmpty) ...[
          _sectionTitle('🤖 AI 분석'),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEEF5FF), Color(0xFFF3EEFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _blue.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:
                  d.messages
                      .map(
                        (m) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Text(
                                m.icon,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  m.text,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: _text,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          const SizedBox(height: 8),
          if (similarCount > 0)
            Text(
              '* 비슷한 공고 $similarCount개 기준',
              style: const TextStyle(fontSize: 11, color: _label),
            ),
        ],
      ],
    );
  }

  // ── 위젯 헬퍼 ──────────────────────────────────────────
  Widget _sectionTitle(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: _text,
    ),
  );

  Widget _statCard(String label, String value, IconData icon, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11, color: _label)),
            ],
          ),
        ),
      );

  Widget _compareRow(String label, String value, Color? vc) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(fontSize: 13, color: _label)),
      Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: vc ?? _text,
        ),
      ),
    ],
  );

  Widget _payCompareBar(int myH, int avgH) {
    final max = myH > avgH ? myH : avgH;
    final myRatio = max > 0 ? myH / max : 0.5;
    final avgRatio = max > 0 ? avgH / max : 0.5;
    return Column(
      children: [
        _bar(myRatio.toDouble(), _blue),
        const SizedBox(height: 4),
        _bar(avgRatio.toDouble(), Colors.orange),
        const SizedBox(height: 6),
        Row(
          children: [
            _dot(_blue),
            const SizedBox(width: 4),
            const Text('내 시급', style: TextStyle(fontSize: 10, color: _label)),
            const SizedBox(width: 12),
            _dot(Colors.orange),
            const SizedBox(width: 4),
            const Text('평균', style: TextStyle(fontSize: 10, color: _label)),
          ],
        ),
      ],
    );
  }

  Widget _bar(double v, Color c) => ClipRRect(
    borderRadius: BorderRadius.circular(99),
    child: LinearProgressIndicator(
      value: v,
      minHeight: 8,
      backgroundColor: _border,
      valueColor: AlwaysStoppedAnimation(c),
    ),
  );

  Widget _dot(Color c) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  Widget _payLevelBadge(String level, int myH, int avgH, NumberFormat fmt) {
    final diff = (myH - avgH).abs();
    String text;
    Color bg;
    Color fg;
    switch (level) {
      case 'high':
        text = '평균보다 ${fmt.format(diff)}원 높아요 🎉';
        bg = Colors.green.withOpacity(0.1);
        fg = Colors.green.shade700;
        break;
      case 'low':
        text = '평균보다 ${fmt.format(diff)}원 낮아요 📢 시급 인상을 고려해보세요';
        bg = Colors.red.withOpacity(0.1);
        fg = Colors.red.shade700;
        break;
      default:
        text = '평균과 비슷한 시급이에요 👍';
        bg = Colors.orange.withOpacity(0.1);
        fg = Colors.orange.shade700;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _bigNumber(String value, String label, Color color) => Column(
    children: [
      Text(
        value,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: _label)),
    ],
  );
}
