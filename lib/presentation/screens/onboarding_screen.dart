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
                // ── 상단 여백 (화면 높이에 비례)
                SizedBox(height: size.height * 0.10),

                // ── 브랜드 블록
                _BrandBlock(),

                SizedBox(height: size.height * 0.07),

                // ── 질문
                const Text(
                  '어떤 분이신가요?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: 18),

                // ── 카드 2개 (가로형, 동등 비중)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _TypeCard(
                        label: '알바생',
                        subtitle: '오늘 가능한 알바 찾기',
                        icon: Icons.person_outline_rounded,
                        badge: null,
                        isHighlighted: false,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.pushNamed(context, '/signup-choice');
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TypeCard(
                        label: '사장님',
                        subtitle: '알바생 바로 구하기',
                        icon: Icons.storefront_outlined,
                        badge: '빠른 채용',
                        isHighlighted: true,
                        onTap: () {
                          HapticFeedback.lightImpact();
                      Navigator.push(context,
  MaterialPageRoute(builder: (_) => const SignupClientChoiceScreen()));
                        },
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // ── 하단 안내
                const Text(
                  '전화번호 인증으로 바로 시작합니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 24),
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
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ✅ Jalnan2TTF 폰트 적용
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryMid],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rect),
          child: const Text(
            '알바일주',
            style: TextStyle(
              fontFamily: 'Jalnan2TTF',
              fontSize: 48,
              fontWeight: FontWeight.w800,
              color: Colors.white, // ShaderMask가 덮어씀
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '오늘 채용 · 오늘 근무',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 선택 카드
// ─────────────────────────────────────────────
class _TypeCard extends StatefulWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _TypeCard({
    required this.label,
    required this.subtitle,
    required this.icon,
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
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 아이콘
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: widget.isHighlighted
                            ? AppColors.primaryLight
                            : AppColors.bgMuted,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 24,
                        color: widget.isHighlighted
                            ? AppColors.primary
                            : AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 라벨
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontFamily: 'Jalnan2TTF',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: widget.isHighlighted
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 5),

                    // 서브타이틀
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 화살표
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
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
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // 뱃지 (사장님 카드만)
            if (widget.badge != null)
              Positioned(
                top: -10,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
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
