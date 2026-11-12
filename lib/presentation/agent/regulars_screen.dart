import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../data/services/agent_service.dart';

/// 일주 매니저: 단골 재고용 — "지난번 그 친구 또 부를까요?" 사장님이 고른 사람에게만 연락한다
class RegularsScreen extends StatefulWidget {
  final int jobId;
  const RegularsScreen({super.key, required this.jobId});
  @override
  State<RegularsScreen> createState() => _RegularsScreenState();
}

class _RegularsScreenState extends State<RegularsScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;
  final _picked = <int>{};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await RegularsApi.regulars(widget.jobId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _picked
          ..clear()
          ..addAll(rows.where((r) => r['invited'] != true).map((r) => (r['workerId'] as num).toInt()));
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final n = await RegularsApi.invite(widget.jobId, _picked.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n명에게 채팅으로 연락했어요. 답이 오면 알려 드릴게요')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('단골 알바생 다시 부르기')),
      body: _error != null
          ? Center(child: Text(_error!, style: AppTextStyles.body2))
          : rows == null
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('아직 다시 부를 알바생이 없어요.\n채용해서 함께 일한 알바생이 여기에 모여요.',
                            textAlign: TextAlign.center, style: AppTextStyles.body2),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        const Text('전에 함께 일한 알바생이에요. 고른 사람에게 이 공고를 채팅으로 알려요.', style: AppTextStyles.body2),
                        const SizedBox(height: 12),
                        for (final r in rows) _row(r),
                      ],
                    ),
      bottomNavigationBar: rows == null || rows.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: ElevatedButton(
                  onPressed: _picked.isEmpty || _sending ? null : _send,
                  child: Text(_sending ? '보내는 중…' : '${_picked.length}명 다시 부르기'),
                ),
              ),
            ),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final id = (r['workerId'] as num).toInt();
    final invited = r['invited'] == true;
    final last = r['lastDate']?.toString();
    final when = last == null || last.length < 10 ? '' : '${int.parse(last.substring(5, 7))}월 ${int.parse(last.substring(8, 10))}일';
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: invited || _picked.contains(id),
      onChanged: invited ? null : (v) => setState(() => v == true ? _picked.add(id) : _picked.remove(id)),
      title: Text(r['name']?.toString() ?? '알바생', style: AppTextStyles.body1),
      subtitle: Text(
        invited ? '이 공고로 이미 연락했어요' : '함께 일한 공고 ${r['times']}번${when.isEmpty ? '' : ' · 마지막 $when'}',
        style: AppTextStyles.caption,
      ),
    );
  }
}
