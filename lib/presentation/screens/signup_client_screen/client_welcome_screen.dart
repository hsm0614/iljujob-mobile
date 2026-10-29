import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';

/// 가입 완료 직후 보여주는 웰컴 화면
/// 핵심 목적: 첫 공고 등록 유도 (가장 중요한 전환 포인트)
class ClientWelcomeScreen extends StatefulWidget {
  const ClientWelcomeScreen({super.key});

  @override
  State<ClientWelcomeScreen> createState() => _ClientWelcomeScreenState();
}

class _ClientWelcomeScreenState extends State<ClientWelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCard,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeIn,
          child: SlideTransition(
            position: _slideUp,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // 완료 아이콘
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                      // 색 그림자(글로우) 제거 — DESIGN.md Paper-Thin
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppColors.primary,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    '가입했어요',
                    style: TextStyle(
                      fontSize: AppFontSize.display,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  // 파란 테두리 타일 3개('간편'·'채팅'·'2건')+주황 상자 → 체크 세 줄.
                  // '월 무료 2건'과 '첫 공고는 무료'가 서로 달랐고 서버 한도(기본 월 3건)와도 달랐다 — 숫자는 빼고 말로
                  for (final t in const [
                    '매달 무료로 공고를 올릴 수 있어요',
                    '지원이 오면 채팅으로 바로 이어져요',
                    '급할 땐 즉시 게시로 바로 공개해요',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.check_rounded, size: 20, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(child: Text(t, style: AppTextStyles.body1.copyWith(color: AppColors.textPrimary))),
                        ],
                      ),
                    ),

                  const Spacer(flex: 3),

                  // ✅ 메인 CTA — 공고 등록 (크고 강하게)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () {
                      // ✅ 웰컴 화면 제거하고 메인 위에 post_job 쌓기
Navigator.pushNamedAndRemoveUntil(
  context,
  '/client_main',
  (_) => false,
);
// 메인 이동 후 바로 공고 등록 화면 push
WidgetsBinding.instance.addPostFrameCallback((_) {
  Navigator.pushNamed(context, '/post_job');
});
                      },
                      icon: const SizedBox.shrink(),
                      label: const Text('첫 공고 올리기'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 서브 CTA — 나중에 (작게)
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/client_main',
                        (_) => false,
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textTertiary,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text(
                      '나중에 올리기',
                      style: TextStyle(fontSize: AppFontSize.button),
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

