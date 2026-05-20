import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:table_calendar/table_calendar.dart';
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/data/services/job_service.dart';

// ════════════════════════════════════════════════════════
//  디자인 토큰 (post_job_form.dart와 동일)
// ════════════════════════════════════════════════════════
const _blue = AppColors.primary;
const _bg = AppColors.bgPage;
const _border = AppColors.border;
const _label = AppColors.textTertiary;
const _text = AppColors.textPrimary;
const _sub = AppColors.textSecondary;
const int _minWage = 10320;

// ════════════════════════════════════════════════════════
//  QuickPostSheet — 진입점
//
//  사용법:
//    QuickPostSheet.show(context, job: selectedJob);
//
//  job은 SelectPreviousJobScreen에서 받은 Map<String, dynamic>
// ════════════════════════════════════════════════════════
class QuickPostSheet extends StatelessWidget {
  final Map<String, dynamic> job;
  const QuickPostSheet({super.key, required this.job});

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> job,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickPostSheet(job: job),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _QuickPostSheetBody(job: job);
  }
}

// ════════════════════════════════════════════════════════
//  내부 State
// ════════════════════════════════════════════════════════
class _QuickPostSheetBody extends StatefulWidget {
  final Map<String, dynamic> job;
  const _QuickPostSheetBody({required this.job});

  @override
  State<_QuickPostSheetBody> createState() => _QuickPostSheetBodyState();
}

class _QuickPostSheetBodyState extends State<_QuickPostSheetBody> {
  final _fmt = NumberFormat('#,###');
  final _df = DateFormat('yyyy.MM.dd (E)', 'ko_KR');
  final _dfShort = DateFormat('M/d(E)', 'ko_KR');

  // ─── 수정 가능한 3개 항목 ───
  DateTime? startDate;
  DateTime? endDate;
  late int pay;
  late String payType;

  // ─── 읽기 전용 (표시용) ───
  late String title;
  late String location;
  late String category;
  late String startTime;
  late String endTime;
  late bool isSameDayPay;

  // ─── 상태 ───
  bool _isSubmitting = false;
  String? _payWarning;
  int _freeRemaining = 0;
  int _freeLimit = 2;
  int _paidPassCount = 0;
  bool _passLoading = false;

  final _payCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final j = widget.job;

    title = j['title'] ?? '';
    location = j['location'] ?? '';
    category = j['category'] ?? '';
    startTime = j['start_time'] ?? '';
    endTime = j['end_time'] ?? '';
    payType = j['pay_type'] ?? '일급';
    isSameDayPay = j['is_same_day_pay'] == 1;

    // 날짜는 오늘부터 새로 (재등록이니까)
    final today = DateTime.now();
    startDate = today;
    endDate = today;

    // 급여는 기존 값 그대로
    pay = int.tryParse(j['pay']?.toString() ?? '') ?? 0;
    _payCtrl.text = pay > 0 ? _fmt.format(pay) : '';

