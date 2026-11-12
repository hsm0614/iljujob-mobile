// 채팅 번역 — 상대 메시지를 길게 눌러 [번역]. 서버 /api/ai/translate (하루 100회, 캐시)
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../config/constants.dart';
import '../../data/services/authenticated_http_client.dart';

const _langs = {'ko', 'en', 'zh', 'vi', 'th', 'ru', 'uz', 'mn', 'ne', 'km', 'id', 'ja', 'tl', 'my'};

/// 한국어 메시지 → 폰 언어(한국어 폰이면 영어), 외국어 메시지 → 한국어
String _targetFor(String text) {
  if (!RegExp(r'[가-힣]').hasMatch(text)) return 'ko';
  final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  return device != 'ko' && _langs.contains(device) ? device : 'en';
}

Future<String> _translate(String text) async {
  final r = await AuthenticatedHttpClient.postJson(
    Uri.parse('$baseUrl/api/ai/translate'),
    body: {'text': text, 'target': _targetFor(text)},
  );
  final b = jsonDecode(r.body) as Map<String, dynamic>;
  if (r.statusCode != 200) throw Exception(b['message'] ?? '번역하지 못했어요');
  return b['text'].toString();
}

Future<void> showChatTranslation(BuildContext context, String text) => showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: FutureBuilder<String>(
            future: _translate(text),
            builder: (ctx, snap) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: AppTextStyles.caption, maxLines: 4, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                if (snap.connectionState != ConnectionState.done)
                  const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                else if (snap.hasError)
                  Text(snap.error.toString().replaceFirst('Exception: ', ''),
                      style: AppTextStyles.body2.copyWith(color: AppColors.error))
                else ...[
                  SelectableText(snap.data!, style: AppTextStyles.body1),
                  const SizedBox(height: 10),
                  const Text('AI 번역이라 틀릴 수 있어요. 시간·금액은 원문을 확인하세요.', style: AppTextStyles.caption),
                ],
              ],
            ),
          ),
        ),
      ),
    );
