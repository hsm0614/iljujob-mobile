// 가입 직후 한 질문씩 (시안 BQvB3zzVYLBcMNbGP6Kznk 3번).
// 11-02 실측: 희망 일 5% · 요일 5% — 사장님이 지원자를 고를 때 보는데 거의 비어 있었다.
// 예전 화면은 성별 필수 + 세 질문을 한 번에 물었고, 저장 요청이 서버가 받지 않는 키(workerId)라 늘 실패했다.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_theme.dart';
import '../../../config/constants.dart';
import '../../../data/services/authenticated_http_client.dart';
import '../../../widget/app_ui.dart';

class WorkerQuickSetupScreen extends StatefulWidget {
  const WorkerQuickSetupScreen({super.key});
  @override
  State<WorkerQuickSetupScreen> createState() => _WorkerQuickSetupScreenState();
}

class _WorkerQuickSetupScreenState extends State<WorkerQuickSetupScreen> {
  // 값은 프로필 수정 화면(_workCategoryMap)과 같은 낱말 — 실제 저장값 상위권
  static const _works = ['서빙', '주방보조', '카페·바리스타', '포장', '상하차', '물류센터', '매장판매', '행사스태프', '사무보조', '청소'];
  static const _days = ['월', '화', '수', '목', '금', '토', '일'];

  int _step = 0;
  final _pickedWorks = <String>[];
  final _pickedDays = <String>{};
  String? _gender;
  bool _saving = false;

  void _goHome() => Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      final id = (await SharedPreferences.getInstance()).getInt('userId');
      await AuthenticatedHttpClient.postJson(
        Uri.parse('$baseUrl/api/worker/update-profile'),
        body: {
          'id': id,
          if (_pickedWorks.isNotEmpty) 'desired_work': _pickedWorks.join(','),
          if (_pickedDays.isNotEmpty) 'available_days': _days.where(_pickedDays.contains).join(','),
          if (_gender != null) 'gender': _gender,
        },
      );
    } catch (_) {
      // 저장 실패해도 가입은 끝났다 — 마이 탭 완성도 카드가 다시 권한다
    }
    if (mounted) _goHome();
  }

  Widget _chip(String label, bool on, VoidCallback onTap, {double? width}) {
    return SizedBox(
      width: width,
      height: 44,
      child: Material(
        color: on ? AppColors.primary : AppColors.bgCard,
        shape: StadiumBorder(side: on ? BorderSide.none : const BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: width == null ? 16 : 0),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: AppTextStyles.body1.copyWith(
                  color: on ? Colors.white : AppColors.textPrimary,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(String title, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.h2),
          const SizedBox(height: 8),
          Text(sub, style: AppTextStyles.body1.copyWith(color: AppColors.textBody)),
        ],
      );

  Widget _stepWork() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('어떤 일을 하고 싶어요?', '2개까지 고르면 맞는 공고부터 보여 드려요'),
          const SizedBox(height: 28),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in _works)
                _chip(w, _pickedWorks.contains(w), () => setState(() {
                      if (_pickedWorks.remove(w)) return;
                      if (_pickedWorks.length >= 2) _pickedWorks.removeAt(0);
                      _pickedWorks.add(w);
                    })),
            ],
          ),
        ],
      );

  Widget _stepDays() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('언제 일할 수 있어요?', '사장님이 지원자를 고를 때 가장 먼저 봐요'),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final d in _days)
                _chip(d, _pickedDays.contains(d), () => setState(() {
                      if (!_pickedDays.remove(d)) _pickedDays.add(d);
                    }), width: 44),
            ],
          ),
          const SizedBox(height: 36),
          Text('성별 (선택)', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final g in const ['남성', '여성'])
                _chip(g == '남성' ? '남자' : '여자', _gender == g,
                    () => setState(() => _gender = _gender == g ? null : g)),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final last = _step == 1;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step = 0);
      },
      child: Scaffold(
        backgroundColor: AppColors.bgCard,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 20,
          title: Row(
            children: [
              for (var i = 0; i < 2; i++) ...[
                Container(
                  width: 24,
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= _step ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _finish,
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              child: const Text('나중에'),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: _step == 0 ? _stepWork() : _stepDays(),
        ),
        bottomNavigationBar: AppBottomBar(
          child: AppPrimaryButton(
            label: last ? '시작하기' : '다음',
            loading: _saving,
            onPressed: last ? _finish : () => setState(() => _step = 1),
          ),
        ),
      ),
    );
  }
}
