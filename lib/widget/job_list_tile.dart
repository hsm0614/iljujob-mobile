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
              if (hasImage || onBookmark != null) ...[
                const SizedBox(width: 12),
                Column(
                  children: [
                    if (hasImage) _Thumb(imageUrl: imageUrl!, size: _thumb),
                    if (onBookmark != null) ...[
                      if (hasImage) const SizedBox(height: 6),
                      if (hasImage)
                        SizedBox(
                          width: _thumb,
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: onBookmark,
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              foregroundColor:
                                  isBookmarked
                                      ? AppColors.badgeNew
                                      : AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.border),
                              textStyle: AppTextStyles.captionBold,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                            ),
                            icon: Icon(
                              isBookmarked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 14,
                            ),
                            label: const Text('관심'),
                          ),
                        )
                      else
                        IconButton(
                          tooltip: isBookmarked ? '관심 공고 해제' : '관심 공고 추가',
                          onPressed: onBookmark,
                          color:
                              isBookmarked
                                  ? AppColors.badgeNew
                                  : AppColors.textSecondary,
                          icon: Icon(
                            isBookmarked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                          ),
                        ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String imageUrl;
  final double size;
  const _Thumb({required this.imageUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: AppColors.bgMuted,
      child: const Icon(
        Icons.work_outline_rounded,
        color: AppColors.textTertiary,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        cacheWidth: (size * 3).round(),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
