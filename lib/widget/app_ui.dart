import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              fontSize: pill ? AppFontSize.meta : AppFontSize.caption,
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

    final button = SizedBox(
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
    return onPressed == null ? button : AppPressScale(child: button);
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
                        fontSize: AppFontSize.body1,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppTextStyles.body2.copyWith(
                        fontSize: AppFontSize.meta,
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
                          isActive
                              ? AppColors.primary
                              : AppColors.textSecondary,
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
                              fontSize: AppFontSize.caption,
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
                  fontSize: AppFontSize.caption,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 빈 화면 공용 (2026-10). 아이콘 → 제목 → 한 줄 설명 → 버튼 **최대 1개**.
/// 빈 화면에서 할 수 있는 다음 행동은 하나여야 한다(급구 참고). 버튼이 없으면 설명만.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 새로고침·다시 시도처럼 보조 행동이면 테두리 버튼
  final bool secondaryAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryAction = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.bgMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: AppTextStyles.h3),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTextStyles.body2,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                height: 44,
                child:
                    secondaryAction
                        ? OutlinedButton(
                          onPressed: onAction,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          child: Text(actionLabel!),
                        )
                        : FilledButton(
                          onPressed: onAction,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            textStyle: AppTextStyles.btnMd,
                          ),
                          child: Text(actionLabel!),
                        ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 확인·안내용 바텀시트 (가운데 AlertDialog 대신 — DESIGN.md 바텀시트 원칙).
/// [cancelLabel] 이 없으면 버튼 하나짜리 안내. 확인을 누르면 true.
/// 되돌릴 수 없는 경고(노쇼·차단·지원 취소)와 이미지 미리보기는 예외로 팝업을 쓴다.
Future<bool> showAppSheet(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = '확인',
  String? cancelLabel,
  bool destructive = false,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    builder:
        (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: AppTextStyles.h2),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: AppTextStyles.body1.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (cancelLabel != null) ...[
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.bgMuted,
                              foregroundColor: AppColors.textPrimary,
                            ),
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(cancelLabel),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: AppPressScale(
                        child: SizedBox(
                        height: 52,
                        child: FilledButton(
                          style:
                              destructive
                                  ? FilledButton.styleFrom(
                                    backgroundColor: AppColors.error,
                                  )
                                  : null,
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(confirmLabel),
                        ),
                      ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
  );
  return ok == true;
}

/// 설정·메뉴 묶음 (2026-10 마이 리디자인, 토스·당근 설정 화면 참고).
/// 화면 폭 가득 흰 블록 + 작은 회색 머리글. 블록 사이 간격은 바탕(bgPage)이 만든다.
class AppMenuSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const AppMenuSection({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                title!,
                style: AppTextStyles.captionBold.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: AppFontSize.body2,
                ),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

/// 메뉴 한 줄. 아이콘은 회색 — 파랑은 누를 수 있는 '버튼'에만 (DESIGN.md CTA Blue).
/// [trailing]이 없으면 오른쪽 화살표, [value]가 있으면 화살표 앞에 회색 값.
class AppMenuRow extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  const AppMenuRow({
    super.key,
    this.icon,
    required this.label,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: AppColors.textSecondary),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: AppTextStyles.body1),
                    if (subtitle != null)
                      Text(subtitle!, style: AppTextStyles.body2),
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 8),
                Text(value!, style: AppTextStyles.body2),
              ],
              trailing ??
                  (onTap == null
                      ? const SizedBox.shrink()
                      : const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: AppColors.textTertiary,
                        ),
                      )),
            ],
          ),
        ),
      ),
    );
  }
}

/// 목록 로딩 자리표시 (2026-10, 토스식 회색 줄). 가운데 빙글이 대신 — 무엇이 올지 모양을 먼저 보여준다.
/// [avatar]: 채팅처럼 왼쪽 동그라미가 있는 목록. 천천히 밝아졌다 어두워진다(0.9초).
class AppSkeletonList extends StatefulWidget {
  final int rows;
  final bool avatar;
  const AppSkeletonList({super.key, this.rows = 6, this.avatar = false});

  @override
  State<AppSkeletonList> createState() => _AppSkeletonListState();
}

