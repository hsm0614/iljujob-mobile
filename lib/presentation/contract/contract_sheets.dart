import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:iljujob/config/constants.dart';
import '../../data/services/contract_service.dart';
import '../screens/webview_screen.dart';

/// 계약서 열기 — 교부 링크(브라우저에서 열람·인쇄·PDF 저장)
Future<void> openLaborContract(BuildContext context, int confirmId) async {
  final c = await ContractService.forConfirmation(confirmId);
  final url = c?['viewUrl'] as String?;
  if (url == null) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('계약서를 찾을 수 없어요.')));
    return;
  }
  await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
}

/// 알바생: 근로계약서 서명 직전 본인인증(가입 때와 같은 다날 PASS·문자). 성공하면 imp_uid, 취소·실패면 null
Future<String?> verifyIdentityForSigning(BuildContext context) async {
  try {
    final r = await http.post(Uri.parse('$baseUrl/api/worker/danal-certification-url'),
        headers: {'Content-Type': 'application/json'});
    final url = (jsonDecode(r.body) as Map)['certificationUrl']?.toString();
    if (url == null || url.isEmpty || !context.mounted) return null;
    return await Navigator.of(context).push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => WebViewScreen(url: url)),
    );
  } catch (e) {
    debugPrint('서명 본인인증 실패: $e');
    return null;
  }
}
