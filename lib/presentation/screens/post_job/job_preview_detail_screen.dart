import 'dart:io';
import 'package:iljujob/widget/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/data/services/job_insight_service.dart';
import 'package:iljujob/utils/pay_display.dart';

// textTertiary(#9CA3AF)는 AppColors.bgPage 위 2.35:1로 WCAG AA 미달이라 승격.

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
        // 하루짜리 공고에 '8/3 ~ 8/3'은 같은 날짜를 두 번 읽게 만든다.
        if (s.year == e.year && s.month == e.month && s.day == e.day) {
          return fmt.format(s);
        }
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

  // 알바생이 보는 공고 상세와 같은 뼈대 (2026-10). 예전엔 테두리 카드 다섯 장·잘난체 제목·
  // 가짜 '내 근처 단기 알바' 칩·주황 '미리보기' 알약·파란 체크리스트 상자가 있었고,
  // 아래 '공고 등록하기'는 실제로는 등록하지 않고 닫기만 했다.
  @override
  Widget build(BuildContext context) {
    final negotiable = isNegotiablePayType(widget.payType);
    Widget section(Widget child) => Container(
      width: double.infinity,
      color: AppColors.bgCard,
      padding: const EdgeInsets.all(20),
      child: child,
    );

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AppBar(title: const Text('알바생에게 이렇게 보여요')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (widget.images.isNotEmpty)
            Container(
              color: AppColors.bgCard,
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                itemCount: widget.images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder:
                    (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.file(widget.images[i], width: 200, height: 176, fit: BoxFit.cover),
                    ),
              ),
            ),
          section(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.category.trim().isNotEmpty) ...[
                  JobSignalBadge(label: widget.category),
                  const SizedBox(height: 10),
                ],
                if (widget.companyName.isNotEmpty) ...[
                  Text(widget.companyName, style: AppTextStyles.body2),
                  const SizedBox(height: 4),
                ],
                Text(widget.title, style: AppTextStyles.h2),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formatJobPay(widget.pay.toString(), widget.payType),
                      style:
                          negotiable
                              ? AppTextStyles.h3.copyWith(color: AppColors.textSecondary)
                              : AppTextStyles.jobPayDisplay,
                    ),
                    if (!negotiable && widget.payType.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(widget.payType, style: AppTextStyles.jobPayUnit),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 14),
                _infoRow(Icons.calendar_today_outlined, _periodText()),
                const SizedBox(height: 10),
                _infoRow(Icons.schedule_outlined, widget.workingTime),
                const SizedBox(height: 10),
                _infoRow(Icons.place_outlined, widget.location),
              ],
            ),
          ),
          const SizedBox(height: 8),
          section(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('상세 설명', style: AppTextStyles.h3),
                const SizedBox(height: 8),
                Text(
                  widget.description.trim().isEmpty
                      ? '설명이 비어 있어요 · 하는 일과 준비물을 쓰면 지원이 늘어요'
                      : widget.description.trim(),
                  style:
                      widget.description.trim().isEmpty
                          ? AppTextStyles.body2
                          : AppTextStyles.body1.copyWith(color: AppColors.textPrimary, height: 1.6),
                ),
              ],
            ),
          ),
          if (_loading || _quality != null) ...[
            const SizedBox(height: 8),
            Container(
              color: AppColors.bgCard,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _AiInsightCard(
                quality: _quality,
                payInsight: _payInsight,
                loading: _loading,
                pay: widget.pay,
                payType: widget.payType,
              ),
            ),
          ],
          if (widget.lat != 0 && widget.lng != 0) ...[
            const SizedBox(height: 8),
            section(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('근무 위치', style: AppTextStyles.h3),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: SizedBox(
                      height: 160,
                      child: FlutterMap(
                        options: MapOptions(initialCenter: LatLng(widget.lat, widget.lng), initialZoom: 16),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: Platform.isAndroid ? 'kr.co.iljujob' : 'com.iljujob.kr',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(widget.lat, widget.lng),
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.location_on, color: AppColors.primary, size: 40),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: AppBottomBar(
        child: AppPrimaryButton(label: '확인했어요', onPressed: widget.onSubmit),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppColors.textSecondary),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: AppTextStyles.body1.copyWith(color: AppColors.textPrimary))),
    ],
  );
}

