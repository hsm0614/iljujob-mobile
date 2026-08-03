import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/data/services/job_insight_service.dart';
import 'package:iljujob/utils/pay_display.dart';

const _kBrand = AppColors.primary;
const _kBg = AppColors.bgPage;
const _kBorder = AppColors.border;
const _kText = AppColors.textPrimary;
// textTertiary(#9CA3AF)는 _kBg 위 2.35:1로 WCAG AA 미달이라 승격.
const _kLabel = AppColors.textSecondary;

class JobPreviewDetailScreen extends StatefulWidget {
  final String title;
  final String category;
  final String location;
  final double lat;
  final double lng;
  final String? startDate;
  final String? endDate;
  final List<String> weekdays;
  final String workingTime;
  final String payType;
  final int pay;
  final String description;
  final List<File> images;
  final String companyName;
  final String managerName;
  final VoidCallback onSubmit;
  final VoidCallback? onEdit;

  const JobPreviewDetailScreen({
    super.key,
    required this.title,
    required this.category,
    required this.location,
    required this.lat,
    required this.lng,
    this.startDate,
    this.endDate,
    required this.weekdays,
    required this.workingTime,
    required this.payType,
    required this.pay,
    required this.description,
    this.images = const [],
    required this.companyName,
    required this.managerName,
    required this.onSubmit,
    this.onEdit,
  });

  @override
  State<JobPreviewDetailScreen> createState() => _JobPreviewDetailScreenState();
}

class _JobPreviewDetailScreenState extends State<JobPreviewDetailScreen> {
  QualityScore? _quality;
  PayInsight? _payInsight;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  int _parseHours() {
    try {
      // "09:00 ~ 18:00" 또는 "오전 9:00 ~ 오후 6:00" 모두 처리
      final raw = widget.workingTime;

      // 숫자만 추출해서 시간 파싱
      final timeRegex = RegExp(r'(\d{1,2}):(\d{2})');
      final matches = timeRegex.allMatches(raw).toList();

      if (matches.length >= 2) {
        int startH = int.parse(matches[0].group(1)!);
        int endH = int.parse(matches[1].group(1)!);

        // 오후 포함 여부 체크
        if (raw.contains('오후') && endH < 12) endH += 12;

        int diff = endH - startH;
        if (diff <= 0) diff += 24;
        return diff.clamp(1, 24);
      }
    } catch (_) {}
    return 8; // 기본값
  }

  // ── location → 도시 ──
  String _parseCity() {
    try {
      final p = widget.location.trim().split(' ');
      if (p.isNotEmpty) {
        final f = p[0];
        if (f.contains('특별시')) return f.replaceAll('특별시', '');
        if (f.contains('광역시')) return f.replaceAll('광역시', '');
        if (f.endsWith('도') && p.length > 1) return p[1];
        return f;
      }
    } catch (_) {}
    return '';
  }

  Future<void> _loadInsights() async {
    if (widget.category.isEmpty || widget.pay <= 0) return;
    setState(() => _loading = true);

    final hours = _parseHours();
    final city = _parseCity();

    // ── 품질 점수 + 급여 인사이트 병렬 호출 ──
    // _loadInsights() 에서
    final results = await Future.wait([
      JobInsightService.getQualityScore(
        title: widget.title,
        category: widget.category,
        locationCity: city,
        pay: widget.pay,
        hours: hours,
        description: widget.description,
        isPaid: false,
      ),
      JobInsightService.getPayInsight(
        category: widget.category,
        locationCity: city,
        payType: widget.payType,
        hours: hours,
      ),
    ]);
    if (mounted) {
      setState(() {
        _quality = results[0] as QualityScore?;
        _payInsight = results[1] as PayInsight?;
        _loading = false;
      });
    }
  }

