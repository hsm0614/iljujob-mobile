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
  final List<Widget> badges;
  /// 회색 태그(업종 등). 뱃지 뒤에 같은 줄로
  final List<String> tags;
  /// 인증 업체면 첫 줄 앞에 초록 체크 (레퍼런스처럼 '안심기업' 뱃지 대신)
  final bool verified;
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
    this.badges = const [],
    this.tags = const [],
    this.verified = false,
    this.imageUrl,
    this.isBookmarked = false,
    this.isApplied = false,
    this.isPinned = false,
  });

  @override
  Widget build(BuildContext context) {
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
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (verified) ...[
                          const Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: AppColors.badgeSameDay,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(
                            head,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.jobMeta,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.jobTitle,
                    ),
                    if (schedule != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        schedule!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.jobMeta.copyWith(
                          color: AppColors.textSecondary,
                        ),
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
              const SizedBox(width: 12),
              Column(
                children: [
                  _Thumb(imageUrl: imageUrl, size: _thumb),
                  if (onBookmark != null) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: _thumb,
                    height: 30,
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
                          borderRadius: BorderRadius.circular(AppRadius.sm),
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
                  ),
                  ],
                ],
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
    // 파란 바탕 심볼이 목록마다 반복되면 시선이 쏠렸다 → 반전(연회색 바탕 + 파란 심볼).
    // logo_mark(파랑 #1A84FF 바탕·흰 글리프)를 R 채널 기준 선형 매핑:
    // R≈26(바탕) → bgMuted #F2F4F8, R=255(글리프) → primary #3B8AFF
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
