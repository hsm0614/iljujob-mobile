import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';

/// 공고 신호 뱃지. 색 의미가 고정돼 있다 (DESIGN.md — The Two-Signal Rule):
///   time  = 시간이 급함 (긴급·마감임박)
///   trust = 검증된 상대 (안심기업)
///   money = 돈이 빨리 들어옴 (당일지급)
///   plain = 분류 (장기 등) — 색 없음
///
/// 화면마다 직접 그리다 보니 상세화면은 `Colors.green`, 목록은 토큰을 쓰는 식으로
/// 갈라졌다. 뱃지를 새로 만들지 말고 이걸 쓴다.
enum JobSignal { time, trust, money, plain }

class JobSignalBadge extends StatelessWidget {
  final String label;
  final JobSignal signal;
  final IconData? icon;

  /// 알약형(상세화면) / 사각형(목록 카드)
  final bool pill;

  const JobSignalBadge({
    super.key,
    required this.label,
    this.signal = JobSignal.plain,
    this.icon,
    this.pill = false,
  });

  Color get _color => switch (signal) {
    JobSignal.time => AppColors.badgeUrgent,
    JobSignal.trust => AppColors.badgeSafe,
    JobSignal.money => AppColors.badgeSameDay,
    JobSignal.plain => AppColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: pill ? 10 : 7,
        vertical: pill ? 4 : 3,
      ),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(
          pill ? AppRadius.full : AppRadius.xs,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: pill ? 14 : 12, color: _color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: _color,
              fontSize: pill ? 12 : 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class AppPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final double height;

  const AppPrimaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.textDisabled,
      elevation: 0,
      textStyle: AppTextStyles.btnLg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    );

    return SizedBox(
      width: double.infinity,
      height: height,
      child:
          icon == null
              ? ElevatedButton(
                onPressed: onPressed,
                style: style,
                child: Text(label),
              )
              : ElevatedButton.icon(
                onPressed: onPressed,
                icon: Icon(icon, size: 18),
                label: Text(label),
                style: style,
              ),
    );
  }
}

class AppActionBand extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;
  final Color accent;

  const AppActionBand({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    this.accent = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.h3.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppTextStyles.body2.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel,
                      style: AppTextStyles.btnSm.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
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

class AppBottomNavItem extends StatelessWidget {
  final bool isActive;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;
  final String? badgeLabel;

  const AppBottomNavItem({
    super.key,
    required this.isActive,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
    this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.all(isActive ? 6 : 0),
                decoration: BoxDecoration(
                  color:
                      isActive
                          ? AppColors.primary.withValues(alpha: 0.10)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      isActive ? activeIcon : icon,
                      size: 21,
                      color:
                          isActive ? AppColors.primary : AppColors.textDisabled,
                    ),
                    if (badgeLabel != null)
                      Positioned(
                        top: -8,
                        right: -10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.badgeNew,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            badgeLabel!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? AppColors.primary : AppColors.textDisabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
