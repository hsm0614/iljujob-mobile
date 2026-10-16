import 'package:flutter/material.dart';

import '../config/app_theme.dart';

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
  final String? imageUrl;
  final bool isBookmarked;
  final bool isApplied;
  /// 지금 상단 고정 중(pinned_until > 지금)일 때만 true. 즉시게시·긴급호출(24시간) 공통
  final bool isPinned;
  final VoidCallback onTap;
  final VoidCallback onBookmark;

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
    required this.onBookmark,
    this.schedule,
    this.badges = const [],
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
                    Text(
                      head,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.jobMeta,
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
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 4, children: badges),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  _Thumb(imageUrl: imageUrl, size: _thumb),
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
    final fallback = Image.asset(
      JobListTile.defaultImage,
      width: size,
      height: size,
      fit: BoxFit.cover,
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