class _AiInsightCard extends StatefulWidget {
  final QualityScore? quality;
  final PayInsight? payInsight;
  final bool loading;
  final int pay;
  final String payType;

  const _AiInsightCard({
    required this.quality,
    required this.payInsight,
    required this.loading,
    required this.pay,
    required this.payType,
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
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');

    // ── 로딩 ──
    if (widget.loading) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: AppColors.bgCard,
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              '공고를 분석하고 있어요…',
              style: TextStyle(fontSize: AppFontSize.body2, color: AppColors.textSecondary),
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
    Color payPosColor = AppColors.textSecondary;
    // 평균 '시급'과 비교하므로 시급 공고만 — 일급 12만원이 늘 '평균보다 높아요'로 나왔다
    if (pi != null && pi.avgHourly > 0 && widget.payType == '시급') {
      final ratio = widget.pay / pi.avgHourly;
      if (ratio >= 1.2) {
        payPosition = '평균보다 높아요';
        payPosColor = AppColors.badgeSameDay;
      } else if (ratio >= 0.95) {
        payPosition = '평균 수준이에요';
        payPosColor = AppColors.primary;
      } else {
        payPosition = '평균보다 낮아요';
        payPosColor = AppColors.warningDark;
      }
    }

    // 흰 섹션 안에 들어가므로 자기 테두리 상자는 없앴다(상자 속 상자)
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더: 품질 점수 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.analytics_outlined, size: 17, color: AppColors.primary),
                const SizedBox(width: 6),
                const Text(
                  '공고 분석',
                  style: TextStyle(
                    fontSize: AppFontSize.button,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
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
                        fontSize: AppFontSize.h2,
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
                          fontSize: AppFontSize.body1,
                          fontWeight: FontWeight.w700,
                          color: gradeColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.full),
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
          const Divider(height: 1, color: AppColors.border),

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
                  valueColor: AppColors.primary,
                ),
                const SizedBox(height: 12),

                // ② 업종 평균 대비 급여
                if (payPosition.isNotEmpty) ...[
                  _insightRow(
                    icon: Icons.payments_outlined,
                    label: '업종 평균 시급 ${fmt.format(pi!.avgHourly)}원 대비',
                    value: payPosition,
                    valueColor: payPosColor,
                  ),
                  const SizedBox(height: 12),
                ],

                // ③ 유료 등록 시 차이 — 값은 등록방식 시트의 비교표와 반드시 일치해야 함
                //    (즉시게시 = 7일 노출·상단 고정 없음 / 긴급호출 = 24시간 상단 고정)
                _insightRow(
                  icon: Icons.vertical_align_top_rounded,
                  label: '즉시게시로 등록 시',
                  value: '12시간 기다리지 않고 즉시 공개 · 알림 2회',
                  valueColor: AppColors.primary,
                ),
              ],
            ),
          ),

          // ── 개선 팁 (있을 때만) ──
          if (q.tips.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.border),
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
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        '개선 포인트 ${q.tips.length}개',
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
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
                      color: AppColors.textSecondary,
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
                                        ? AppColors.errorLight
                                        : tip.impact == 'high'
                                        ? const Color(0xFFFFF8E1)
                                        : AppColors.bgPage,
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                border: Border.all(
                                  color:
                                      tip.impact == 'critical'
                                          ? AppColors.errorBorder
                                          : tip.impact == 'high'
                                          ? AppColors.warningBorder
                                          : AppColors.border,
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
                                            : AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tip.msg,
                                      style: const TextStyle(
                                        fontSize: AppFontSize.meta,
                                        color: AppColors.textPrimary,
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
      Icon(icon, size: 16, color: AppColors.textSecondary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: AppFontSize.meta, color: AppColors.textSecondary),
        ),
      ),
      // 12px 값 텍스트라 3:1(UI 컴포넌트)이 아니라 4.5:1이 기준이다.
      // AppColors.primary(#3B8AFF)는 흰 배경에서 3.35:1이므로 진한 파랑으로 대체한다.
      Text(
        value,
        style: TextStyle(
          fontSize: AppFontSize.meta,
          fontWeight: FontWeight.w700,
          color: valueColor == AppColors.primary ? AppColors.primaryDark : valueColor,
        ),
      ),
    ],
  );
}
