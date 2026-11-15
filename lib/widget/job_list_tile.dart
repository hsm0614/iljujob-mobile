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

  /// 업종(잎 이름). 사진이 없을 때 업종 아이콘 칸의 그림·색을 고른다
  final String category;
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
    this.category = '',
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
      // 누르면 물결 대신 줄 전체가 옅은 회색으로 눌린다 (당근식 목록 반응)
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppColors.bgMuted,
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
                                // 누르면 하트가 톡 튀어나온다 (해제는 그냥 바뀐다)
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 320),
                                  transitionBuilder: (child, a) => ScaleTransition(
                                    scale: child.key == const ValueKey(true)
                                        ? CurvedAnimation(parent: a, curve: Curves.elasticOut)
                                        : a,
                                    child: child,
                                  ),
                                  child: Icon(
                                  key: ValueKey(isBookmarked),
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
                    _Thumb(imageUrl: hasImage ? imageUrl : null, size: _thumb, category: category),
                    if (onApply != null) ...[
                      const SizedBox(height: 6),
                      AppPressScale(
                        haptic: !isApplied,
                        child: SizedBox(
                        width: _thumb,
                        height: 36,
                        child: FilledButton(
                          // 한 화면에 여러 개라 꽉 찬 파랑 대신 연한 파랑 (주 행동 하나 원칙).
                          // 알바생 홈 시안 A(2026-11): 작게·모서리 8·진한 파랑 글자 — 공고 내용보다 튀지 않게
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                            backgroundColor: AppColors.primaryLight,
                            foregroundColor: AppColors.primaryDark,
                            disabledBackgroundColor: AppColors.bgMuted,
                            disabledForegroundColor: AppColors.textSecondary,
                            textStyle: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
                          ),
                          onPressed: isApplied ? null : onApply,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: isApplied
                              ? const Row(
                                  key: ValueKey('applied'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_rounded, size: 14),
                                    SizedBox(width: 2),
                                    Text('지원 완료'),
                                  ],
                                )
                              : const Text('지원하기', key: ValueKey('apply')),
                          ),
                        ),
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
  final String category;
  const _Thumb({required this.imageUrl, required this.size, this.category = ''});
  static const _compact = 56.0;

  /// 사진 없는 공고가 대부분이라 회색 심볼이 줄마다 반복돼 목록이 비어 보였다(2026-11-15 실기기).
  /// 업종별 연한 바탕 + 아이콘으로 — 무슨 일인지 그림으로 먼저 읽힌다. 뱃지가 아니라 Two-Signal과 무관.
  static (IconData, Color, Color) _look(String c) {
    bool has(List<String> ks) => ks.any(c.contains);
    if (has(['홀서빙', '주방', '설거지', '패스트푸드', '요리', '음식'])) {
      return (Icons.restaurant_rounded, const Color(0xFFFFF1E6), const Color(0xFFE07B39));
    }
    if (has(['카페', '바리스타', '베이커리'])) {
      return (Icons.local_cafe_rounded, const Color(0xFFF6EFE8), const Color(0xFF9A6B45));
    }
    if (has(['물류', '택배', '상하차', '배송', '검품', '포장'])) {
      return (Icons.local_shipping_rounded, const Color(0xFFE8F6F1), const Color(0xFF2F9A78));
    }
    if (has(['건설', '제조', '생산', '조립', '반도체', '노무', '청소'])) {
      return (Icons.construction_rounded, const Color(0xFFFFF6DD), const Color(0xFFC08A12));
    }
    if (has(['행사', '진행', '이벤트', '모델', '도우미', '시식', '홍보', '캐릭터'])) {
      return (Icons.celebration_rounded, const Color(0xFFEEF5FF), const Color(0xFF3B8AFF));
    }
    if (has(['편의점', '매장', '판매', '마트'])) {
      return (Icons.storefront_rounded, const Color(0xFFFDEEF2), const Color(0xFFD45C7A));
    }
    if (has(['사무', '데이터', '안내', '접수', '상담'])) {
      return (Icons.badge_rounded, const Color(0xFFEDF1F7), const Color(0xFF5B6B85));
    }
    return (Icons.work_rounded, AppColors.bgMuted, AppColors.textTertiary);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, bg, fg) = _look(category);
    Widget fallback({double? h}) => Container(
      width: size,
      height: h ?? _compact,
      color: bg,
      alignment: Alignment.center,
      child: Icon(icon, size: 26, color: fg),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child:
          imageUrl == null
              ? fallback()
              : Image.network(
                imageUrl!,
                width: size,
                height: size,
                cacheWidth: (size * 3).round(),
                fit: BoxFit.cover,
                // 받아 오는 동안 회색 칸 → 다 받으면 부드럽게 나타난다 (캐시에서 바로 오면 페이드 없음)
                frameBuilder: (_, child, frame, sync) => sync
                    ? child
                    : ColoredBox(
                        color: AppColors.bgMuted,
                        child: AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          child: child,
                        ),
                      ),
                errorBuilder: (_, __, ___) => fallback(h: size),
              ),
    );
  }
}
