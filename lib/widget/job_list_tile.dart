import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 공고 목록 한 줄. 카드(그림자·라운드) 대신 흰 바탕 + 아래 구분선.
/// 읽는 순서: 급여 → 제목 → 언제 → 어디.
/// 지원 버튼은 없다 — 지원은 상세에서 조건을 본 뒤에 한다(급구와 같은 흐름).
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
    return Material(
      color: AppColors.bgCard,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderSub)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPinned)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '상단 고정',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              // 급여 줄 오른쪽 끝에 뱃지·하트를 모아 오른쪽 가장자리를 한 줄로 맞춘다
              Row(
                children: [
                  Expanded(
                    child: Row(
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
                  ),
                  if (isApplied)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        '지원 완료',
                        style: AppTextStyles.captionBold.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  for (final b in badges)
                    Padding(padding: const EdgeInsets.only(left: 4), child: b),
                  SizedBox(
                    width: 40,
                    height: 36,
                    child: IconButton(
                      tooltip: '찜',
                      onPressed: onBookmark,
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        isBookmarked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 20,
                        color:
                            isBookmarked
                                ? AppColors.badgeNew
                                : AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.jobTitle,
                        ),
                        const SizedBox(height: 4),
                        if (schedule != null)
                          _MetaLine(
                            icon: Icons.schedule_outlined,
                            text: schedule!,
                          ),
                        _MetaLine(
                          icon: Icons.location_on_outlined,
                          text: location,
                        ),
                        if (note != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            note!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (imageUrl != null) ...[
                    const SizedBox(width: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.network(
                        imageUrl!,
                        width: 60,
                        height: 60,
                        cacheWidth: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                  const SizedBox(width: 12),
                ],
              ),
            ],
          ),
        ),
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
