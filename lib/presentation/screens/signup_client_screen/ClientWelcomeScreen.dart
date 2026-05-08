import 'package:flutter/material.dart';

const kBrand = Color(0xFF3B8AFF);

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
      backgroundColor: Colors.white,
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
                      color: const Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kBrand.withOpacity(0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: kBrand,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    '가입 완료!',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '지금 근처에서 알바를 구하는 분들이\n공고를 기다리고 있어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF6B7280),
                      height: 1.6,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 통계 카드 3개
                  Row(
                    children: const [
                      Expanded(
                        child: _StatCard(
                          number: '7,000+',
                          label: '대기 중인\n구직자',
                          icon: Icons.people_outline,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          number: '30분',
                          label: '평균 첫\n지원 시간',
                          icon: Icons.timer_outlined,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          number: '5회',
                          label: '무료 공고\n제공',
                          icon: Icons.card_giftcard_outlined,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // 안내 텍스트
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFFED7AA), width: 1),
                    ),
                    child: Row(
                      children: const [
                        Text('🎁', style: TextStyle(fontSize: 18)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '첫 공고는 무료예요. 지금 바로 올려보세요!',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFF92400E),
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 3),

                  // ✅ 메인 CTA — 공고 등록 (크고 강하게)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kBrand,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        minimumSize: const Size.fromHeight(56),
                        shadowColor: kBrand.withOpacity(0.4),
                      ),
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
                      icon: const Icon(Icons.add_circle_outline, size: 22),
                      label: const Text(
                        '지금 바로 공고 올리기',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
                      foregroundColor: const Color(0xFF9CA3AF),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text(
                      '나중에 올리기',
                      style: TextStyle(fontSize: 14),
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

// ─────────────────────────────────────────────
// 통계 카드
// ─────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String number;
  final String label;
  final IconData icon;

  const _StatCard({
    required this.number,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDBEAFE), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: kBrand, size: 22),
          const SizedBox(height: 8),
          Text(
            number,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kBrand,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}