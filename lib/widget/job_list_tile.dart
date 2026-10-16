import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 공고 목록 한 줄. 카드(그림자·라운드) 대신 흰 바탕 + 아래 구분선.
/// 읽는 순서: 급여 → 제목 → 언제 → 어디.
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
  final bool isApplying;
  final VoidCallback onTap;
  final VoidCallback onBookmark;
  final VoidCallback onApply;

  const JobListTile({
    super.key,
    required this.pay,
    required this.payType,
    required this.negotiablePay,
    required this.title,
    required this.location,
    required this.onTap,
    required this.onBookmark,
    required this.onApply,
    this.schedule,
    this.note,
    this.badges = const [],
    this.imageUrl,
    this.isBookmarked = false,
    this.isApplied = false,
    this.isApplying = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgCard,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderSub)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    pay,
                    style: negotiablePay
                        ? AppTextStyles.body1.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          )
                        : AppTextStyles.jobPayHero,
                  ),
                  if (payType.isNotEmpty && !negotiablePay) ...[
                    const SizedBox(width: 5),
                    Text(payType, style: AppTextStyles.jobPayUnit),
                  ],
                  const Spacer(),
                  for (final b in badges)
                    Padding(padding: const EdgeInsets.only(left: 4), child: b),
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
                          _MetaLine(icon: Icons.schedule_outlined, text: schedule!),
                        _MetaLine(icon: Icons.location_on_outlined, text: location),
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
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: note == null
                        ? const SizedBox.shrink()
                        : Text(
                            note!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption,
                          ),
                  ),
                  IconButton(
                    tooltip: '찜',
                    onPressed: onBookmark,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      isBookmarked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 20,
                      color: isBookmarked
                          ? AppColors.badgeNew
                          : AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 34,
                    child: FilledButton(
                      onPressed: isApplied || isApplying ? null : onApply,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.bgMuted,
                        disabledForegroundColor: AppColors.textTertiary,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        textStyle: AppTextStyles.btnMd,
                      ),
                      child: isApplying
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textTertiary,
                              ),
                            )
                          : Text(isApplied ? '지원 완료' : '지원하기'),
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
