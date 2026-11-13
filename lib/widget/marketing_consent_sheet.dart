import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';

/// 사장님 광고성 정보(혜택·소식) 수신 동의 — 홈에서 한 번만 묻는다.
/// 가입 화면 체크값이 서버에 저장되지 않던 버그(2026-11-03 수정) 때문에
/// 기존 사장님 전원이 '미동의'로 남아 있어 다시 받는다.
/// '괜찮아요'는 서버를 부르지 않는다 — 지금 받고 있는 알림 설정을 바꾸지 않기 위해서.
class MarketingConsentSheet {
  static const _askedKey = 'client_marketing_consent_asked_v1';

  static Future<void> maybeShow(BuildContext context, {required bool agreed}) async {
    if (agreed) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) == true) return;
    await prefs.setBool(_askedKey, true);
    if (!context.mounted) return;

    final accepted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 32 + MediaQuery.paddingOf(sheetContext).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '혜택 소식을 받아보시겠어요?',
              style: TextStyle(
                fontSize: AppFontSize.titleLg,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '이용권 할인, 새 기능, 채용 팁을 문자와 앱 알림으로 보내드려요.\n'
              '선택 사항이고, 마이페이지 > 알림 설정에서 언제든 끌 수 있어요.',
              style: TextStyle(
                fontSize: AppFontSize.button,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: const Text(
                      '괜찮아요',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('받을게요'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (accepted != true || !context.mounted) return;
    try {
      final res = await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/client/marketing-consent'),
        body: {'agreed': true},
      );
      if (!context.mounted) return;
      final now = DateTime.now();
      // 처리 결과 통지(정보통신망법 제50조 ⑦): 전송자·일자·처리 내용
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.statusCode == 200
            ? '알바일주 혜택 소식 수신에 동의하셨어요 (${now.year}. ${now.month}. ${now.day}.)'
            : '저장하지 못했어요. 알림 설정에서 다시 켜 주세요.'),
      ));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장하지 못했어요. 알림 설정에서 다시 켜 주세요.')),
      );
    }
  }
}
