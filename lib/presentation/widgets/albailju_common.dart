import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';

class AlbailjuAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;

  const AlbailjuAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.bottom,
    this.centerTitle = false,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.bgCard,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: AppColors.bgCard,
      elevation: 0,
      scrolledUnderElevation: 0.5,
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
                style: const TextStyle(
                  fontFamily: 'Jalnan2TTF',
                  color: AppColors.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              )),
      actions: actions,
      bottom: bottom,
    );
  }
}

class AlbailjuPostJobCta extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const AlbailjuPostJobCta({
    super.key,
    required this.onPressed,
    this.label = '공고 올리기',
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
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
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
