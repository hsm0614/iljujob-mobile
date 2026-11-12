import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_theme.dart';
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

/// 알바생: 수락 전에 계약서 확인 — [동의하고 수락]이면 true
Future<bool> confirmWorkerContractSign(BuildContext context, int confirmId) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.bgCard,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('근로계약서도 함께 서명해요', style: AppTextStyles.h2),
          const SizedBox(height: 6),
          const Text('사장님이 서명한 근로계약서가 있어요. 근무일·시간·시급·지급일을 확인하고 수락하면 전자서명으로 기록되고, 언제든 다시 볼 수 있어요.',
              style: AppTextStyles.body2),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: () => openLaborContract(ctx, confirmId), child: const Text('계약서 보기')),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('동의하고 수락')),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}
