import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iljujob/config/app_theme.dart';
import 'signup_client_screen/signup_client_choice_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final textScaler = MediaQuery.of(context).textScaler
        .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.2);

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
                      fontSize: 16,
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
                        subtitle: '오늘 일하고\n오늘 받는 단기 알바',
                        badge: null,
                        isHighlighted: false,
                        onTap: () =>
                            Navigator.pushNamed(context, '/signup-choice'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TypeCard(
                        label: '사장님',
                        icon: Icons.storefront_outlined,
                        subtitle: '갑작스러운 결근도\n30분 내 해결',
                        badge: '빠른 채용',
                        isHighlighted: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignupClientChoiceScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                const Text(
                  '전화번호 인증으로 바로 시작합니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 28),
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
            fontSize: 46,
            color: AppColors.primary,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '필요한 날, 딱 맞는 알바',
          style: TextStyle(
            fontSize: 15,
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
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
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
                    color: widget.isHighlighted
                        ? AppColors.primaryMid
                        : AppColors.border,
                    width: widget.isHighlighted ? 1.5 : 1.0,
                  ),
                  boxShadow: widget.isHighlighted
                      ? AppShadows.cardElevated
                      : AppShadows.card,
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
                        color: widget.isHighlighted
                            ? AppColors.primaryLight
                            : const Color(0xFFEFF6FF),
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
                        fontSize: 17,
                        color: AppColors.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 6),

                    // 부제목
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
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
                        decoration: BoxDecoration(
                          color: widget.isHighlighted
                              ? AppColors.primary
                              : AppColors.bgMuted,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: widget.isHighlighted
                              ? Colors.white
                              : AppColors.textTertiary,
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
                      fontSize: 10,
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
