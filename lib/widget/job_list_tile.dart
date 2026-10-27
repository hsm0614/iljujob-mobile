import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'app_ui.dart';

/// 공고 목록 한 줄 (2026-10 대표 레퍼런스: 흰 줄 + 구분선, 오른쪽 사진 + 아래 관심 버튼).
/// 읽는 순서: 어디 → 제목 → 언제 → 급여 → 태그. 지원은 상세에서.
class JobListTile extends StatelessWidget {
  final String pay;
  final String payType; // 일급·주급 등. 빈 문자열이면 생략
  final bool negotiablePay; // '협의'는 숫자가 아니라 크게 쓰지 않는다
  final String title;
  final String? schedule;
  final String location;

  /// 목록 마지막 줄이면 false — 마지막 항목 뒤엔 구분선을 긋지 않는다
  final bool divider;
  final List<Widget> badges;

  /// 회색 태그(업종 등). 뱃지 뒤에 같은 줄로
  final List<String> tags;

  final String? imageUrl;
  final bool isBookmarked;
  final bool isApplied;

  /// 지금 상단 고정 중(pinned_until > 지금)일 때만 true. 즉시게시·긴급호출(24시간) 공통
  final bool isPinned;
  final VoidCallback onTap;

  /// null이면 '관심' 버튼을 숨긴다 (최근 본 공고 등)
  final VoidCallback? onBookmark;

  /// 목록의 '지원하기'. null이면 버튼 없음(최근 본 공고 등). 지원 완료면 비활성
  final VoidCallback? onApply;

  static const _thumb = 80.0;
  static const defaultImage = 'assets/images/logo_mark.png';

  const JobListTile({
    super.key,
    required this.pay,
    required this.payType,
    required this.negotiablePay,
    required this.title,
    required this.location,
    required this.onTap,
    this.onBookmark,
    this.onApply,
    this.schedule,
    this.divider = true,
    this.badges = const [],
    this.tags = const [],
    this.imageUrl,
    this.isBookmarked = false,
    this.isApplied = false,
    this.isPinned = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final head = [
      if (isPinned) '상단 고정',
      location,
      if (isApplied) '지원 완료',
    ].join(' · ');

    return Material(
      color: AppColors.bgCard,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          decoration: BoxDecoration(
            border:
                divider
                    ? const Border(bottom: BorderSide(color: AppColors.border))
                    : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 첫 줄 끝에 하트 — 사진 위에 얹으면 기본 이미지와 겹쳐 보였다
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            head,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.jobMeta,
                          ),
                        ),
                        if (onBookmark != null)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onBookmark,
                            child: SizedBox(
                              width: 40,
                              height: 28,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Icon(
                                  isBookmarked
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 20,
                                  color:
                                      isBookmarked
                                          ? AppColors.badgeNew
                                          : AppColors.textTertiary,
                                  semanticLabel:
                                      isBookmarked ? '관심 공고 해제' : '관심 공고 추가',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2, // 긴 제목의 핵심 직무가 '월37…' 뒤로 숨던 것
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.jobTitle,
                    ),
                    if (schedule != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        schedule!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.jobMeta,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: pay,
                            style:
                                // '협의'는 정보가 없는데 급여 자리를 크게 차지했다 → 작은 회색 한 줄
                                negotiablePay
                                    ? AppTextStyles.body2.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    )
                                    : AppTextStyles.jobPayHero,
                          ),
                          if (payType.isNotEmpty && !negotiablePay)
                            TextSpan(
                              text: ' $payType',
                              style: AppTextStyles.jobPayUnit,
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (badges.isNotEmpty || tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ...badges,
                          for (final t in tags) JobSignalBadge(label: t),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // 오른쪽 칸 폭은 모든 공고가 같다 — 사진(없으면 낮은 띠) + 지원하기
              const SizedBox(width: 12),
              SizedBox(
                width: _thumb,
                child: Column(
                  children: [
                    _Thumb(imageUrl: hasImage ? imageUrl : null, size: _thumb),
                    if (onApply != null) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: _thumb,
                        height: 40,
                        child: FilledButton(
                          // 한 화면에 여러 개라 꽉 찬 파랑 대신 연한 파랑 (주 행동 하나 원칙)
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: AppColors.primaryLight,
                            foregroundColor: AppColors.primary,
                            disabledBackgroundColor: AppColors.bgMuted,
                            disabledForegroundColor: AppColors.textTertiary,
                            textStyle: AppTextStyles.btnSm,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                          ),
                          onPressed: isApplied ? null : onApply,
                          child: Text(isApplied ? '지원 완료' : '지원하기'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? imageUrl;
  final double size;
  const _Thumb({required this.imageUrl, required this.size});
  static const _compact = 48.0;

  @override
  Widget build(BuildContext context) {
    // 사진이 없으면 알바일주 심볼 (대표 결정). 파란 심볼도 반복되면 시선이 쏠려
    // 회색 톤(바탕 #F2F4F6 + 심볼 #B0B8C1): logo_mark R 채널(바탕 26 · 심볼 255) 선형 매핑
    final fallback = ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        -0.288, 0, 0, 0, 249.5, //
        -0.262, 0, 0, 0, 250.8, //
        -0.231, 0, 0, 0, 252.0, //
        0, 0, 0, 1, 0,
      ]),
      child: Image.asset(JobListTile.defaultImage, height: _compact),
    );
    // 사진 없는 기업이 대부분이라 정사각 심볼이 줄 높이를 다 먹었다 —
    // 없으면 낮은 띠(폭 그대로, 높이 48)로 줄여 한 화면에 공고가 더 보이게
    final placeholder = Container(
      width: size,
      height: _compact,
      color: AppColors.bgMuted,
      alignment: Alignment.center,
      child: fallback,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child:
          imageUrl == null
              ? placeholder
              : Image.network(
                imageUrl!,
                width: size,
                height: size,
                cacheWidth: (size * 3).round(),
                fit: BoxFit.cover,
                errorBuilder:
                    (_, __, ___) => SizedBox(
                      width: size,
                      height: size,
                      child: ColoredBox(
                        color: AppColors.bgMuted,
                        child: Center(child: fallback),
                      ),
                    ),
              ),
    );
  }
}
