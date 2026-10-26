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
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
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
                    Text(
                      head,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.jobMeta,
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
                                negotiablePay
                                    ? AppTextStyles.body1.copyWith(
                                      fontWeight: FontWeight.w700,
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
              // 오른쪽 칸은 모든 공고가 같다 (사진 있든 없든) — 사진 + 모서리 하트 + 지원하기
              const SizedBox(width: 12),
              SizedBox(
                width: _thumb,
                child: Column(
                  children: [
                    Stack(
                      children: [
                        _Thumb(
                          imageUrl: hasImage ? imageUrl : null,
                          size: _thumb,
                        ),
                        if (onBookmark != null)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onBookmark,
                              child: Padding(
                                // 보이는 원 28, 터치 영역 44
                                padding: const EdgeInsets.all(8),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: const BoxDecoration(
                                    color: Color(0xE6FFFFFF),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isBookmarked
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    size: 17,
                                    color:
                                        isBookmarked
                                            ? AppColors.badgeNew
                                            : AppColors.textSecondary,
                                    semanticLabel:
                                        isBookmarked ? '관심 공고 해제' : '관심 공고 추가',
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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

  @override
  Widget build(BuildContext context) {
    // 사진이 없으면 알바일주 심볼 (대표 결정). 파란 바탕이 반복되면 시선이 쏠려
    // 반전(연회색 바탕 + 파란 심볼): logo_mark R 채널 기준 선형 매핑
    final fallback = ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        -0.799, 0, 0, 0, 262.8, //
        -0.463, 0, 0, 0, 256.0, //
        0.031, 0, 0, 0, 247.2, //
        0, 0, 0, 1, 0,
      ]),
      child: Image.asset(
        JobListTile.defaultImage,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child:
          imageUrl == null
              ? fallback
              : Image.network(
                imageUrl!,
                width: size,
                height: size,
                cacheWidth: (size * 3).round(),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
    );
  }
}
