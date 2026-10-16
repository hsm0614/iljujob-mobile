import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 공고 목록 카드. 회색 배경 위 흰 카드 + 8px 간격으로 공고끼리 경계를 분명히 한다
/// (플랫 줄+구분선은 공고가 서로 붙어 보였다 — 2026-10 대표 피드백).
/// 읽는 순서: 급여 → 제목 → 언제 → 어디. 오른쪽 썸네일(사진 없으면 알바일주 심볼) 위에 찜.
/// 지원 버튼은 없다 — 지원은 상세에서 조건을 본 뒤에 한다.
class JobListTile extends StatelessWidget {
  final String pay;
  final String payType; // 일급·주급 등. 빈 문자열이면 생략
  final bool negotiablePay; // '협의'는 숫자가 아니라 크게 쓰지 않는다
  final String title;
  final String? schedule;
  final String location;
  final String? note; // 매칭 이유 한 줄
  final List<Widget> badges;
  final String? imageUrl;
  final bool isBookmarked;
  final bool isApplied;
  /// 지금 상단 고정 중(pinned_until > 지금)일 때만 true. 즉시게시·긴급호출(24시간) 공통
  final bool isPinned;
  final VoidCallback onTap;
  final VoidCallback onBookmark;

  static const _thumb = 76.0;
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
    this.note,
    this.badges = const [],
    this.imageUrl,
    this.isBookmarked = false,
    this.isApplied = false,
    this.isPinned = false,
  });

  @override
  Widget build(BuildContext context) {
    final tags = <Widget>[
      if (isPinned)
        Text(
          '상단 고정',
          style: AppTextStyles.captionBold.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ...badges,
      if (isApplied)
        Text(
          '지원 완료',
          style: AppTextStyles.captionBold.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tags.isNotEmpty) ...[
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: tags,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              pay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  negotiablePay
                                      ? AppTextStyles.body1.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textSecondary,
                                      )
                                      : AppTextStyles.jobPayHero,
                            ),
                          ),
                          if (payType.isNotEmpty && !negotiablePay) ...[
                            const SizedBox(width: 5),
                            Text(payType, style: AppTextStyles.jobPayUnit),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.jobTitle,
                      ),
                      const SizedBox(height: 6),
                      if (schedule != null)
                        _MetaLine(icon: Icons.schedule_outlined, text: schedule!),
                      _MetaLine(icon: Icons.location_on_outlined, text: location),
                      if (note != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.bgMuted,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            note!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _Thumb(
                  imageUrl: imageUrl,
                  size: _thumb,
                  isBookmarked: isBookmarked,
                  onBookmark: onBookmark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final bool isBookmarked;
  final VoidCallback onBookmark;
  const _Thumb({
    required this.imageUrl,
    required this.size,
    required this.isBookmarked,
    required this.onBookmark,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      JobListTile.defaultImage,
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipRRect(
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
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SizedBox(
              width: 34,
              height: 34,
              child: IconButton(
                tooltip: '찜',
                padding: EdgeInsets.zero,
                onPressed: onBookmark,
                icon: Icon(
                  isBookmarked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 20,
                  color: isBookmarked ? AppColors.badgeNew : Colors.white,
                  shadows: const [
                    Shadow(color: Color(0x40000000), blurRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppColors.textTertiary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.jobMeta.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
