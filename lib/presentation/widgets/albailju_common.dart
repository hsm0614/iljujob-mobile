import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';

class AlbailjuAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;
  final bool brand;

  const AlbailjuAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.bottom,
    this.centerTitle = false,
    this.brand = false,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(52 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final appBarBottom =
        bottom == null
            ? null
            : PreferredSize(
              preferredSize: bottom!.preferredSize,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.bgCard,
                  border: Border(
                    bottom: BorderSide(color: AppColors.borderSub),
                  ),
                ),
                child: bottom!,
              ),
            );

    // 리디자인(2026-10): 88px 파란 그라데이션(brand)을 없앴다. 탭 루트도 52px 흰 앱바.
    // brand=true 는 '탭 루트 제목'이라는 뜻으로만 남는다 — 글자가 한 단계 크다.
    return AppBar(
      backgroundColor: AppColors.bgCard,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 52,
      centerTitle: centerTitle,
      titleSpacing: leading == null ? 20 : 0,
      leading: leading,
      title:
          titleWidget ??
          (title == null
              ? null
              : Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: brand ? AppTextStyles.tabTitle : AppTextStyles.h3,
              )),
      actions: actions,
      bottom: appBarBottom,
    );
  }
}

class AlbailjuPostJobCta extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  final bool inverted;

  const AlbailjuPostJobCta({
    super.key,
    required this.onPressed,
    this.label = '공고 올리기',
    this.inverted = false,
  });

  // 2026-10: 큰 파란 알약 → 파란 글자 버튼 (내 공고 상단바와 같은 모양). [inverted]는 하위호환으로만 받는다.
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_rounded, size: 20),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: inverted ? Colors.white : AppColors.primary,
        textStyle: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class AlbailjuPostJobPrimaryButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const AlbailjuPostJobPrimaryButton({
    super.key,
    required this.onPressed,
    this.label = '공고 올리기',
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Jalnan2TTF',
                  fontSize: AppFontSize.buttonLg,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AlbailjuPageTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const AlbailjuPageTitle({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.h2),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: AppTextStyles.body2),
          ],
        ],
      ),
    );
  }
}
