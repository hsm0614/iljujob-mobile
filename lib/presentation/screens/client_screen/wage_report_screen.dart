// 임금 AI 리포트 화면 — 사장님이 급여 설정 전 시장 데이터 + AI 분석 확인

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/services/ai_labor_service.dart';

class WageReportScreen extends StatefulWidget {
  final String category;
  final String? locationCity;
  final String payType;
  final int? currentPay;
  final int hours;

  const WageReportScreen({
    super.key,
    required this.category,
    this.locationCity,
    this.payType = '시급',
    this.currentPay,
    this.hours = 8,
  });

  @override
  State<WageReportScreen> createState() => _WageReportScreenState();
}

class _WageReportScreenState extends State<WageReportScreen> {
  WageReport? _report;
  bool _loading = true;
  String? _error;
  bool _needsSubscription = false;

  final _fmt = NumberFormat('#,###', 'ko_KR');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _needsSubscription = false;
    });
    try {
      final r = await AiLaborService.getWageReport(
        category: widget.category,
        locationCity: widget.locationCity,
        payType: widget.payType,
        pay: widget.currentPay,
        hours: widget.hours,
      );
      if (mounted) setState(() { _report = r; _loading = false; });
    } on SubscriptionRequiredException {
      if (mounted) setState(() { _needsSubscription = true; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('임금 AI 리포트'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : _needsSubscription
              ? _buildSubscriptionGate()
              : _error != null
                  ? _buildError()
                  : _buildBody(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _load, child: const Text('다시 시도')),
        ],
      ),
    );
  }

  Widget _buildSubscriptionGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFF3B8AFF),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '구독자 전용 기능이에요',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Color(0xFF191F28),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '임금 AI 리포트는 라이트 이상 구독자만\n이용할 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/subscribe'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B8AFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  '구독 플랜 보기',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final r = _report!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 ─────────────────────────────────────────────────
          _sectionHeader(
            '${r.category} 급여 시장 분석',
            '${r.locationCity} · ${r.sampleLocal}건 분석',
          ),
          const SizedBox(height: 12),

          // ── 급여 분포 카드 ────────────────────────────────────────
          _card(
            children: [
              _payRangeBar(r),
              const SizedBox(height: 16),
              Row(
                children: [
                  _statItem('최저', r.minHourly, Colors.orange),
                  _statItem('평균', r.avgHourly, const Color(0xFF2563EB)),
                  _statItem('최고', r.maxHourly, Colors.green),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _statItem('전국평균', r.nationAvg, Colors.grey),
                  _statItem('고지원율', r.highApply, Colors.purple),
                  _statItem(
                    '추천시급',
                    r.recommendedHourly,
                    const Color(0xFF16A34A),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 현재 급여 위치 (입력된 경우) ─────────────────────────
          if (r.currentHourly != null) ...[
            _currentPayCard(r),
            const SizedBox(height: 12),
          ],

          // ── AI 분석 텍스트 ────────────────────────────────────────
          _card(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'AI 분석',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Gemini AI 리포트',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                r.aiAnalysis.isEmpty ? '분석 데이터가 부족합니다.' : r.aiAnalysis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 추천 급여 배너 ────────────────────────────────────────
          _recommendCard(r),
          const SizedBox(height: 24),

          // ── 데이터 출처 ───────────────────────────────────────────
          Center(
            child: Text(
              '* 알바일주 DB 기반 분석 · ${r.cached ? '캐시' : '실시간'} · 2026년 최저임금 10,320원 기준',
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ── 급여 분포 바 ─────────────────────────────────────────────────
  Widget _payRangeBar(WageReport r) {
    final total = (r.maxHourly - r.minHourly).clamp(1, double.infinity);
    final currentRatio =
        r.currentHourly != null
            ? ((r.currentHourly! - r.minHourly) / total).clamp(0.0, 1.0)
            : null;
    final avgRatio = ((r.avgHourly - r.minHourly) / total).clamp(0.0, 1.0);
    final recRatio = ((r.recommendedHourly - r.minHourly) / total).clamp(
      0.0,
      1.0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '시장 급여 분포',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (ctx, box) {
            final w = box.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // 배경 바
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFBFDBFE), Color(0xFF2563EB)],
                    ),
                  ),
                ),
                // 평균 마커
                Positioned(
                  left: (w * avgRatio - 1).clamp(0, w - 2),
                  top: -4,
                  child: Container(
                    width: 2,
                    height: 16,
                    color: const Color(0xFF1D4ED8),
                  ),
                ),
                // 추천 마커
                Positioned(
                  left: (w * recRatio - 1).clamp(0, w - 2),
                  top: -4,
                  child: Container(width: 2, height: 16, color: Colors.green),
                ),
                // 현재 급여 마커
                if (currentRatio != null)
                  Positioned(
                    left: (w * currentRatio - 6).clamp(0, w - 12),
                    top: -8,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _percentileColor(r.percentile),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_fmt.format(r.minHourly)}원',
              style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
            ),
            Text(
              '${_fmt.format(r.maxHourly)}원',
              style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ],
    );
  }

  // ── 현재 급여 위치 카드 ──────────────────────────────────────────
  Widget _currentPayCard(WageReport r) {
    final pct = r.percentile;
    final color = _percentileColor(pct);
    final label =
        pct == null
            ? '분석 중'
            : pct >= 70
            ? '시장 상위'
            : pct >= 40
            ? '시장 평균'
            : '시장 하위';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.15),
            ),
            child: Center(
              child: Text(
                pct != null ? '$pct%' : '-',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '현재 시급 ${_fmt.format(r.currentHourly)}원',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '시장 내 $label (${pct != null ? '$pct 퍼센타일' : ''})',
                  style: TextStyle(fontSize: 13, color: color),
                ),
                if (r.applyRateUplift != null && r.applyRateUplift! > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '추천 시급으로 올리면 지원자 +${r.applyRateUplift}% 예상',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 추천 급여 배너 ───────────────────────────────────────────────
  Widget _recommendCard(WageReport r) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16A34A), Color(0xFF15803D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI 추천 급여',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '시급 ${_fmt.format(r.recommendedHourly)}원',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (widget.payType != '시급')
                  Text(
                    '${widget.payType} ${_fmt.format(r.recommendedPay)}원',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '적용하기',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, int value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '${_fmt.format(value)}원',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
      ],
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Color _percentileColor(int? pct) {
    if (pct == null) return Colors.grey;
    if (pct >= 70) return Colors.green;
    if (pct >= 40) return const Color(0xFF2563EB);
    return Colors.orange;
  }
}
