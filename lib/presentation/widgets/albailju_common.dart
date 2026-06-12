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
  Size get preferredSize => Size.fromHeight(
    (brand ? 88 : kToolbarHeight) + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final titleColor = brand ? Colors.white : AppColors.primary;
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

    return AppBar(
      backgroundColor: brand ? AppColors.primary : AppColors.bgCard,
      foregroundColor: brand ? Colors.white : AppColors.textPrimary,
      surfaceTintColor: brand ? AppColors.primary : AppColors.bgCard,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      toolbarHeight: brand ? 88 : kToolbarHeight,
      centerTitle: centerTitle,
      titleSpacing: leading == null ? 20 : 0,
      leading: leading,
      flexibleSpace:
          brand
              ? const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                ),
              )
              : null,
      title:
          titleWidget ??
          (title == null
              ? null
              : Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Jalnan2TTF',
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ).copyWith(color: titleColor),
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: inverted ? Colors.white : AppColors.primary,
          foregroundColor: inverted ? AppColors.primary : Colors.white,
          padding: const EdgeInsets.fromLTRB(13, 0, 15, 0),
          textStyle: const TextStyle(
            fontFamily: 'Jalnan2TTF',
            fontSize: 13,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          elevation: 0,
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