class _AppSkeletonListState extends State<AppSkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _bar(double? w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: AppColors.bgMuted,
      borderRadius: BorderRadius.circular(AppRadius.xs),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.45).animate(_c),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: widget.rows,
        itemBuilder:
            (_, i) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.avatar) ...[
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: AppColors.bgMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _bar(i.isEven ? 120 : 90, 12),
                        const SizedBox(height: 8),
                        _bar(double.infinity, 16),
                        const SizedBox(height: 8),
                        _bar(i.isEven ? 160 : 200, 12),
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

/// 누르는 동안 살짝 작아지는 반응 (2026-10, 토스식). 손가락이 닿는 순간 반응해 '눌렸다'가 바로 느껴진다.
/// 제스처를 가로채지 않는다(Listener) — 안쪽 InkWell·버튼은 그대로 동작한다.
class AppPressScale extends StatefulWidget {
  final Widget child;
  final double scale;

  /// 닿는 순간 가벼운 진동. 주요 버튼만 (목록 줄마다 울리면 시끄럽다)
  final bool haptic;
  const AppPressScale({
    super.key,
    required this.child,
    this.scale = 0.97,
    this.haptic = true,
  });

  @override
  State<AppPressScale> createState() => _AppPressScaleState();
}

class _AppPressScaleState extends State<AppPressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        _set(true);
        if (widget.haptic) HapticFeedback.selectionClick();
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// 마이 상단 프로필 줄 (알바생·사장님 공용). 누르면 프로필 수정.
class AppProfileHeader extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String subtitle;
  final IconData fallbackIcon;
  final bool loading;
  final VoidCallback onTap;

  const AppProfileHeader({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    this.fallbackIcon = Icons.person_rounded,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImg = !loading && imageUrl.isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.bgMuted,
              backgroundImage: hasImg ? NetworkImage(imageUrl) : null,
              child:
                  hasImg
                      ? null
                      : Icon(
                        fallbackIcon,
                        size: 32,
                        color: AppColors.textDisabled,
                      ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.h3,
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body2),
                ],
              ),
            ),
            Text(
              '프로필 수정',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 이번 달 근무 금액 (2026-10): 같은 크기 두 칸 → 큰 숫자 하나(토스식 '화면의 포인트')
/// + 예정 한 줄. 입금 확인 데이터가 아니라 근무 기록 합계라 '정산'이라 부르지 않는다.
/// 같은 숫자가 캘린더에 월별로 있어 누르면 캘린더로

/// 마이 맨 아래 사업자 정보 (전자상거래법 표시, 알바생·사장님 공용)
class AppBizInfoRow extends StatefulWidget {
  const AppBizInfoRow({super.key});

  @override
  State<AppBizInfoRow> createState() => AppBizInfoRowState();
}

class AppBizInfoRowState extends State<AppBizInfoRow> {
  bool _open = false;

  static const _items = [
    ('법인명', '주식회사 찾다'),
    ('대표자', '황성민'),
    ('사업자등록번호', '480-88-03690'),
    ('법인등록번호', '120111-0146420'),
    ('통신판매업 번호', '2025-인천연수구-2179호'),
    ('이메일', 'hsm@outfind.co.kr'),
    ('고객센터', '070-4792-3001 / 010-4653-3002'),
    ('개업연월일', '2025년 05월 26일'),
    ('사업장 소재지', '인천광역시 연수구 하모니로178번길 22, 7층 707-나60호 (송도동)'),
    ('본점 소재지', '인천광역시 연수구 하모니로178번길 22, 7층 707-나60호 (송도동)'),
    ('업태', '정보통신업'),
    ('종목', '데이터베이스 및 온라인 정보제공업, 온라인활용마케팅 및 관련사업지원서비스'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppMenuRow(
          label: '사업자 정보',
          onTap: () => setState(() => _open = !_open),
          trailing: Icon(
            _open
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: AppColors.textTertiary,
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              children: [
                for (final (k, v) in _items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 104,
                          child: Text(k, style: AppTextStyles.caption),
                        ),
                        Expanded(
                          child: Text(
                            v,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
