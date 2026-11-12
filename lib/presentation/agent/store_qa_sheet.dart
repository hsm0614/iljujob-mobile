import 'dart:convert';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../config/constants.dart';
import '../../data/services/authenticated_http_client.dart';

/// 알바생: 근무 잡힌 매장에 물어보기 — 사장님 매장 안내서에 적힌 것만 AI가 답한다
Future<void> showStoreQaSheet(BuildContext context, int confirmId) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      builder: (_) => _StoreQa(confirmId: confirmId),
    );

class _StoreQa extends StatefulWidget {
  final int confirmId;
  const _StoreQa({required this.confirmId});
  @override
  State<_StoreQa> createState() => _StoreQaState();
}

class _StoreQaState extends State<_StoreQa> {
  final _q = TextEditingController();
  String? _answer;
  bool _asking = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _ask([String? preset]) async {
    final q = (preset ?? _q.text).trim();
    if (q.length < 2) return;
    _q.text = q;
    setState(() => _asking = true);
    try {
      final r = await AuthenticatedHttpClient.postJson(Uri.parse('$baseUrl/api/agent/store-qa'),
          body: {'confirmId': widget.confirmId, 'question': q});
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      _answer = (r.statusCode == 200 ? b['answer'] : b['message'])?.toString();
    } catch (_) {
      _answer = '답을 받지 못했어요. 채팅으로 사장님께 물어보세요.';
    }
    if (mounted) setState(() => _asking = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('매장에 물어보기', style: AppTextStyles.h2),
            const SizedBox(height: 4),
            const Text('사장님이 적어 둔 매장 안내서에서 AI가 찾아 답해요.', style: AppTextStyles.body2),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in const ['어디로 들어가요?', '복장은요?', '준비물 있어요?', '주차 돼요?'])
                ActionChip(label: Text(p), onPressed: _asking ? null : () => _ask(p)),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _q,
              maxLength: 300,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _ask(),
              decoration: InputDecoration(
                hintText: '궁금한 걸 적어 주세요',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(onPressed: _asking ? null : _ask, icon: const Icon(Icons.send_rounded)),
              ),
            ),
            if (_asking) const LinearProgressIndicator(),
            if (_answer != null && !_asking) ...[
              const SizedBox(height: 8),
              Text(_answer!, style: AppTextStyles.body1),
            ],
          ],
        ),
      );
}
