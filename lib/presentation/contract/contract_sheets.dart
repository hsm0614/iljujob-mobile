import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/services/contract_service.dart';

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
