import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kBrand = Color(0xFF3B8AFF);

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.of(context).textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.2);

    return Scaffold(
      backgroundColor: const Color(0xFFEFF3F8),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isSmall = constraints.maxHeight < 700;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 브랜드 타이틀
                      ShaderMask(
                        shaderCallback: (rect) => const LinearGradient(
                          colors: [kBrand, Color(0xFF6FB2FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(rect),
                        child: const Text(
                          '알바일주',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            color: Colors.white, // ShaderMask로 대체
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '빠르고 믿을 수 있는 주급·일급 매칭 플랫폼',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                          height: 1.6,
                        ),
                      ),
                      SizedBox(height: isSmall ? 28 : 40),

                      const Text(
                        '당신은 어떤 사용자이신가요?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 사용자 유형 선택 (반응형)
                      constraints.maxWidth > 340
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: _UserTypeCard(
                                    label: '알바생',
                                    subtitle: '오늘 가능한 알바 찾기',
                                    icon: Icons.person_outline,
                                    onTap: () {
                                      // 번호 입력 → 본인인증 → (기존) 자동 로그인 / (신규) 회원정보 입력
                                      HapticFeedback.lightImpact();
                                      Navigator.pushNamed(context, '/signup_worker'); // 기존 구조 유지
                                    },
                                    variant: CardVariant.filled, // 브랜드 그라디언트
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _UserTypeCard(
                                    label: '사장님',
                                    subtitle: '알바생 찾기',
                                    icon: Icons.business_outlined,
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.pushNamed(context, '/signup_client'); // 기존 구조 유지
                                    },
                                    variant: CardVariant.outlined, // 동등 비중 + 대비만 다르게
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                _UserTypeCard(
                                  label: '알바생',
                                  subtitle: '번호 인증으로 시작',
                                  icon: Icons.person_outline,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.pushNamed(context, '/signup_worker');
                                  },
                                  variant: CardVariant.filled,
                                ),
                                const SizedBox(height: 12),
                                _UserTypeCard(
                                  label: '사장님',
                                  subtitle: '번호 인증으로 시작',
                                  icon: Icons.business_outlined,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.pushNamed(context, '/signup_client');
                                  },
                                  variant: CardVariant.outlined,
                                ),
                              ],
                            ),

                      const SizedBox(height: 16),

                      // 보조 안내: 로그인 없이 진행
                      const Text(
                        '회원가입 없이 전화번호 인증으로 바로 시작합니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF6B7280),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

enum CardVariant { filled, outlined }

class _UserTypeCard extends StatefulWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final CardVariant variant;

  const _UserTypeCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.variant,
  });

  @override
  State<_UserTypeCard> createState() => _UserTypeCardState();
}

class _UserTypeCardState extends State<_UserTypeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const baseRadius = 20.0;

    final decoration = switch (widget.variant) {
      CardVariant.filled => BoxDecoration(
          gradient: const LinearGradient(
            colors: [kBrand, Color(0xFF6FB2FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(baseRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
      CardVariant.outlined => BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(baseRadius),
          border: Border.all(color: const Color(0xFFD1D5DB), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08), // ← black08 대체
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
    };

    final iconColor = widget.variant == CardVariant.filled ? Colors.white : kBrand;
    final titleColor = widget.variant == CardVariant.filled ? Colors.white : const Color(0xFF111827);
    final subColor = widget.variant == CardVariant.filled ? Colors.white.withOpacity(0.9) : const Color(0xFF4B5563);

    return Semantics(
      button: true,
      label: '${widget.label} 시작하기',
      child: AnimatedScale(
        duration: const Duration(milliseconds: 90),
        scale: _pressed ? 0.98 : 1.0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 120, minWidth: 140),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(baseRadius),
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: () {
                setState(() => _pressed = false);
                widget.onTap();
              },
              splashColor: widget.variant == CardVariant.filled
                  ? Colors.white24
                  : kBrand.withOpacity(0.08),
              child: Ink(
                decoration: decoration,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 30, color: iconColor),
                    const SizedBox(height: 10),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: subColor,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
