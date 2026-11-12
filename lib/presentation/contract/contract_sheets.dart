import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
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

/// 사장님: 보내기 전 계약서 미리보기(서버가 만든 실제 계약서 화면). 닫고 시트에서 고친다
Future<void> showContractPreview(BuildContext context, String html) => Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('계약서 미리보기')),
          body: InAppWebView(initialData: InAppWebViewInitialData(data: html, mimeType: 'text/html', encoding: 'utf-8')),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫고 계속 고치기')),
            ),
          ),
        ),
      ),
    );

/// 일주봇 메시지 [PDF 열기] — 로그인한 당사자에게 10분짜리 링크를 받아 연다
Future<void> openLaborContractPdf(BuildContext context, int contractId) async {
  final c = await ContractService.byId(contractId);
  final url = c?['pdfUrl'] as String?;
  if (url == null) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('계약서를 열 수 없어요.')));
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
