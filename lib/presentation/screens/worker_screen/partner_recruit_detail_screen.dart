// 파트너 채용공고 상세 (광고 제휴) — 일반 공고 상세와 렌더가 달라 별도 화면
// 진입점은 아직 미배선 (배너 탭 / 공고목록 상단 카드 등 결정 후 연결)
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_theme.dart';
import '../../../data/models/partner_recruit_post.dart';
import '../../../data/services/ad_banner_service.dart';

class PartnerRecruitDetailScreen extends StatefulWidget {
  final PartnerRecruitPost post;

  /// CTA 로그에 남길 유입 지면 (미지정 시 app_partner_recruit)
  final String? placement;

  const PartnerRecruitDetailScreen({
    super.key,
    required this.post,
    this.placement,
  });

  @override
  State<PartnerRecruitDetailScreen> createState() =>
      _PartnerRecruitDetailScreenState();
}

class _PartnerRecruitDetailScreenState
    extends State<PartnerRecruitDetailScreen> {
  bool _applying = false;

  // 요약부는 상세 본문(14)보다 1pt 작게
  static const double _bodyFontSize = 14;
  static const double _summaryFontSize = 13;

  Future<void> _onApply() async {
    if (_applying) return;
    setState(() => _applying = true);

    final uri = Uri.tryParse(widget.post.applyUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      _snack('지원 페이지 주소가 올바르지 않습니다.');
      setState(() => _applying = false);
      return;
    }

    // 정산 대사 근거 — 외부 링크를 열기 전에 기록 (실패해도 이동은 진행)
    await AdBannerService.instance.logPartnerCta(
      widget.post.partnerCode,
      placement: widget.placement,
    );

    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}

    if (!mounted) return;
    if (!launched) _snack('지원 페이지를 열 수 없습니다.');
    setState(() => _applying = false);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AppBar(
        title: const Text('채용공고'),
        backgroundColor: AppColors.bgCard,
        elevation: 0,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _titleBlock(post),
            const SizedBox(height: 16),
            _summaryCard(post),
            const SizedBox(height: 12),
            ...post.sections.map(_sectionCard),
            _benefitsCard(post.benefits),
          ],
        ),
      ),
      bottomNavigationBar: _applyBar(post),
    );
  }

  // ── 타이틀 (형광펜 하이라이트) ─────────────────────────────
  Widget _titleBlock(PartnerRecruitPost post) {
    const style = TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      height: 1.35,
    );

    if (!post.highlightTitle) return Text(post.title, style: style);

    // 텍스트 하단 45%에만 깔리는 형광펜 느낌 (배경 바 → 텍스트 순서)
    return Stack(
      children: [
        Positioned.fill(
          child: FractionallySizedBox(
            alignment: Alignment.bottomLeft,
            heightFactor: 0.45,
            child: Container(color: AppColors.primaryMid),
          ),
        ),
        Text(post.title, style: style),
      ],
    );
  }

  // ── 요약부 (상세보다 1pt 작게) ────────────────────────────
  Widget _summaryCard(PartnerRecruitPost post) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in post.summary)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: _summaryFontSize,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.value,
                      style: const TextStyle(
                        fontSize: _summaryFontSize,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 본문 섹션 ────────────────────────────────────────────
  Widget _sectionCard(PartnerRecruitSection section) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(section.heading),
          const SizedBox(height: 10),
          ...section.body.map(_line),
          if (section.highlightLine != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.highlightLine!,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                  if (section.highlightBody.isNotEmpty) const SizedBox(height: 8),
                  ...section.highlightBody.map(_line),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 혜택부 (알바일주 + 원더 로고 / 상품권은 텍스트만) ────────
  Widget _benefitsCard(PartnerRecruitBenefits benefits) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.primaryMid),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _logoLockup(benefits.logos),
          const SizedBox(height: 14),
          _heading(benefits.heading),
          const SizedBox(height: 12),
          for (final item in benefits.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ${item.title}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...item.details.map(_line),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 로고 슬롯. 파트너 로고는 파트너 제공 자산만 쓴다(임의 제작 금지).
  /// 자산이 없는 키는 회색 자리표시자로 둔다.
  /// 실제로 번들에 들어 있는 것만 적는다. 없는 경로를 적어두면
  /// errorBuilder로 늦게 떨어져 자리표시자가 한 프레임 늦게 뜬다.
  /// 원더 로고 = 원더 제공 자산('앱 logo 남색_텍스트조합'). 임의 제작·변형 금지.
  static const _logoAssets = {
    'albailju': 'assets/images/logo_mark.png',
    'wonder': 'assets/images/wonder_logo.png',
  };

  static const _logoLabels = {'albailju': '알바일주', 'wonder': 'wonder'};

  /// 제휴 락업 — 로고 사이에 ×를 두어 "함께한다"를 시각적으로 말한다.
  /// (NAVER CLOVA × COMPANY LOGO 형태)
  Widget _logoLockup(List<String> logos) {
    final items = <Widget>[];
    for (var i = 0; i < logos.length; i++) {
      if (i > 0) {
        items.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ),
        );
      }
      items.add(_logo(logos[i]));
    }

    return Center(
      child: Row(mainAxisSize: MainAxisSize.min, children: items),
    );
  }

  Widget _logo(String key) {
    final asset = _logoAssets[key];
    if (asset == null) return _logoFallback(key);

    // 심볼형 로고는 앱 아이콘처럼 모서리를 둥글게 잘라 락업 안에서 정돈되게
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Image.asset(
        asset,
        height: 34,
        width: 34,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _logoFallback(key),
      ),
    );
  }

  Widget _logoFallback(String key) {
    return Container(
      height: 34,
      constraints: const BoxConstraints(minWidth: 80),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.bgMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        _logoLabels[key] ?? key,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textTertiary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _heading(String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        margin: const EdgeInsets.only(top: 5, right: 8),
        width: 3,
        height: 14,
        color: AppColors.primary,
      ),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.35,
          ),
        ),
      ),
    ],
  );

  Widget _line(PartnerRecruitLine line) {
    switch (line.kind) {
      case PartnerLineKind.bold:
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            line.text,
            style: const TextStyle(
              fontSize: _bodyFontSize + 1,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
        );
      case PartnerLineKind.bullet:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 7, right: 8),
                child: SizedBox(
                  width: 4,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Expanded(child: Text(line.text, style: _bodyStyle)),
            ],
          ),
        );
      case PartnerLineKind.text:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(line.text, style: _bodyStyle),
        );
    }
  }

  static const _bodyStyle = TextStyle(
    fontSize: _bodyFontSize,
    color: AppColors.textSecondary,
    height: 1.6,
  );

  // ── 하단 고정 지원하기 ────────────────────────────────────
  Widget _applyBar(PartnerRecruitPost post) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        boxShadow: AppShadows.bottomNav,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _applying ? null : _onApply,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withValues(
                  alpha: 0.5,
                ),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: _applying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(post.applyLabel, style: AppTextStyles.btnLg),
            ),
          ),
        ),
      ),
    );
  }
}
