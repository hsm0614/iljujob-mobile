import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/app_theme.dart';
import '../../../widget/app_ui.dart';

/// 고객센터 (2026-10 리디자인). 파란 헤더 카드·그림자 카드 → 질문 한 줄 + 할 일 줄.
/// 약관은 마이 > 약관 및 정책에 이미 있어 여기서 뺐다.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const _phone = '07047923001';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('고객센터')),
      body: ListView(
        children: [
          Container(
            color: AppColors.bgCard,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('무엇을 도와드릴까요?', style: AppTextStyles.h2),
                const SizedBox(height: 6),
                const Text(
                  '자주 묻는 질문에 없으면 1:1 문의를 남겨 주세요.\n사진도 함께 보낼 수 있어요.',
                  style: AppTextStyles.body2,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: () => Navigator.pushNamed(context, '/inquiry'),
                    child: const Text('1:1 문의하기'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AppMenuSection(
            children: [
              AppMenuRow(
                icon: Icons.help_outline_rounded,
                label: '자주 묻는 질문',
                onTap: () => Navigator.pushNamed(context, '/faq'),
              ),
              AppMenuRow(
                icon: Icons.call_outlined,
                label: '전화 상담',
                value: '070-4792-3001',
                onTap: () => launchUrl(Uri.parse('tel:$_phone')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
