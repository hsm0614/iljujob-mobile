import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../data/services/vacancy_service.dart';
import '../../widget/app_ui.dart';

/// 사장님: 결원 복구 — 대체 후보 고르고 AI 제안문 확인 후 보내기 (2026-11-11)
class VacancyRecoveryScreen extends StatefulWidget {
  final int confirmId;
  const VacancyRecoveryScreen({super.key, required this.confirmId});

  @override
  State<VacancyRecoveryScreen> createState() => _VacancyRecoveryScreenState();
}

class _VacancyRecoveryScreenState extends State<VacancyRecoveryScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _sending = false;
  bool? _auto;
  final _picked = <int>{};
  final _message = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    VacancyService.autoVacancy().then((v) => mounted ? setState(() => _auto = v) : null);
  }

  Future<void> _toggleAuto(bool on) async {
    setState(() => _auto = on);
    try {
      await VacancyService.setAutoVacancy(on);
    } catch (e) {
      if (!mounted) return;
      setState(() => _auto = !on);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // 일주 매니저 위임 스위치 — 고르는 화면·진행 화면 둘 다 맨 아래
  Widget _autoSwitch() => _auto == null
      ? const SizedBox.shrink()
      : SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _auto!,
          onChanged: _toggleAuto,
          title: const Text('다음부터 자동으로 대타 찾기', style: AppTextStyles.body1),
          subtitle: const Text('알바생이 취소하면 일주 매니저가 후보 5명에게 바로 제안을 보내고 알려드려요. 확정은 먼저 수락한 분으로 돼요.',
              style: AppTextStyles.body2),
        );

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await VacancyService.forConfirmation(widget.confirmId);
      final cands = (d['candidates'] as List? ?? []).cast<Map<String, dynamic>>();
      _picked
        ..clear()
        ..addAll(cands.take(5).map((c) => (c['workerId'] as num).toInt()));
      _message.text = (d['draft'] as Map?)?['message']?.toString() ?? '';
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final n = await VacancyService.send(widget.confirmId, _picked.toList(), _message.text.trim(),
          aiWritten: (_data?['draft'] as Map?)?['by'] == 'ai');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n명에게 보냈어요. 먼저 수락한 한 분과 확정돼요.')));
      _data = null;
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovery = _data?['recovery'] as Map<String, dynamic>?;
    final cands = (_data?['candidates'] as List? ?? []).cast<Map<String, dynamic>>();
    final canSend = recovery == null && _data != null && cands.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.bgCard,
      appBar: AppBar(title: const Text('대체 후보 찾기')),
      bottomNavigationBar: canSend
          ? AppBottomBar(
              child: AppPrimaryButton(
                label: '${_picked.length}명에게 보내기',
                loading: _sending,
                onPressed: _picked.isEmpty || _message.text.trim().isEmpty ? null : _send,
              ),
            )
          : null,
      body: _error != null
          ? AppEmptyState(icon: Icons.error_outline, title: _error!, actionLabel: '다시 시도', onAction: _load, secondaryAction: true)
          : _data == null
              ? const AppSkeletonList(rows: 5, avatar: true)
              : recovery != null
                  ? _progress(recovery)
                  : cands.isEmpty
                      ? const AppEmptyState(
                          icon: Icons.person_search_outlined,
                          title: '지금 연락할 수 있는 후보가 없어요',
                          message: '이 공고 지원자, 함께 일한 알바생, 근처에서 오늘 일할 수 있다고 표시한 사람을 찾아봤어요.',
                        )
                      : _picker(cands),
    );
  }

  Widget _picker(List<Map<String, dynamic>> cands) {
    final aiWritten = (_data?['draft'] as Map?)?['by'] == 'ai';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('대체 후보 ${cands.length}명을 찾았어요', style: AppTextStyles.h2),
        const SizedBox(height: 4),
        const Text('먼저 수락한 한 분과만 확정되고, 나머지 분께는 마감을 알려드려요.', style: AppTextStyles.body2),
        const SizedBox(height: 16),
        ...cands.map((c) {
          final id = (c['workerId'] as num).toInt();
          return CheckboxListTile(
            value: _picked.contains(id),
            onChanged: (v) => setState(() => v == true ? _picked.add(id) : _picked.remove(id)),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.trailing,
            title: Text(c['name']?.toString() ?? '알바생', style: AppTextStyles.body1),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                AppGradeBadge(score: (c['activityScore'] as num?)?.toInt() ?? 0),
                const SizedBox(width: 8),
                Flexible(child: Text(c['sourceLabel']?.toString() ?? '', style: AppTextStyles.body2, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          );
        }),
        const Divider(height: 32),
        Text(aiWritten ? '제안문 · AI가 썼어요. 고쳐도 돼요' : '제안문 · 고쳐도 돼요', style: AppTextStyles.h3),
        const SizedBox(height: 8),
        TextField(
          controller: _message,
          maxLines: 5,
          maxLength: 500,
          onChanged: (_) => setState(() {}),
        ),
        if (aiWritten) const Text('받는 분께는 "AI가 쓴 안내문"으로 표시돼요.', style: AppTextStyles.caption),
        const Divider(height: 32),
        _autoSwitch(),
      ],
    );
  }

  Widget _progress(Map<String, dynamic> r) {
    final offers = (r['offers'] as List? ?? []).cast<Map<String, dynamic>>();
    final filled = r['status'] == 'filled';
    String label(Map<String, dynamic> o) => switch (o['answer']) {
          'accepted' => '수락 · 확정',
          'declined' => '어려워요',
          'too_late' => '늦게 수락',
          _ => filled ? '마감 안내됨' : '답 기다리는 중',
        };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(filled ? '대체 근무자가 확정됐어요' : '${offers.length}명에게 보냈어요', style: AppTextStyles.h2),
        if (r['isAuto'] == true) ...[
          const SizedBox(height: 4),
          const Text('일주 매니저가 자동으로 보냈어요', style: AppTextStyles.body2),
        ],
        const SizedBox(height: 4),
        Text(filled ? '채팅에서 근무 카드를 확인하세요.' : '먼저 수락한 한 분과 확정되면 알려드려요.', style: AppTextStyles.body2),
        const SizedBox(height: 16),
        ...offers.map((o) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(o['name']?.toString() ?? '알바생', style: AppTextStyles.body1),
              trailing: Text(label(o),
                  style: AppTextStyles.body2.copyWith(
                      color: o['answer'] == 'accepted' ? AppColors.primary : AppColors.textSecondary,
                      fontWeight: o['answer'] == 'accepted' ? FontWeight.w700 : FontWeight.w400)),
            )),
        if (!filled) ...[
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _load, child: const Text('새로고침')),
        ],
        const Divider(height: 32),
        _autoSwitch(),
      ],
    );
  }
}