    _loadCounts();
  }

  @override
  void dispose() {
    _payCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    setState(() => _passLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getInt('userId');
      final token = prefs.getString('authToken') ?? '';
      if (clientId == null) return;

      // 무료 잔여
      final freeRes = await http.get(
        Uri.parse('$baseUrl/api/job/free-post-usage?clientId=$clientId'),
        headers: {'Cache-Control': 'no-cache'},
      );
      if (freeRes.statusCode == 200) {
        final d = jsonDecode(freeRes.body);
        if (mounted)
          setState(() {
            _freeLimit = (d['limit'] ?? 5) as int;
            _freeRemaining = (d['remaining'] ?? 0) as int;
          });
      }

      // 이용권 잔여
      final passRes = await http.get(
        Uri.parse('$baseUrl/api/pass/remain?clientId=$clientId'),
        headers: {if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
      );
      if (passRes.statusCode == 200) {
        final d = jsonDecode(utf8.decode(passRes.bodyBytes));
        final remain =
            int.tryParse('${d['remaining'] ?? d['remain'] ?? 0}') ?? 0;
        if (mounted) setState(() => _paidPassCount = remain);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _passLoading = false);
    }
  }

  // ─── 날짜 피커 ───
  void _pickDate({required bool isStart}) {
    final today = DateTime.now();
    final minDate = isStart ? today : (startDate ?? today);
    DateTime selected = isStart ? (startDate ?? today) : (endDate ?? minDate);
    if (selected.isBefore(minDate)) selected = minDate;
    DateTime focused = selected;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => StatefulBuilder(
            builder: (ctx, set) {
              final safePad = MediaQuery.of(ctx).padding.bottom;
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Column(
                          children: [
                            Text(
                              isStart ? '시작일 선택' : '종료일 선택',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TableCalendar(
                              locale: 'ko_KR',
                              focusedDay: focused,
                              firstDay: minDate,
                              lastDay: today.add(const Duration(days: 365)),
                              selectedDayPredicate:
                                  (d) => isSameDay(d, selected),
                              onDaySelected:
                                  (d, f) => set(() {
                                    selected = DateTime(d.year, d.month, d.day);
                                    focused = d;
                                  }),
                              onPageChanged: (f) => set(() => focused = f),
                              calendarStyle: const CalendarStyle(
                                todayDecoration: BoxDecoration(
                                  color: _blue,
                                  shape: BoxShape.circle,
                                ),
                                selectedDecoration: BoxDecoration(
                                  color: const Color(0xFF191F28),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              headerStyle: const HeaderStyle(
                                formatButtonVisible: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      minimum: EdgeInsets.fromLTRB(16, 8, 16, safePad + 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              if (isStart) {
                                startDate = selected;
                                if (endDate != null &&
                                    endDate!.isBefore(selected))
                                  endDate = selected;
                              } else {
                                endDate = selected;
                              }
                            });
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '선택 완료',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }

  // ─── 급여 검증 ───
  void _validatePay() {
    if (pay <= 0) {
      setState(() => _payWarning = null);
      return;
    }
    // 시간 정보 없으면 스킵
    if (startTime.isEmpty || endTime.isEmpty) {
      setState(() => _payWarning = null);
      return;
    }
    final sParts = startTime.split(':');
    final eParts = endTime.split(':');
    if (sParts.length < 2 || eParts.length < 2) {
      setState(() => _payWarning = null);
      return;
    }
    final sMin = int.parse(sParts[0]) * 60 + int.parse(sParts[1]);
    final eMin = int.parse(eParts[0]) * 60 + int.parse(eParts[1]);
    int diff = eMin - sMin;
    if (diff <= 0) diff += 24 * 60;
    final hours = diff / 60.0;
    final required = (_minWage * hours).ceil();
    setState(
      () =>
          _payWarning =
              pay >= required
                  ? null
                  : '💰 최저시급 미달 · 최소 ${_fmt.format(required)}원 이상',
    );
  }

  // ─── 등록 실행 ───
  Future<void> _submit({required bool isPaid}) async {
    if (startDate == null || endDate == null) {
      _showSnack('날짜를 선택해주세요');
      return;
    }
    if (pay <= 0) {
      _showSnack('급여를 입력해주세요');
      return;
    }
    if (_payWarning != null) {
      _showSnack(_payWarning!);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getInt('userId')!;
      final userType = prefs.getString('userType') ?? '';
      final j = widget.job;

      await JobService.postJobWithImages(
        title: j['title'] ?? '',
        category: j['category'] ?? '',
        location: j['location'] ?? '',
        locationCity: j['location_city'] ?? '',
        startDate: startDate!.toIso8601String().split('T')[0],
        endDate: endDate!.toIso8601String().split('T')[0],
        startTime: j['start_time'] ?? '',
        endTime: j['end_time'] ?? '',
        payType: payType,
        pay: pay,
        description: j['description'] ?? '',
        images: [], // 재등록이므로 이미지는 기존 URL만 (서버측에서 복사 처리 필요 시 별도 대응)
        clientId: clientId,
        weekdays: j['weekdays'],
        lat: (j['lat'] ?? 0.0).toDouble(),
        lng: (j['lng'] ?? 0.0).toDouble(),
        isScheduled: false,
        publishAt: null,
        isSameDayPay: j['is_same_day_pay'] == 1,
        isPaid: isPaid,
        isAgency: clientId == 1,
      );

      if (!mounted) return;
      Navigator.pop(context); // 시트 닫기
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('공고 등록 완료 🎉'),
          backgroundColor: Colors.green,
        ),
      );

      // 화면 이동
      if (userType == 'client')
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/client_main',
          (_) => false,
        );
      else
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } catch (e) {
      if (mounted) _showSnack('오류: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── 등록 방식 선택 ───
  void _showPublishOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final safePad = MediaQuery.of(ctx).padding.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, safePad + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '등록 방식 선택',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _blue,
                ),
              ),
              const SizedBox(height: 20),

              // 무료
              _OptionCard(
                emoji: '💸',
                title: '무료 등록',
                desc: '24시간 노출',
                badge: '$_freeRemaining/$_freeLimit',
                badgeOk: _freeRemaining > 0,
                onTap: () {
                  Navigator.pop(ctx);
                  if (_freeRemaining <= 0) {
                    _showSnack('이번 달 무료 한도를 모두 사용했어요');
                    return;
                  }
                  _submit(isPaid: false);
                },
              ),
              const SizedBox(height: 12),

              // 부스터
              _OptionCard(
                emoji: '🚀',
                title: '부스터 모드',
                desc: '72시간 · 푸시 · 상단 고정',
                badge: _passLoading ? '조회중…' : '보유 $_paidPassCount개',
                badgeOk: _paidPassCount > 0,
                onTap: () {
                  Navigator.pop(ctx);
                  if (_paidPassCount <= 0) {
                    _showSnack('이용권이 없습니다');
                    return;
                  }
                  _submit(isPaid: true);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final safePad = MediaQuery.of(context).padding.bottom;
    final kbPad = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = (kbPad > 0 ? kbPad : safePad) + 16;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        builder:
            (_, sc) => Column(
              children: [
                // ─ 핸들 ─
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ─ 헤더 ─
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '⚡ 빠른 등록',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _blue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '날짜·급여만 바꾸고 바로 등록',
                          style: TextStyle(
                            fontSize: 13,
                            color: _label,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ─ 본문 스크롤 ─
                Expanded(
                  child: SingleChildScrollView(
                    controller: sc,
                    padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 공고 미리보기 카드 ──
                        _JobSummaryCard(
                          title: title,
                          category: category,
                          location: location,
                          startTime: startTime,
                          endTime: endTime,
                          isSameDayPay: isSameDayPay,
                        ),
                        const SizedBox(height: 20),

                        // ── 날짜 수정 ──
                        _SectionTitle(
                          icon: Icons.calendar_today_rounded,
                          label: '근무 날짜',
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _DateTile(
                                label: '시작일',
                                value:
                                    startDate != null
                                        ? _df.format(startDate!)
                                        : null,
                                onTap: () => _pickDate(isStart: true),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                '→',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: _label.withOpacity(0.6),
                                ),
                              ),
                            ),
                            Expanded(
                              child: _DateTile(
                                label: '종료일',
                                value:
                                    endDate != null
                                        ? _df.format(endDate!)
                                        : null,
                                onTap: () => _pickDate(isStart: false),
                              ),
                            ),
                          ],
                        ),

                        // 날짜 범위 요약
                        if (startDate != null && endDate != null) ...[
                          const SizedBox(height: 8),
                          _DateRangeSummary(
                            start: startDate!,
                            end: endDate!,
                            dfShort: _dfShort,
                          ),
                        ],

                        const SizedBox(height: 24),

                        // ── 급여 수정 ──
                        _SectionTitle(
                          icon: Icons.payments_rounded,
                          label: '급여',
                        ),
                        const SizedBox(height: 10),

                        // 급여 타입 선택
                        Row(
                          children:
                              ['일급', '주급'].map((t) {
                                final sel = payType == t;
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: t == '일급' ? 8 : 0,
                                    ),
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() => payType = t);
                                        _validatePay();
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: sel ? _blue : _bg,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: sel ? _blue : _border,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            t,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: sel ? Colors.white : _sub,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 10),

                        // 급여 입력
                        TextFormField(
                          controller: _payCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: _text,
                          ),
                          decoration: InputDecoration(
                            hintText: '0',
                            hintStyle: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _border,
                            ),
                            suffixText: '원',
                            suffixStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _label,
                            ),
                            filled: true,
                            fillColor: _bg,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color:
                                    _payWarning != null ? Colors.red : _border,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: _payWarning != null ? Colors.red : _blue,
                                width: 1.5,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onChanged: (v) {
                            final num = v.replaceAll(RegExp(r'[^0-9]'), '');
                            final parsed = num.isEmpty ? 0 : int.parse(num);
                            setState(() => pay = parsed);
                            _validatePay();
                            final formatted =
                                num.isEmpty ? '' : _fmt.format(parsed);
                            if (_payCtrl.text != formatted) {
                              _payCtrl.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                  offset: formatted.length,
                                ),
                              );
                            }
                          },
                        ),

                        if (_payWarning != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3F0),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  '⚠️',
                                  style: TextStyle(fontSize: 13),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _payWarning!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 13,
                              color: _label,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '2026년 최저시급 ${_fmt.format(_minWage)}원',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _label,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),

                // ─ 하단 버튼 ─
                _BottomButtons(
                  isSubmitting: _isSubmitting,
                  canSubmit:
                      startDate != null &&
                      endDate != null &&
                      pay > 0 &&
                      _payWarning == null,
                  onTap: _showPublishOptions,
                ),
              ],
            ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
//  서브 위젯들
// ════════════════════════════════════════════════════════

class _JobSummaryCard extends StatelessWidget {
  final String title, category, location, startTime, endTime;
  final bool isSameDayPay;
  const _JobSummaryCard({
    required this.title,
    required this.category,
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.isSameDayPay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목 + 카테고리
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  category,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: _border, height: 1),
          const SizedBox(height: 10),

          // 정보 그리드
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _InfoChip(icon: Icons.location_on_rounded, label: location),
              if (startTime.isNotEmpty && endTime.isNotEmpty)
                _InfoChip(
                  icon: Icons.access_time_rounded,
                  label: '$startTime ~ $endTime',
                ),
              if (isSameDayPay)
                _InfoChip(
                  icon: Icons.attach_money_rounded,
                  label: '당일지급',
                  color: Colors.green,
                ),
            ],
          ),

          // 재사용 안내
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 14,
                color: _blue.withOpacity(0.7),
              ),
              const SizedBox(width: 4),
              const Text(
                '위 정보를 그대로 재사용해요',
                style: TextStyle(
                  fontSize: 11,
                  color: _label,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _InfoChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: color ?? _label),
      const SizedBox(width: 3),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color ?? _sub,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

class _DateRangeSummary extends StatelessWidget {
  final DateTime start, end;
  final DateFormat dfShort;
  const _DateRangeSummary({
    required this.start,
    required this.end,
    required this.dfShort,
  });

  @override
  Widget build(BuildContext context) {
    final days = end.difference(start).inDays + 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range_rounded, size: 15, color: _blue),
          const SizedBox(width: 6),
          Text(
            '${dfShort.format(start)} ~ ${dfShort.format(end)}  ·  총 $days일',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _sub,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: _blue),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: _text,
        ),
      ),
    ],
  );
}

class _DateTile extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: value != null ? const Color(0xFFEEF5FF) : _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value != null ? _blue : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: value != null ? _blue : _label,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value ?? '선택',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: value != null ? _text : _label,
            ),
          ),
        ],
      ),
    ),
  );
}

class _OptionCard extends StatelessWidget {
  final String emoji, title, desc, badge;
  final bool badgeOk;
  final VoidCallback onTap;
  const _OptionCard({
    required this.emoji,
    required this.title,
    required this.desc,
    required this.badge,
    required this.badgeOk,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 12, color: _label)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (badgeOk ? _blue : Colors.red).withOpacity(0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: badgeOk ? _blue : Colors.red),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: badgeOk ? _blue : Colors.red,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BottomButtons extends StatelessWidget {
  final bool isSubmitting, canSubmit;
  final VoidCallback onTap;
  const _BottomButtons({
    required this.isSubmitting,
    required this.canSubmit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: (isSubmitting || !canSubmit) ? null : onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: canSubmit ? _blue : _border,
              foregroundColor: canSubmit ? Colors.white : _label,
              elevation: canSubmit ? 2 : 0,
              shadowColor: _blue.withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child:
                isSubmitting
                    ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                    : const Text(
                      '등록 방식 선택 →',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
          ),
        ),
      ),
    );
  }
}
