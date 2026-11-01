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

// 점수·등급은 뺐다(2026-11, 대표) — 숫자 하나로 공고를 채점하면 고칠 거리보다 불안을 준다.
// 쓸모 있는 것(평균 대비 급여·고칠 점)만 문장으로.
class _AiInsightCardState extends State<_AiInsightCard> {
  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');

    if (widget.loading) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: AppColors.bgCard,
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppColors.primary)),
            ),
            SizedBox(width: 12),
            Text('공고를 살펴보고 있어요…', style: AppTextStyles.body2),
          ],
        ),
      );
    }

    final q = widget.quality;
    final pi = widget.payInsight;
    final notes = <String>[
      // 평균 '시급'과 비교하므로 시급 공고만 — 일급 12만원이 늘 '평균보다 높아요'로 나왔다
      if (pi != null && pi.avgHourly > 0 && widget.payType == '시급')
        switch (widget.pay / pi.avgHourly) {
          >= 1.2 => '업종 평균 시급 ${fmt.format(pi.avgHourly)}원보다 높아요',
          >= 0.95 => '업종 평균 시급 ${fmt.format(pi.avgHourly)}원과 비슷해요',
          _ => '업종 평균 시급 ${fmt.format(pi.avgHourly)}원보다 낮아요',
        },
      ...?q?.tips.map((t) => t.msg),
    ];
    if (notes.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.bgMuted, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('올리기 전에 참고하세요',
              style: AppTextStyles.body1.copyWith(fontSize: AppFontSize.button, fontWeight: FontWeight.w700)),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•', style: AppTextStyles.body1.copyWith(fontSize: AppFontSize.button, color: AppColors.primary)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(n, style: AppTextStyles.body1.copyWith(fontSize: AppFontSize.button))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
