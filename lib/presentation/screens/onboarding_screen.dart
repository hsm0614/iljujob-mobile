import 'package:flutter/material.dart';
import '../../widget/dev_account_switch.dart';
import 'package:flutter/services.dart';
import 'package:iljujob/config/app_theme.dart';
import 'worker_screen/home_main_screen.dart';
import 'signup_client_screen/signup_client_choice_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final textScaler = MediaQuery.of(
      context,
    ).textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.2);

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: size.height * 0.10),

                // 브랜드
                const _BrandBlock(),

                const SizedBox(height: 20),

                // 기능 태그 (단색 아웃라인 필)
                const _FeatureTags(),

                SizedBox(height: size.height * 0.06),

                // 역할 선택 레이블
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '어떤 분이신가요?',
                    style: TextStyle(
                      fontSize: AppFontSize.buttonLg,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // 카드
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _TypeCard(
                        label: '알바생',
                        icon: Icons.person_outline_rounded,
                        subtitle: '원하는 날짜의\n일급·주급 알바 찾기',
                        badge: null,
                        isHighlighted: false,
                        onTap:
                            () =>
                                Navigator.pushNamed(context, '/signup-choice'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TypeCard(
                        label: '사장님',
                        icon: Icons.storefront_outlined,
                        subtitle: '필요한 날에 맞춰\n구인 공고 등록하기',
                        // 두 카드는 같은 무게 — 구직자 쪽이 비활성처럼 보이던 문제(2026-10)
                        badge: null,
                        isHighlighted: false,
                        onTap:
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => const SignupClientChoiceScreen(),
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
                const DevAccountSwitchButton(),

                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const HomeMainScreen(),
                          ),
                        ),
                    child: const Text('공고 먼저 보기'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('지원할 때 가입할 수 있어요', style: AppTextStyles.caption),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 브랜드 블록
// ─────────────────────────────────────────────
class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text(
          '알바일주',
          style: TextStyle(
            fontFamily: 'Jalnan2TTF',
            fontSize: AppFontSize.hero,
            color: AppColors.primary,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '필요한 날, 딱 맞는 알바',
          style: TextStyle(
            fontSize: AppFontSize.body1,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 기능 키워드 태그 (아웃라인 필, 단색)
// ─────────────────────────────────────────────
class _FeatureTags extends StatelessWidget {
  const _FeatureTags();

  @override
  Widget build(BuildContext context) {
    const tags = ['긴급 호출', '즉시 게시', '일급·주급'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < tags.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '·',
                style: TextStyle(fontSize: AppFontSize.meta, color: AppColors.textTertiary),
              ),
            ),
          _Tag(tags[i]),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    // 누를 수 없는 소개 문구라 버튼처럼 보이는 테두리 알약을 쓰지 않는다
    return Text(
      label,
      style: const TextStyle(
        fontSize: AppFontSize.body2,
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 선택 카드
// ─────────────────────────────────────────────
class _TypeCard extends StatefulWidget {
  final String label;
  final IconData icon;
  final String subtitle;
  final String? badge;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _TypeCard({
    required this.label,
    required this.icon,
    required this.subtitle,
    required this.badge,
    required this.isHighlighted,
    required this.onTap,
  });

  @override
  State<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends State<_TypeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${widget.label}으로 시작하기',
      child: AnimatedScale(
        duration: const Duration(milliseconds: 100),
        scale: _pressed ? 0.96 : 1.0,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: () {
                setState(() => _pressed = false);
                HapticFeedback.lightImpact();
                widget.onTap();
              },
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(
                    color:
                        widget.isHighlighted
                            ? AppColors.primaryMid
                            : AppColors.border,
                    width: widget.isHighlighted ? 1.5 : 1.0,
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 아이콘
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color:
                            widget.isHighlighted
                                ? AppColors.primaryLight
                                : AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 22,
                        color: AppColors.primary,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 라벨
                    Text(
                      widget.label,
                      style: const TextStyle(
                        fontFamily: 'Jalnan2TTF',
                        fontSize: AppFontSize.title,
                        color: AppColors.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 6),

                    // 부제목
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        fontSize: AppFontSize.meta,
                        color: AppColors.textSecondary,
                        height: 1.55,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 화살표
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 뱃지
            if (widget.badge != null)
              Positioned(
                top: -10,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    boxShadow: AppShadows.button,
                  ),
                  child: Text(
                    widget.badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
