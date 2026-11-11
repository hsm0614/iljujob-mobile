import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../data/services/agent_service.dart';
import '../../widget/app_ui.dart';

/// 일주 매니저 2호: 지원 0명 공고 — 원인과 고친 안, [이대로 고치기] 한 번 (2026-11-12)
class JobRescueScreen extends StatefulWidget {
  final int jobId;
  const JobRescueScreen({super.key, required this.jobId});

  @override
  State<JobRescueScreen> createState() => _JobRescueScreenState();
}

class _JobRescueScreenState extends State<JobRescueScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _saving = false;
  bool _usePay = true;
  bool _useRewrite = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await AgentService.jobRescue(widget.jobId);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<Map<String, dynamic>> get _diagnoses => (_data?['diagnoses'] as List? ?? []).cast<Map<String, dynamic>>();
  int? get _suggestedPay {
    for (final d in _diagnoses) {
      final a = d['action'];
      if (a is Map && a['type'] == 'raise_pay') return (a['pay'] as num?)?.toInt();
    }
    return null;
  }

  String? get _rewrite => _data?['rewrite'] as String?;

  Future<void> _apply() async {
    setState(() => _saving = true);
    try {
      await AgentService.applyJobRescue(
        widget.jobId,
        pay: _usePay ? _suggestedPay : null,
        description: _useRewrite ? _rewrite : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('공고를 고쳤어요.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canApply = (_usePay && _suggestedPay != null) || (_useRewrite && _rewrite != null);
    return Scaffold(
      backgroundColor: AppColors.bgCard,
      appBar: AppBar(title: const Text('공고 살리기')),
      bottomNavigationBar: _data != null && (_suggestedPay != null || _rewrite != null)
          ? AppBottomBar(
              child: AppPrimaryButton(label: '이대로 고치기', loading: _saving, onPressed: canApply ? _apply : null),
            )
          : null,
      body: _error != null
          ? AppEmptyState(icon: Icons.error_outline, title: _error!, actionLabel: '다시 시도', onAction: _load, secondaryAction: true)
          : _data == null
              ? const AppSkeletonList(rows: 4)
              : _body(),
    );
  }

  Widget _body() {
    final job = _data!['job'] as Map<String, dynamic>;
    final diagnoses = _diagnoses;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(job['title']?.toString() ?? '', style: AppTextStyles.h2),
        const SizedBox(height: 4),
        Text('본 사람 ${job['views']}명 · 지원 ${job['applicants']}명', style: AppTextStyles.body2),
        const SizedBox(height: 20),
        if (diagnoses.isEmpty)
          const AppEmptyState(icon: Icons.check_circle_outline, title: '지금은 고칠 점이 없어요', message: '지원자가 들어오고 있어요.'),
        ...diagnoses.map((d) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d['title']?.toString() ?? '', style: AppTextStyles.h3),
                const SizedBox(height: 4),
                Text(d['detail']?.toString() ?? '', style: AppTextStyles.body2),
              ]),
            )),
        if (_suggestedPay != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _usePay,
            onChanged: (v) => setState(() => _usePay = v ?? false),
            title: Text('${job['payType']} ${job['pay']}원 → $_suggestedPay원', style: AppTextStyles.body1),
          ),
        if (_rewrite != null) ...[
          const Divider(height: 32),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _useRewrite,
            onChanged: (v) => setState(() => _useRewrite = v ?? false),
            title: const Text('설명을 이렇게 바꾸기', style: AppTextStyles.body1),
            subtitle: const Text('AI가 원래 설명을 바탕으로 다듬었어요. 급여·시간 같은 조건은 바꾸지 않았어요.', style: AppTextStyles.caption),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.bgPage, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Text(_rewrite!, style: AppTextStyles.body2),
          ),
        ],
      ],
    );
  }
}
