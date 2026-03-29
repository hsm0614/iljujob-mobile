import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../../config/constants.dart';
import 'quick_post_sheet.dart'; // ✅ 추가

class SelectPreviousJobScreen extends StatefulWidget {
  // ✅ quickMode 파라미터 추가
  // true  → 공고 선택 시 QuickPostSheet 바로 오픈
  // false → 기존처럼 Navigator.pop(context, job) 으로 폼에 데이터 전달
  final bool quickMode;

  const SelectPreviousJobScreen({
    super.key,
    this.quickMode = false, // 기본값 false → 기존 동작 그대로
  });

  @override
  State<SelectPreviousJobScreen> createState() => _SelectPreviousJobScreenState();
}

class _SelectPreviousJobScreenState extends State<SelectPreviousJobScreen> {
  // ===== Brand (알바일주 톤) =====
  static const Color brandBlue = Color(0xFF3B8AFF);
  static const Color brandBlueDark = Color(0xFF1675F4);
  static const Color bg = Color(0xFFF6F8FC);
  static const Color textDark = Color(0xFF0C1F35);
  static const Color textMute = Color(0xFF7A8596);
  static const Color border = Color(0xFFE7ECF3);

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

  String _payTypeKo(dynamic v) {
    final s = (v ?? '').toString().toLowerCase().trim();
    if (s == 'daily' || s == '일급') return '일급';
    if (s == 'weekly' || s == '주급') return '주급';
    return '급여';
  }

  String _ymd(dynamic v) => _s(v, fallback: '');
  String _hm(dynamic v) => _s(v, fallback: '');

  Future<void> _fetchMyJobs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getInt('userId');

      if (clientId == null) {
        if (mounted) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('로그인 정보를 불러올 수 없습니다.')),
          );
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
          msg = (body is Map && body['message'] != null) ? body['message'].toString() : msg;
        } catch (_) {}
        if (mounted) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ $msg')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류 발생: ${e.toString()}')),
        );
      }
    }
  }

  // ✅ 공고 선택 시 분기 처리
  void _onJobSelected(dynamic job) {
    if (widget.quickMode) {
      // 빠른 등록: 이 화면을 닫고 QuickPostSheet 오픈
      Navigator.pop(context); // SelectPreviousJobScreen 닫기
      QuickPostSheet.show(
        context,
        job: Map<String, dynamic>.from(job as Map),
      );
    } else {
      // 기존 동작: 폼에 데이터 전달
      Navigator.pop(context, job);
    }
  }

  Widget _chip({
    required String text,
    Color? bgColor,
    Color? fgColor,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor ?? const Color(0xFFEFF5FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDCEAFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fgColor ?? brandBlueDark),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fgColor ?? brandBlueDark,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF5FF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFDCEAFF)),
              ),
              child: const Icon(Icons.work_outline, color: brandBlueDark, size: 32),
            ),
            const SizedBox(height: 14),
            const Text('작성한 공고가 없습니다', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textDark)),
            const SizedBox(height: 6),
            const Text('공고를 작성하면 여기에서\n이전 공고를 바로 불러올 수 있어요.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.4, color: textMute)),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: brandBlueDark,
                side: const BorderSide(color: Color(0xFFDCEAFF)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobCard(dynamic job) {
    final title = _s(job['title'], fallback: '제목 없음');
    final location = _s(job['location'], fallback: '지역 없음');
    final category = _s(job['category'], fallback: '카테고리 없음');
    final startDate = _ymd(job['start_date']);
    final endDate = _ymd(job['end_date']);
    final startTime = _hm(job['start_time']);
    final endTime = _hm(job['end_time']);
    final payType = _payTypeKo(job['pay_type']);
    final pay = _s(job['pay'], fallback: '');
    final isSameDayPay = (job['is_same_day_pay'] == 1 || job['is_same_day_pay'] == true);
    final dateText = (startDate.isEmpty && endDate.isEmpty) ? '날짜 정보 없음' : '$startDate ~ $endDate';
    final timeText = (startTime.isEmpty && endTime.isEmpty) ? '시간 정보 없음' : '$startTime ~ $endTime';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _onJobSelected(job), // ✅ 변경된 부분 (기존: Navigator.pop(context, job))
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
            boxShadow: const [
              BoxShadow(color: Color(0x0F0C1F35), blurRadius: 18, offset: Offset(0, 10)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단: 타이틀 + 아이콘
                Row(children: [
                  Expanded(
                    child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textDark, height: 1.15)),
                  ),
                  const SizedBox(width: 10),
                  // ✅ quickMode일 때 아이콘 다르게
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: widget.quickMode ? const Color(0xFFEEF5FF) : const Color(0xFFEFF5FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFDCEAFF)),
                    ),
                    child: Icon(
                      widget.quickMode ? Icons.flash_on_rounded : Icons.arrow_forward_ios_rounded,
                      size: 16, color: brandBlueDark,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),

                // 칩들
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _chip(text: location, icon: Icons.place_outlined),
                  _chip(text: category, icon: Icons.category_outlined),
                  if (isSameDayPay) _chip(text: '당일지급', bgColor: const Color(0xFFFFF4E5), fgColor: const Color(0xFFB25E00), icon: Icons.flash_on_outlined),
                ]),

                const SizedBox(height: 12),
                Container(height: 1, color: border),
                const SizedBox(height: 12),

                // 날짜/시간
                Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 16, color: textMute),
                  const SizedBox(width: 8),
                  Expanded(child: Text(dateText, style: const TextStyle(fontSize: 13, color: textMute, fontWeight: FontWeight.w600))),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.schedule_outlined, size: 16, color: textMute),
                  const SizedBox(width: 8),
                  Expanded(child: Text(timeText, style: const TextStyle(fontSize: 13, color: textMute, fontWeight: FontWeight.w600))),
                ]),
                const SizedBox(height: 12),

                // 급여
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFFEFF5FF), Color(0xFFFFFFFF)]),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDCEAFF)),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: brandBlue, borderRadius: BorderRadius.circular(999)),
                      child: Text(payType, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, height: 1.0)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(pay.isEmpty ? '급여 정보 없음' : '$pay원', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: textDark))),
                    Icon(
                      widget.quickMode ? Icons.bolt_rounded : Icons.touch_app_outlined,
                      size: 18, color: brandBlueDark,
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        centerTitle: false,
        // ✅ quickMode일 때 타이틀 다르게
        title: Text(
          widget.quickMode ? '⚡ 빠른 등록 · 공고 선택' : '기존 공고 선택',
          style: const TextStyle(color: textDark, fontWeight: FontWeight.w900),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // ✅ quickMode일 때 안내 배너 추가
      body: Column(
        children: [
          if (widget.quickMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFEEF5FF),
              child: const Row(children: [
                Icon(Icons.info_outline, size: 14, color: Color(0xFF3182F6)),
                SizedBox(width: 6),
                Text('공고를 선택하면 날짜·급여만 바꿔서 바로 등록할 수 있어요',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF3182F6))),
              ]),
            ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : myJobs.isEmpty
                    ? _emptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        itemCount: myJobs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, index) => _jobCard(myJobs[index]),
                      ),
          ),
        ],
      ),
    );
  }
}