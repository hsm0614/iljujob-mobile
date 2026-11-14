import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';
import '../../../widget/app_ui.dart';

/// 홈 '+ 올리기' → 무엇을 올릴지 고르는 화면 (홈 시안 3번, 2026-11).
/// 공고 올리기가 기본으로 골라져 있어 대부분은 버튼 한 번이면 지나간다.
class PostChooseScreen extends StatefulWidget {
  const PostChooseScreen({super.key});

  @override
  State<PostChooseScreen> createState() => _PostChooseScreenState();
}

class _PostChooseScreenState extends State<PostChooseScreen> {
  bool _promotion = false;

  Widget _card({
    required bool selected,
    required IconData icon,
    required String title,
    required String body,
    required String price,
    required VoidCallback onTap,
  }) => AppPressScale(
    scale: 0.98,
    child: Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryLight : AppColors.bgMuted,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, size: 26, color: selected ? AppColors.primary : AppColors.textSecondary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.h3.copyWith(fontSize: AppFontSize.titleLg)),
                    const SizedBox(height: 6),
                    Text(body, style: AppTextStyles.body1.copyWith(fontSize: AppFontSize.button)),
                    const SizedBox(height: 6),
                    Text(
                      price,
                      style: AppTextStyles.body2.copyWith(
                        color: selected ? AppColors.primaryDark : AppColors.textSecondary,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : Colors.transparent,
                  border: selected ? null : Border.all(color: AppColors.textDisabled, width: 1.5),
                ),
                child: selected ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCard,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '닫기',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: -0.3),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text('무엇을 올릴까요?', style: AppTextStyles.h1.copyWith(fontWeight: FontWeight.w700, height: 1.4)),
            const SizedBox(height: 8),
            Text('나중에 언제든 바꿀 수 있어요', style: AppTextStyles.body1.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 28),
            _card(
              selected: !_promotion,
              icon: Icons.description_outlined,
              title: '공고 올리기',
              body: '하루·단기 알바를 직접 구해요. 지원자와 채팅으로 바로 이야기해요.',
              price: '무료 월 3회\n즉시 게시 8,900원부터', // 한 줄이면 '원부/터'로 꺾였다
              onTap: () => setState(() => _promotion = false),
            ),
            const SizedBox(height: 10),
            _card(
              selected: _promotion,
              icon: Icons.campaign_outlined,
              title: '채용 홍보',
              body: '내 공고를 알바생 홈에 30일 동안 크게 보여요. 배너나 광고 카드로 올라가요.',
              price: '검수 후 게시\n30일 150,000원',
              onTap: () => setState(() => _promotion = true),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomBar(
        child: AppPrimaryButton(
          label: _promotion ? '채용 홍보 신청하기' : '공고 올리기 시작',
          height: 54,
          onPressed: () => Navigator.pushReplacementNamed(context, _promotion ? '/promotion' : '/post_job'),
        ),
      ),
    );
  }
}
