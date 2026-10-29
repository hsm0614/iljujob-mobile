import 'dart:convert';
import 'package:iljujob/widget/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../../config/constants.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/utils/pay_display.dart';
import '../../../config/messages.dart';

class SelectPreviousJobScreen extends StatefulWidget {
  const SelectPreviousJobScreen({super.key});

  @override
  State<SelectPreviousJobScreen> createState() =>
      _SelectPreviousJobScreenState();
}

class _SelectPreviousJobScreenState extends State<SelectPreviousJobScreen> {
  // 자체 팔레트를 쓰면 화면 전환 시 배경·텍스트가 미세하게 어긋난다.
  // 디자인 토큰(AppColors)만 사용한다.

  List<dynamic> myJobs = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMyJobs();
  }

  String _s(dynamic v, {String fallback = ''}) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  String _hm(dynamic v) => _s(v, fallback: '');

  Future<void> _fetchMyJobs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getInt('userId');

      if (clientId == null) {
        if (mounted) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text(Msg.loginRequired)));
        }
        return;
      }

      final res = await http.get(
        Uri.parse('$baseUrl/api/job/my-jobs?clientId=$clientId'),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        List<dynamic> jobsList;
        if (data is List) {
          jobsList = data;
        } else if (data is Map && data.containsKey('jobs')) {
          jobsList = (data['jobs'] as List<dynamic>);
        } else if (data is Map && data.containsKey('data')) {
          jobsList = (data['data'] as List<dynamic>);
        } else {
          jobsList = [];
        }

        if (mounted) {
          setState(() {
            myJobs = jobsList;
            isLoading = false;
          });
        }
      } else {
        String msg = '공고 조회 실패';
        try {
          final body = jsonDecode(res.body);
          msg =
              (body is Map && body['message'] != null)
                  ? body['message'].toString()
                  : msg;
        } catch (_) {}
        if (mounted) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(Msg.loadFailed)));
      }
    }
  }

  // 고르면 폼으로 돌려준다 (빠른 등록 시트는 '공고 올리기' 선택 시트와 함께 없앴다, 2026-10)
  void _onJobSelected(dynamic job) => Navigator.pop(context, job);

  DateTime? _date(dynamic v) {
    final s = _s(v);
    return s.length >= 10 ? DateTime.tryParse(s.substring(0, 10)) : null;
  }

  // 파란 테두리 칩·파란 급여 상자(안에 파란 알약)·그림자 카드·파란 화살표 상자 → 흰 목록 한 줄
  Widget _jobCard(dynamic job) {
    final title = _s(job['title'], fallback: '제목 없음');
    final where = [_s(job['location_city']).isNotEmpty ? _s(job['location_city']) : _s(job['location']), _s(job['category'])]
        .where((x) => x.isNotEmpty)
        .join(' · ');
    final days = formatWorkDays(_date(job['start_date']), _date(job['end_date']), _s(job['weekdays']));
    final hours = [_hm(job['start_time']), _hm(job['end_time'])].where((x) => x.isNotEmpty).join(' ~ ');
    final when = [if (days != null) days, if (hours.isNotEmpty) hours].join(' · ');
    final pay = formatJobPay(_s(job['pay']), _s(job['pay_type']), includeType: true);

    return InkWell(
      onTap: () => _onJobSelected(job),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [pay, if (when.isNotEmpty) when].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body2,
                  ),
                  if (where.isNotEmpty)
                    Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body2),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AppBar(title: const Text('지난 공고로 채우기')),
      body:
          isLoading
              ? const AppSkeletonList()
              : myJobs.isEmpty
              ? AppEmptyState(
                icon: Icons.work_outline,
                title: '아직 올린 공고가 없어요',
                message: '공고를 올리면 여기서 불러와 다시 쓸 수 있어요',
                actionLabel: '닫기',
                onAction: () => Navigator.pop(context),
                secondaryAction: true,
              )
              : ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text('고르면 내용을 채워 드려요 · 날짜는 다시 골라 주세요', style: AppTextStyles.body2),
                  ),
                  Container(
                    color: AppColors.bgCard,
                    child: Column(children: [for (final j in myJobs) _jobCard(j)]),
                  ),
                ],
              ),
    );
  }
}
