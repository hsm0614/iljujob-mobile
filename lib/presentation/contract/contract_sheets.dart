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

/// 사장님: 계약서에 넣을 사업장 정보가 있는지 확인, 없으면 한 번 입력받는다. 준비되면 true
Future<bool> ensureContractProfile(BuildContext context) async {
  final p = await ContractService.profile();
  if (p.complete) return true;
  if (!context.mounted) return false;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bgCard,
    builder: (_) => _ProfileSheet(initial: p.profile),
  );
  return saved == true;
}

class _ProfileSheet extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _ProfileSheet({required this.initial});
  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final _rep = TextEditingController(text: widget.initial['repName']?.toString() ?? '');
  late final _addr = TextEditingController(text: widget.initial['bizAddress']?.toString() ?? '');
  late final _payDay = TextEditingController(text: widget.initial['payDay']?.toString() ?? '');
  late String _method = (widget.initial['payMethod']?.toString().isNotEmpty ?? false) ? widget.initial['payMethod'].toString() : '계좌이체';
  bool _saving = false;

  @override
  void dispose() {
    _rep.dispose();
    _addr.dispose();
    _payDay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ContractService.saveProfile({
        'repName': _rep.text.trim(), 'bizAddress': _addr.text.trim(), 'payDay': _payDay.text.trim(), 'payMethod': _method,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _rep.text.trim().isNotEmpty && _addr.text.trim().isNotEmpty && _payDay.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('근로계약서에 들어갈 정보', style: AppTextStyles.h2),
          const SizedBox(height: 4),
          const Text('처음 한 번만 입력하면 다음부터 자동으로 채워져요.', style: AppTextStyles.body2),
          const SizedBox(height: 16),
          TextField(controller: _rep, decoration: const InputDecoration(labelText: '대표자 이름'), onChanged: (_) => setState(() {})),
          TextField(controller: _addr, decoration: const InputDecoration(labelText: '사업장 주소'), onChanged: (_) => setState(() {})),
          TextField(
            controller: _payDay,
            decoration: const InputDecoration(labelText: '임금 지급일', hintText: '예: 근무 당일, 근무 다음 날, 매주 금요일'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final m in ['계좌이체', '현금'])
              ChoiceChip(label: Text(m), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(onPressed: ready && !_saving ? _save : null, child: const Text('저장')),
          ),
        ],
      ),
    );
  }
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
