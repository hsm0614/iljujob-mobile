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
                SizedBox(height: size.height * 0.08),

                // ── 브랜드 블록
                const _BrandBlock(),

                SizedBox(height: size.height * 0.045),

                // ── 기능 요약 칩 3개
                const _FeatureRow(),

                SizedBox(height: size.height * 0.045),

                // ── 역할 선택
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

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _TypeCard(
                        label: '알바생',
                        icon: Icons.person_outline_rounded,
                        iconBgColor: const Color(0xFFEFF6FF),
                        iconColor: AppColors.primary,
                        features: const [
                          '💰  일급·주급 즉시 지급',
                          '📍  내 근처 오늘 공고만',
                          '⭐  신뢰등급으로 빠른 매칭',
                        ],
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
                        icon: Icons.storefront_outlined,
                        iconBgColor: AppColors.primaryLight,
                        iconColor: AppColors.primary,
                        features: const [
                          '⚡  긴급 호출 30분 대타',
                          '🎫  즉시 게시 상단 노출',
                          '🤖  AI 공고문 자동 작성',
                        ],
                        badge: '빠른 채용',
                        isHighlighted: true,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SignupClientChoiceScreen(),
                            ),
                          );
                        },
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
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
              color: Colors.white,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '필요한 날, 딱 맞는 알바',
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 기능 요약 칩 3개
// ─────────────────────────────────────────────
class _FeatureRow extends StatelessWidget {
  const _FeatureRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FeatureChip(
            emoji: '⚡',
            label: '긴급 호출',
            color: const Color(0xFFEF4444),
            bgColor: const Color(0xFFFFF5F5),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FeatureChip(
            emoji: '🎫',
            label: '즉시 게시',
            color: AppColors.primary,
            bgColor: const Color(0xFFEFF6FF),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FeatureChip(
            emoji: '💰',
            label: '일급·주급',
            color: const Color(0xFF10B981),
            bgColor: const Color(0xFFF0FDF4),
          ),
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final Color bgColor;

  const _FeatureChip({
    required this.emoji,
    required this.label,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
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
  final Color iconBgColor;
  final Color iconColor;
  final List<String> features;
  final String? badge;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _TypeCard({
    required this.label,
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.features,
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
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 아이콘
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.iconBgColor,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 22,
                        color: widget.iconColor,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 라벨
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontFamily: 'Jalnan2TTF',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: widget.isHighlighted
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 기능 목록
                    ...widget.features.map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          f,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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
