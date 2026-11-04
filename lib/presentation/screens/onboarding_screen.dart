import 'package:flutter/material.dart';
import '../../widget/dev_account_switch.dart';
import 'package:iljujob/config/app_theme.dart';
import '../../widget/app_ui.dart';
import 'worker_screen/home_main_screen.dart';
import 'signup_client_screen/signup_client_choice_screen.dart';

// 시안 BQvB3zzVYLBcMNbGP6Kznk 1번: 역할 두 줄이 주인공, '공고 먼저 보기'는 아래 글자 링크.
// 예전엔 '공고 먼저 보기'가 가장 큰 파란 버튼이라 가입보다 먼저 눈에 들어왔다.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final textScaler = MediaQuery.of(
      context,
    ).textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.2);

    return Scaffold(
      backgroundColor: AppColors.bgCard,
      body: SafeArea(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: size.height * 0.08),
                const Text(
                  '알바일주',
                  style: TextStyle(
                    fontFamily: 'Jalnan2TTF',
                    fontSize: AppFontSize.h1,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '필요한 날만 일하고,\n필요한 날만 뽑아요',
                  style: AppTextStyles.h2.copyWith(fontSize: AppFontSize.h1, height: 1.35),
                ),
                const SizedBox(height: 8),
                Text('일급·주급 단기 알바', style: AppTextStyles.body1.copyWith(color: AppColors.textBody)),
                SizedBox(height: size.height * 0.06),
                Text(
                  '어떻게 쓰실 건가요?',
                  style: AppTextStyles.body1.copyWith(color: AppColors.textBody, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _RoleRow(
                  title: '알바를 찾아요',
                  subtitle: '내 근처 일급·주급 공고 보고 지원',
                  onTap: () => Navigator.pushNamed(context, '/signup-choice'),
                ),
                const SizedBox(height: 10),
                _RoleRow(
                  title: '사람을 구해요',
                  subtitle: '공고 올리고 지원자와 바로 채팅',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SignupClientChoiceScreen()),
                  ),
                ),
                const DevAccountSwitchButton(),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeMainScreen()),
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: AppColors.textPrimary,
                    textStyle: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('가입 없이 공고 먼저 볼게요'),
                ),
                const Text(
                  '지원할 때 가입해도 돼요',
                  style: AppTextStyles.caption,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({required this.title, required this.subtitle, required this.onTap});
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: AppPressScale(
        child: Material(
          color: AppColors.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            side: const BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 84),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppTextStyles.h3),
                          const SizedBox(height: 3),
                          Text(subtitle, style: AppTextStyles.body1.copyWith(color: AppColors.textBody)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
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