  String _periodText() {
    if ((widget.startDate != null && widget.startDate!.trim().isNotEmpty) &&
        (widget.endDate != null && widget.endDate!.trim().isNotEmpty)) {
      DateTime? s, e;
      try {
        s = DateTime.parse(widget.startDate!.trim());
      } catch (_) {}
      try {
        e = DateTime.parse(widget.endDate!.trim());
      } catch (_) {}
      if (s != null && e != null) {
        final fmt = DateFormat('yyyy.MM.dd (E)', 'ko_KR');
        return '${fmt.format(s)} ~ ${fmt.format(e)}';
      }
      return '${widget.startDate} ~ ${widget.endDate}';
    }

    final flatDays =
        widget.weekdays
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .expand((s) => s.contains(',') ? s.split(',') : [s])
            .map((s) => s.trim())
            .toList();

    if (flatDays.isNotEmpty) {
      final first = flatDays.first;
      if (first == '협의') {
        return '요일 협의';
      }
      if (RegExp(r'^협의\s*:').hasMatch(first)) {
        final txt = first.replaceFirst(RegExp(r'^협의\s*:\s*'), '').trim();
        return '요일 협의: ${txt.isEmpty ? '상세 협의' : txt}';
      }
      return flatDays.join(', ');
    }
    return '미정';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: _kBrand,
        title: const Text('공고 미리보기'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.warningBorder),
            ),
            child: const Text(
              '미리보기',
              // Colors.orange는 흰 배경에서 2.15:1 — AA 미달
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.warningDark,
              ),
            ),
          ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // ── 이미지 ──────────────────────────────────────
          if (widget.images.isNotEmpty)
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: widget.images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder:
                    (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        widget.images[i],
                        width: 200,
                        height: 176,
                        fit: BoxFit.cover,
                      ),
                    ),
              ),
            ),

          const SizedBox(height: 12),

          // ── 공고 분석 카드 ──────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _AiInsightCard(
              quality: _quality,
              payInsight: _payInsight,
              loading: _loading,
              pay: widget.pay,
            ),
          ),
          const SizedBox(height: 16),

          // ── 헤더 카드 ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F0FF),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          '내 근처 단기 알바',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _kBrand,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5E8EB),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.category,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Jalnan2TTF',
                            color: _kText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: _kLabel,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.location,
                          style: const TextStyle(fontSize: 13, color: _kLabel),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── 근무 정보 카드 ────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '근무 정보',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _infoRow(
                    Icons.monetization_on,
                    formatJobPay(
                      widget.pay.toString(),
                      widget.payType,
                      includeType: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _infoRow(Icons.calendar_today, _periodText()),
                  const SizedBox(height: 10),
                  _infoRow(Icons.access_time, widget.workingTime),

                  if (widget.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: _kBorder),
                    const SizedBox(height: 14),
                    const Text(
                      '상세 설명',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: _kText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.description.trim(),
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: _kText,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: _kBorder),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.warningBorder),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: AppColors.warningDark,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '공고 설명이 비어 있어요. 등록 전에 작성하는 걸 추천해요.',
                              // Colors.orange는 2.15:1 — AA 미달
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.warningDark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── 지도 ─────────────────────────────────────────
          if (widget.lat != 0 && widget.lng != 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '근무 위치',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 200,
                      child: Stack(
                        children: [
                          FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(widget.lat, widget.lng),
                              initialZoom: 16,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName:
                                    Platform.isAndroid
                                        ? 'kr.co.iljujob'
                                        : 'com.iljujob.kr',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(widget.lat, widget.lng),
                                    width: 40,
                                    height: 40,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.red,
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.92),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.place,
                                    size: 14,
                                    color: _kLabel,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      widget.location,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _kText,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // ── 기업 카드 ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _kBrand.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.business_outlined,
                      color: _kBrand,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.companyName.isNotEmpty
                              ? widget.companyName
                              : '회사명 미입력',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _kText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.managerName.isNotEmpty
                              ? '담당자: ${widget.managerName}'
                              : '담당자 정보 없음',
                          style: const TextStyle(fontSize: 13, color: _kLabel),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── 체크리스트 ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F0FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.checklist_rounded, size: 16, color: _kBrand),
                      SizedBox(width: 6),
                      Text(
                        '등록 전 확인해주세요',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _kBrand,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...[
                    '제목과 업종이 정확한가요?',
                    '급여가 최저시급 이상인가요?',
                    '근무 날짜와 시간이 맞나요?',
                    '근무지 주소가 정확한가요?',
                  ].map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 14,
                            color: _kBrand,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _kBrand,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── 하단 버튼 ─────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onEdit?.call();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: _kBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    foregroundColor: _kText,
                  ),
                  child: const Text(
                    '수정하기',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: widget.onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrand,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '공고 등록하기',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 16, color: _kLabel),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            color: _kText,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}

class _AiInsightCard extends StatefulWidget {
  final QualityScore? quality;
  final PayInsight? payInsight;
  final bool loading;
  final int pay;

  const _AiInsightCard({
    required this.quality,
    required this.payInsight,
    required this.loading,
    required this.pay,
  });

  @override
  State<_AiInsightCard> createState() => _AiInsightCardState();
}

class _AiInsightCardState extends State<_AiInsightCard> {
  bool _tipsExpanded = false;

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      return _kBrand;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');

    // ── 로딩 ──
    if (widget.loading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(_kBrand),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              '공고를 분석하고 있어요…',
              style: TextStyle(fontSize: 13, color: _kLabel),
            ),
          ],
        ),
      );
    }

    if (widget.quality == null) return const SizedBox.shrink();

    final q = widget.quality!;
    final gradeColor = _parseColor(q.gradeColor);
    final pi = widget.payInsight;

    // 급여 위치 계산
    String payPosition = '';
    Color payPosColor = _kLabel;
    if (pi != null && pi.avgHourly > 0) {
      final ratio = widget.pay / pi.avgHourly;
      if (ratio >= 1.2) {
        payPosition = '평균보다 높아요';
        payPosColor = Colors.green.shade600;
      } else if (ratio >= 0.95) {
        payPosition = '평균 수준이에요';
        payPosColor = _kBrand;
      } else {
        payPosition = '평균보다 낮아요';
        payPosColor = Colors.orange.shade700;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더: 품질 점수 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.analytics_outlined, size: 17, color: _kBrand),
                const SizedBox(width: 6),
                const Text(
                  '공고 분석',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _kText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── 점수 + 등급 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: gradeColor.withOpacity(0.1),
                    border: Border.all(
                      color: gradeColor.withOpacity(0.35),
                      width: 2.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${q.score}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: gradeColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.gradeLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: gradeColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: q.score / 100,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFF0F0F0),
                          valueColor: AlwaysStoppedAnimation(gradeColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: _kBorder),

          // ── 3개 인사이트 행 ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // ① 24시간 예상 지원자
                _insightRow(
                  icon: Icons.groups_outlined,
                  label: '24시간 예상 지원자',
                  value: q.predictLabel,
                  valueColor: _kBrand,
                ),
                const SizedBox(height: 12),

                // ② 업종 평균 대비 급여
                if (pi != null && pi.avgHourly > 0) ...[
                  _insightRow(
                    icon: Icons.payments_outlined,
                    label: '업종 평균 시급 ${fmt.format(pi.avgHourly)}원 대비',
                    value: payPosition,
                    valueColor: payPosColor,
                  ),
                  const SizedBox(height: 12),
                ],

                // ③ 유료 등록 시 차이 — 값은 등록방식 시트의 비교표와 반드시 일치해야 함
                //    (즉시게시 = 즉시 노출·상단 고정 없음 / 긴급호출 = 24시간 상단 고정)
                _insightRow(
                  icon: Icons.vertical_align_top_rounded,
                  label: '즉시게시로 등록 시',
                  value: '12시간 대기 없이 즉시 노출',
                  valueColor: _kBrand,
                ),
              ],
            ),
          ),

          // ── 개선 팁 (있을 때만) ──
          if (q.tips.isNotEmpty) ...[
            const Divider(height: 1, color: _kBorder),
            GestureDetector(
              onTap: () => setState(() => _tipsExpanded = !_tipsExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: gradeColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '개선 포인트 ${q.tips.length}개',
                        style: TextStyle(
                          fontSize: 11,
                          color: gradeColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _tipsExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: _kLabel,
                    ),
                  ],
                ),
              ),
            ),

            if (_tipsExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children:
                      q.tips
                          .map(
                            (tip) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color:
                                    tip.impact == 'critical'
                                        ? Colors.red.shade50
                                        : tip.impact == 'high'
                                        ? const Color(0xFFFFF8E1)
                                        : const Color(0xFFF4F6FA),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      tip.impact == 'critical'
                                          ? Colors.red.shade200
                                          : tip.impact == 'high'
                                          ? Colors.orange.shade200
                                          : _kBorder,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    tip.impact == 'critical'
                                        ? Icons.error_outline
                                        : tip.impact == 'high'
                                        ? Icons.info_outline
                                        : Icons.lightbulb_outline,
                                    size: 16,
                                    color:
                                        tip.impact == 'critical'
                                            ? AppColors.error
                                            : tip.impact == 'high'
                                            ? AppColors.warning
                                            : _kBrand,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tip.msg,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _kText,
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
          ],
        ],
      ),
    );
  }

  Widget _insightRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) => Row(
    children: [
      Icon(icon, size: 16, color: _kLabel),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: _kLabel),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: valueColor,
        ),
      ),
    ],
  );
}
