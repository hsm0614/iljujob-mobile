import 'dart:convert';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../config/constants.dart';
import '../../data/services/authenticated_http_client.dart';
import '../../data/services/vacancy_service.dart';

/// 사장님: AI 일주 매니저 — 매니저가 대신 하는 일 한눈에 + 자동 대타 + 매장 안내서
class AiManagerScreen extends StatefulWidget {
  const AiManagerScreen({super.key});
  @override
  State<AiManagerScreen> createState() => _AiManagerScreenState();
}

class _AiManagerScreenState extends State<AiManagerScreen> {
  bool? _auto;
  final _manual = TextEditingController();
  bool _saving = false;
  String _savedManual = '';

  @override
  void initState() {
    super.initState();
    VacancyService.autoVacancy().then((v) => mounted ? setState(() => _auto = v) : null).catchError((_) {});
    AuthenticatedHttpClient.get(Uri.parse('$baseUrl/api/agent/manual')).then((r) {
      if (r.statusCode != 200 || !mounted) return;
      _savedManual = (jsonDecode(r.body) as Map)['manual']?.toString() ?? '';
      setState(() => _manual.text = _savedManual);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _saveManual() async {
    setState(() => _saving = true);
    var ok = false;
    try {
      final r = await AuthenticatedHttpClient.putJson(Uri.parse('$baseUrl/api/agent/manual'), body: {'manual': _manual.text.trim()});
      ok = r.statusCode == 200;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _savedManual = _manual.text.trim();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '저장했어요. 첫 출근 브리핑과 알바생 질문에 써요' : '저장하지 못했어요')));
  }

  static const _jobs = [
    ('사진 한 장으로 공고', '전단·메모를 찍으면 공고 칸을 채워요'),
    ('지원 없으면 공고 살리기', '원인을 찾아 고친 안을 보여 줘요'),
    ('지원자 첫 응대', '유료 공고에서 가능 시간·경험을 대신 물어요'),
    ('근로계약서', '출근 제안에 붙이면 서명·교부까지'),
    ('첫 출근 전날 브리핑', '시간·장소·복장·준비물을 알바생에게'),
    ('자동 대타', '알바생이 취소하면 바로 후보에게 연락'),
    ('단골 다시 부르기', '전에 함께한 알바생을 한 번에'),
    ('먼저 제안', '평소 알바 쓰는 날 전에 미리 물어봐요'),
    ('채팅 번역', '외국인 알바생 메시지를 길게 눌러 번역'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('AI 일주 매니저')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const Text('공고부터 출근까지, AI 매니저가 대신 챙겨요', style: AppTextStyles.h2),
            const SizedBox(height: 6),
            const Text('채용 확정·돈이 드는 일은 사장님이 마지막에 정해요.', style: AppTextStyles.body2),
            const SizedBox(height: 20),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _auto ?? false,
              onChanged: _auto == null
                  ? null
                  : (v) async {
                      setState(() => _auto = v);
                      await VacancyService.setAutoVacancy(v).catchError((_) {
                        if (mounted) setState(() => _auto = !v);
                      });
                    },
              title: const Text('자동 대타', style: AppTextStyles.body1),
              subtitle: const Text('알바생이 근무를 취소하면 AI가 바로 후보 5명에게 연락해요', style: AppTextStyles.caption),
            ),
            const Divider(height: 32, color: AppColors.border),
            const Text('매장 안내서', style: AppTextStyles.h3),
            const SizedBox(height: 4),
            const Text('출입 방법·복장·준비물·주차·누구를 찾으면 되는지 적어 두세요. 첫 출근 브리핑에 들어가고, 알바생이 물으면 AI가 여기 적힌 것만 답해요.',
                style: AppTextStyles.body2),
            const SizedBox(height: 10),
            TextField(
              controller: _manual,
              minLines: 5,
              maxLines: 12,
              maxLength: 3000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '예) 후문으로 들어와서 주방 김실장님 찾기 / 검은 바지·운동화 / 앞치마는 매장에서 드려요 / 주차는 건물 지하 1시간 무료',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving || _manual.text.trim() == _savedManual ? null : _saveManual,
                child: Text(_saving ? '저장 중…' : '안내서 저장'),
              ),
            ),
            const Divider(height: 40, color: AppColors.border),
            const Text('AI 매니저가 하는 일', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            for (final (t, d) in _jobs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_rounded, size: 18, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Text(t, style: AppTextStyles.body1), Text(d, style: AppTextStyles.caption)],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}
