import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kpostal/kpostal.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_time_picker_spinner/flutter_time_picker_spinner.dart';

import 'package:iljujob/data/services/job_service.dart';

/// ------------------------------------------------------------
/// Time helpers (UTC/KST-safe, self-contained for this screen)
/// ------------------------------------------------------------
class _Tx {
  static final _ymd = DateFormat('yyyy-MM-dd');
  static final _hm = DateFormat('HH:mm');

  /// 문자열을 UTC DateTime으로 파싱
  static DateTime? parseUtcFlexible(dynamic v) {
    if (v == null) return null;
    final s0 = v.toString().trim();
    if (s0.isEmpty) return null;

    // epoch (sec/ms)
    if (RegExp(r'^\d+$').hasMatch(s0)) {
      final n = int.tryParse(s0);
      if (n == null) return null;
      final isMs = s0.length >= 13;
      final dt = isMs
          ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
      return dt.toUtc();
    }

    // ISO with Z/offset
    if (RegExp(r'(?:[zZ]|[+\-]\d{2}:\d{2})$').hasMatch(s0)) {
      return DateTime.tryParse(s0)?.toUtc();
    }

    // plain -> assume UTC (Z)
    final base = s0.contains('T') ? s0 : s0.replaceFirst(' ', 'T');
    return DateTime.tryParse('${base}Z')?.toUtc();
  }

  /// UTC -> KST
  static DateTime? toKst(DateTime? utc) => utc?.toUtc().add(const Duration(hours: 9));

  /// UTC -> yyyy-MM-dd(KST 기준)
  static String utcToKstYmd(DateTime? utc) {
    final k = toKst(utc);
    return (k == null) ? '' : _ymd.format(k);
  }

  /// yyyy-MM-dd(KST 의미) + HH:mm -> UTC
  static DateTime? buildUtcFromKst(String? ymd, String? hhmm) {
    if (ymd == null || ymd.isEmpty || hhmm == null || hhmm.isEmpty) return null;
    final ym = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(ymd);
    final tm = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hhmm);
    if (ym == null || tm == null) return null;
    final y = int.parse(ym.group(1)!);
    final mo = int.parse(ym.group(2)!);
    final d = int.parse(ym.group(3)!);
    final h = int.parse(tm.group(1)!);
    final m = int.parse(tm.group(2)!);
    // KST 시각을 만든 뒤 9시간 빼서 UTC로
    return DateTime.utc(y, mo, d, h, m).subtract(const Duration(hours: 9));
  }

  /// UI 표기
  static String formatKstDate(DateTime? utc) => utc == null ? '' : _ymd.format(toKst(utc)!);
  static String formatKstTime(DateTime? utc) => utc == null ? '' : _hm.format(toKst(utc)!);

  /// TimeOfDay <-> "HH:mm"
  static String fmtHmOf(TimeOfDay? t) =>
      t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay? parseHm(String? s) {
    if (s == null || s.isEmpty) return null;
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final n = int.tryParse(m.group(2)!);
    if (h == null || n == null) return null;
    return TimeOfDay(hour: h, minute: n);
  }
}

/// ------------------------------------------------------------
/// Screen
/// ------------------------------------------------------------
class EditJobScreen extends StatefulWidget {
  const EditJobScreen({super.key});

  @override
  State<EditJobScreen> createState() => _EditJobScreenState();
}

class _EditJobScreenState extends State<EditJobScreen> {
  // ===== Brand =====
  static const Color brandBlue = Color(0xFF3B8AFF);
  static const Color cardBg = Color(0xFFF7F9FF);
  static const int minWagePerHour = 10030; // 2025 기준

  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();

  // Controllers
  final _title = TextEditingController();
  final _pay = TextEditingController();
  final _desc = TextEditingController();
  final _location = TextEditingController();

  // Field Keys (스크롤 에러 이동용)
  final _titleKey = GlobalKey();
  final _locationKey = GlobalKey();
  final _payKey = GlobalKey();

  // State
  String jobId = '';
  bool isLoading = true;

  String category = '제조';
  String payType = '일급';
  String location = '';

  // Short-term (date-only) vs weekdays
  bool isShortTerm = true;
  final List<String> weekdays = const ['월', '화', '수', '목', '금', '토', '일'];
  List<String> selectedWeekdays = [];

  // Date-only semantics (KST midnight stored in UTC)
  DateTime? startDateUtc;
  DateTime? endDateUtc;

  // Time of day (HH:mm)
  TimeOfDay? startTime;
  TimeOfDay? endTime;

  // Images
  List<File> newImages = [];
  List<String> existingImageUrls = [];
  final Set<String> _toDeleteUrls = {};

  // Pay warning
  String? _payWarning;

  // Formatters
  final _moneyFmt = NumberFormat('#,###');

  @override
  void dispose() {
    _scroll.dispose();
    _title.dispose();
    _pay.dispose();
    _desc.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args == null) {
        if (mounted) Navigator.pop(context);
        return;
      }
      jobId = args as String;
      await _load();
    });
  }

  // ===================== Load =====================
  Future<void> _load() async {
    try {
      final job = await JobService.fetchJobById(jobId);

      setState(() {
        _title.text = (job.title ?? '').toString();
        _pay.text = (job.pay ?? '').toString();
        _desc.text = (job.description ?? '').toString();

        category = (job.category ?? '제조').toString();
        payType = (job.payType ?? '일급').toString();

        location = (job.location ?? '').toString();
        _location.text = location;

        // Short-term vs weekdays (weekdays field can be String or null)
        final wdRaw = (job.weekdays ?? '').toString();
        isShortTerm = wdRaw.trim().isEmpty;
        selectedWeekdays = wdRaw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        // Date-only (server sent UTC representing KST 00:00)
        startDateUtc = job.startDate;
        endDateUtc = job.endDate;

        // Times (HH:mm strings)
        startTime = _Tx.parseHm(job.startTime);
        endTime = _Tx.parseHm(job.endTime);

        existingImageUrls = job.imageUrls ?? [];
        isLoading = false;
      });

      _formatPayInput();
      _validatePay();
    } catch (e) {
      debugPrint('❌ 공고 불러오기 실패: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  // ===================== Images =====================
  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedList = await picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (pickedList.isNotEmpty) {
      setState(() {
        newImages.addAll(pickedList.map((x) => File(x.path)));
        if (newImages.length > 10) newImages = newImages.sublist(0, 10);
      });
    }
  }

  // ===================== Date Helpers (PostJob 스타일) =====================
  DateTime get _today0 {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _d0(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _clampDate(DateTime d, DateTime min, DateTime max) {
    if (d.isBefore(min)) return min;
    if (d.isAfter(max)) return max;
    return d;
  }

  void _showDatePickerBottomSheet({
    required DateTime? initialDateKst,
    DateTime? minDateKst,
    DateTime? maxDateKst,
    required void Function(DateTime pickedKst0) onSelected,
  }) {
    final first = _d0(minDateKst ?? _today0);
    final last = _d0(maxDateKst ?? _today0.add(const Duration(days: 365)));

    DateTime selectedDate = _clampDate(
      _d0(initialDateKst ?? _today0),
      first,
      last,
    );
    DateTime focusedDay = selectedDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final safePad = MediaQuery.of(context).padding.bottom;
            final kbPad = MediaQuery.of(context).viewInsets.bottom;
            final bottomPad = (kbPad > 0 ? kbPad : safePad) + 8;

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8 - safePad,
              ),
              child: Column(
                children: [
                  // 핸들 + 타이틀
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '날짜 선택',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: TableCalendar(
                        locale: 'ko_KR',
                        focusedDay: focusedDay,
                        firstDay: first,
                        lastDay: last,
                        selectedDayPredicate: (day) => isSameDay(day, selectedDate),
                        onDaySelected: (day, f) {
                          setModalState(() {
                            selectedDate = _d0(day);
                            focusedDay = day;
                          });
                        },
                        onPageChanged: (f) => setModalState(() => focusedDay = f),
                        headerStyle: const HeaderStyle(formatButtonVisible: false),
                        calendarStyle: const CalendarStyle(
                          todayDecoration: BoxDecoration(
                            color: brandBlue,
                            shape: BoxShape.circle,
                          ),
                          selectedDecoration: BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),

                  SafeArea(
                    top: false,
                    minimum: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          onSelected(selectedDate);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          '선택 완료',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openStartDatePicker() {
    final min = _today0;
    final max = _today0.add(const Duration(days: 365));
    final currentKst = _Tx.toKst(startDateUtc) ?? _today0;

    _showDatePickerBottomSheet(
      initialDateKst: currentKst,
      minDateKst: min,
      maxDateKst: max,
      onSelected: (pickedKst0) {
        // KST 00:00 의미 -> UTC로 저장(9시간 빼기)
        final utc = DateTime.utc(pickedKst0.year, pickedKst0.month, pickedKst0.day)
            .subtract(const Duration(hours: 9));
        setState(() {
          startDateUtc = utc;
          if (endDateUtc != null && startDateUtc!.isAfter(endDateUtc!)) {
            endDateUtc = startDateUtc;
          }
        });
        _validatePay();
      },
    );
  }

  void _openEndDatePicker() {
    final minBase = _today0;
    DateTime min = minBase;
    if (startDateUtc != null) {
      final sKst = _Tx.toKst(startDateUtc)!;
      if (_d0(sKst).isAfter(min)) min = _d0(sKst);
    }
    final max = _today0.add(const Duration(days: 365));
    final currentKst = _Tx.toKst(endDateUtc) ?? min;

    _showDatePickerBottomSheet(
      initialDateKst: currentKst,
      minDateKst: min,
      maxDateKst: max,
      onSelected: (pickedKst0) {
        final utc = DateTime.utc(pickedKst0.year, pickedKst0.month, pickedKst0.day)
            .subtract(const Duration(hours: 9));
        setState(() => endDateUtc = utc);
        _validatePay();
      },
    );
  }

  // ===================== Time Range (iOS/Android 통일: 휠 바텀시트) =====================
  void _openTimePicker() {
    _showTimeRangePickerBottomSheet();
  }

  void _showTimeRangePickerBottomSheet() {
    TimeOfDay _align10(TimeOfDay t) {
      int m = ((t.minute + 5) ~/ 10) * 10;
      int h = t.hour;
      if (m == 60) {
        m = 0;
        h = (h + 1) % 24;
      }
      return TimeOfDay(hour: h, minute: m);
    }

    int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;
    bool _isOvernight(TimeOfDay s, TimeOfDay e) => _toMinutes(e) <= _toMinutes(s);

    int _durationMinutes(TimeOfDay s, TimeOfDay e) {
      final sm = _toMinutes(s), em = _toMinutes(e);
      int d = em - sm;
      if (d <= 0) d += 24 * 60;
      return d;
    }

    String _durationLabel(int mins) {
      final h = mins ~/ 60, m = mins % 60;
      if (h == 0) return '${m}분';
      if (m == 0) return '${h}시간';
      return '${h}시간 ${m}분';
    }

    String _fmt12(TimeOfDay t) {
      final period = t.period == DayPeriod.am ? '오전' : '오후';
      int h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
      final mm = t.minute.toString().padLeft(2, '0');
      return '$period $h:$mm';
    }

    TimeOfDay selectedStart = _align10(startTime ?? const TimeOfDay(hour: 9, minute: 0));
    TimeOfDay selectedEnd = _align10(
      endTime ?? selectedStart.replacing(hour: (selectedStart.hour + 1) % 24),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            final safePad = MediaQuery.of(context).viewPadding.bottom;

            void _applyStart(TimeOfDay t) => setModalState(() => selectedStart = _align10(t));
            void _applyEnd(TimeOfDay t) => setModalState(() => selectedEnd = _align10(t));

            final overnight = _isOvernight(selectedStart, selectedEnd);
            final duration = _durationMinutes(selectedStart, selectedEnd);

            return FractionallySizedBox(
              heightFactor: 0.85,
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  // 핸들/닫기
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 2),
                  const Text(
                    '근무 시간 설정',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  // 미리보기 카드
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_fmt12(selectedStart)} ~ ${overnight ? '익일 ' : ''}${_fmt12(selectedEnd)}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '총 근무시간 ${_durationLabel(duration)}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: LayoutBuilder(
                        builder: (ctx, box) {
                          final reserved = 60.0 + 20.0;
                          double each = (box.maxHeight - reserved) / 2;
                          if (each < 120) each = 120;

                          final content = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('시작 시간', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: each,
                                child: TimePickerSpinner(
                                  key: const ValueKey('startSpinner'),
                                  is24HourMode: false,
                                  minutesInterval: 10,
                                  normalTextStyle: const TextStyle(fontSize: 16, color: Colors.grey),
                                  highlightedTextStyle: const TextStyle(
                                    fontSize: 18,
                                    color: brandBlue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  spacing: 40,
                                  itemHeight: 40,
                                  isForce2Digits: true,
                                  time: DateTime(2000, 1, 1, selectedStart.hour, selectedStart.minute),
                                  onTimeChange: (dt) => _applyStart(TimeOfDay.fromDateTime(dt)),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text('종료 시간', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: each,
                                child: TimePickerSpinner(
                                  key: const ValueKey('endSpinner'),
                                  is24HourMode: false,
                                  minutesInterval: 10,
                                  normalTextStyle: const TextStyle(fontSize: 16, color: Colors.grey),
                                  highlightedTextStyle: const TextStyle(
                                    fontSize: 18,
                                    color: brandBlue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  spacing: 40,
                                  itemHeight: 40,
                                  isForce2Digits: true,
                                  time: DateTime(2000, 1, 1, selectedEnd.hour, selectedEnd.minute),
                                  onTimeChange: (dt) => _applyEnd(TimeOfDay.fromDateTime(dt)),
                                ),
                              ),
                            ],
                          );

                          final needsScroll = (each * 2 + reserved) > box.maxHeight;
                          return needsScroll
                              ? SingleChildScrollView(
                                  physics: const ClampingScrollPhysics(),
                                  child: content,
                                )
                              : content;
                        },
                      ),
                    ),
                  ),

                  SafeArea(
                    top: false,
                    minimum: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      (bottomInset > 0 ? bottomInset : safePad) + 8,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_toMinutes(selectedStart) == _toMinutes(selectedEnd)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('시작과 종료 시간이 같습니다')),
                            );
                            return;
                          }
                          setState(() {
                            startTime = selectedStart;
                            endTime = selectedEnd;
                          });
                          _validatePay();
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          '확인',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ===================== Pay utils =====================
  void _formatPayInput() {
    final raw = _pay.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.isEmpty) return;
    final v = int.tryParse(raw) ?? 0;
    final formatted = _moneyFmt.format(v);
    if (_pay.text != formatted) {
      _pay.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  int _toMin(TimeOfDay t) => t.hour * 60 + t.minute;

  int _durationMinutesAcrossMidnight(TimeOfDay s, TimeOfDay e) {
    final sm = _toMin(s), em = _toMin(e);
    var d = em - sm;
    if (d <= 0) d += 24 * 60;
    return d;
  }

  int _shortTermDayCountKst(DateTime utcStart0, DateTime utcEnd0) {
    final s = _d0(_Tx.toKst(utcStart0)!);
    final e = _d0(_Tx.toKst(utcEnd0)!);
    return e.difference(s).inDays + 1;
  }

  void _validatePay() {
    final raw = _pay.text.replaceAll(RegExp(r'[^0-9]'), '');
    final payVal = raw.isEmpty ? 0 : (int.tryParse(raw) ?? 0);

    if (payVal <= 0) {
      setState(() => _payWarning = null);
      return;
    }

    if (startTime == null || endTime == null) {
      setState(() => _payWarning = null);
      return;
    }

    final mins = _durationMinutesAcrossMidnight(startTime!, endTime!);
    final hours = mins / 60.0;
    if (hours <= 0) {
      setState(() => _payWarning = null);
      return;
    }

    // "일급": 하루 기준
    // "주급": 주(근무일수) 기준(장기=선택 요일 수, 단기=기간 내 일수로 근사)
    int divisorDays = 1;
    if (payType == '주급') {
      if (!isShortTerm) {
        divisorDays = selectedWeekdays.isEmpty ? 0 : selectedWeekdays.length;
      } else {
        if (startDateUtc != null && endDateUtc != null) {
          divisorDays = _shortTermDayCountKst(startDateUtc!, endDateUtc!);
        } else {
          divisorDays = 0;
        }
      }
    }

    if (payType == '주급' && divisorDays <= 0) {
      setState(() => _payWarning = '주급은 근무일(요일/기간)을 먼저 설정해주세요.');
      return;
    }

    final impliedHourly = payType == '일급'
        ? (payVal / hours)
        : (payVal / (hours * divisorDays));

    if (impliedHourly + 1e-9 < minWagePerHour) {
      setState(() => _payWarning =
          '최저시급 미달 가능성: 시급 약 ${_moneyFmt.format(impliedHourly.floor())}원 (기준 ${_moneyFmt.format(minWagePerHour)}원)');
    } else {
      setState(() => _payWarning = null);
    }
  }

  // ===================== Submit =====================
  void _showError(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('오류'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인')),
        ],
      ),
    );
  }

  void _scrollToKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      alignment: 0.15,
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) {
      // 간단 우선순위 스크롤
      if (_title.text.trim().isEmpty) _scrollToKey(_titleKey);
      else if (_location.text.trim().isEmpty) _scrollToKey(_locationKey);
      else if (_pay.text.trim().isEmpty) _scrollToKey(_payKey);
      return;
    }

    final payRaw = _pay.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (payRaw.isEmpty) {
      _showError('급여를 입력해주세요.');
      _scrollToKey(_payKey);
      return;
    }

    if (isShortTerm && (startDateUtc == null || endDateUtc == null)) {
      _showError('시작/종료일을 선택해주세요.');
      return;
    }

    if (startTime == null || endTime == null) {
      _showError('근무 시간을 선택해주세요.');
      return;
    }

    final payload = <String, dynamic>{
      'title': _title.text.trim(),
      'category': category,
      'location': location,
      'payType': payType,
      'pay': payRaw, // 숫자만
      'description': _desc.text.trim(),
      // 시간: 서버가 어떤 키를 받는지 혼용 대비
      'start_time': _Tx.fmtHmOf(startTime),
      'end_time': _Tx.fmtHmOf(endTime),
      'startTime': _Tx.fmtHmOf(startTime),
      'endTime': _Tx.fmtHmOf(endTime),
      // 날짜-only는 yyyy-MM-dd(KST 자정 의미)
      'startDate': isShortTerm ? _Tx.utcToKstYmd(startDateUtc) : null,
      'endDate': isShortTerm ? _Tx.utcToKstYmd(endDateUtc) : null,
      'weekdays': !isShortTerm ? selectedWeekdays.join(',') : null,
    }..removeWhere((k, v) => v == null);

    try {
      await JobService.updateJobWithImages(
        id: jobId,
        data: payload,
        newImages: newImages,
        deleteImageUrls: _toDeleteUrls.toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('공고 수정 완료')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showError('수정 실패: $e');
    }
  }

  // ===================== UI Helpers =====================
  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: brandBlue, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String label, {String? hint, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      suffixIcon: suffix,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE6E8EC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: brandBlue, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.red, width: 1.6),
      ),
    );
  }

  Widget _pillToggle({
    required String left,
    required String right,
    required bool value,
    required void Function(bool v) onChanged,
  }) {
    return Row(
      children: [
        _toggleChip(label: left, selected: value == true, onTap: () => onChanged(true)),
        const SizedBox(width: 10),
        _toggleChip(label: right, selected: value == false, onTap: () => onChanged(false)),
      ],
    );
  }

  Widget _toggleChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? brandBlue : Colors.white,
            border: Border.all(color: selected ? brandBlue : const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _deleteBadge() => Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: const Icon(Icons.close, color: Colors.white, size: 16),
      );

  Widget _imageThumbs() {
    final total = existingImageUrls.length + newImages.length;
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E4FF)),
        ),
        child: const Text(
          '사진은 선택 사항이에요.\n현장 사진/근무복/약도 등을 올리면 지원율이 올라갑니다.',
          style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.35),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Chip(
              label: Text('총 ${total}장'),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            if (_toDeleteUrls.isNotEmpty)
              Chip(
                label: Text('삭제예정 ${_toDeleteUrls.length}'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: total,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final isExisting = i < existingImageUrls.length;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: isExisting
                        ? Image.network(
                            existingImageUrls[i],
                            height: 120,
                            width: 120,
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            newImages[i - existingImageUrls.length],
                            height: 120,
                            width: 120,
                            fit: BoxFit.cover,
                          ),
                  ),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isExisting) {
                            final url = existingImageUrls[i];
                            _toDeleteUrls.add(url);
                            existingImageUrls.removeAt(i);
                          } else {
                            newImages.removeAt(i - existingImageUrls.length);
                          }
                        });
                      },
                      child: _deleteBadge(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dateRow() {
    final startYmd = _Tx.formatKstDate(startDateUtc);
    final endYmd = _Tx.formatKstDate(endDateUtc);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _dateBox(
                label: '시작일',
                value: startYmd.isEmpty ? null : startYmd,
                onTap: _openStartDatePicker,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dateBox(
                label: '종료일',
                value: endYmd.isEmpty ? null : endYmd,
                onTap: _openEndDatePicker,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E4FF)),
          ),
          child: const Text(
            '날짜는 KST(UTC+9) 자정 기준으로 저장됩니다.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ],
    );
  }

  Widget _dateBox({required String label, String? value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E4FF)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 18, color: brandBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value ?? '$label 선택',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: value == null ? Colors.black38 : Colors.black87,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black45),
          ],
        ),
      ),
    );
  }

  Widget _weekdayChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: weekdays.map((day) {
        final sel = selectedWeekdays.contains(day);
        return FilterChip(
          label: Text(day),
          selected: sel,
          selectedColor: brandBlue.withOpacity(0.15),
          checkmarkColor: brandBlue,
          onSelected: (v) {
            setState(() {
              if (v) {
                if (!selectedWeekdays.contains(day)) selectedWeekdays.add(day);
              } else {
                selectedWeekdays.remove(day);
              }
            });
            _validatePay();
          },
        );
      }).toList(),
    );
  }

  Widget _timeRangeRow() {
    final has = startTime != null && endTime != null;
    final value = has ? '${_Tx.fmtHmOf(startTime)} ~ ${_Tx.fmtHmOf(endTime)}' : '선택하기';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _openTimePicker,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6E8EC)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.access_time, size: 20, color: brandBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('근무 시간', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: has ? Colors.black : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
            if (has)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'KST',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.black45),
          ],
        ),
      ),
    );
  }

  Widget _payTypeRow() {
    return Row(
      children: [
        _toggleChip(
          label: '일급',
          selected: payType == '일급',
          onTap: () {
            setState(() => payType = '일급');
            _validatePay();
          },
        ),
        const SizedBox(width: 10),
        _toggleChip(
          label: '주급',
          selected: payType == '주급',
          onTap: () {
            setState(() => payType = '주급');
            _validatePay();
          },
        ),
      ],
    );
  }

  Widget _categoryDropdown() {
    final categories = ['제조', '물류', '서비스', '건설', '사무', '청소', '기타'];

    return DropdownButtonFormField<String>(
      value: category.isNotEmpty ? category : null,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      borderRadius: BorderRadius.circular(16),
      dropdownColor: Colors.white,
      menuMaxHeight: 340,
      elevation: 6,
      style: const TextStyle(fontSize: 14, color: Colors.black87),
      decoration: _inputDeco('하는 일', hint: '업종을 선택하세요'),
      validator: (_) => category.trim().isEmpty ? '업종을 선택하세요' : null,
      items: categories.map((c) {
        return DropdownMenuItem<String>(
          value: c,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: brandBlue, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(c),
            ],
          ),
        );
      }).toList(),
      onChanged: (val) {
        if (val == null) return;
        setState(() => category = val);
      },
    );
  }

  // ===================== Build =====================
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return UnfocusOnTap(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text('공고 수정'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _sectionCard(
                  title: '기본 정보',
                  subtitle: '지원자가 가장 먼저 보는 내용이에요',
                  icon: Icons.edit_note_rounded,
                  child: Column(
                    children: [
                      Container(
                        key: _titleKey,
                        child: TextFormField(
                          controller: _title,
                          decoration: _inputDeco(
                            '제목',
                            hint: '예: 물류 피킹 단기 알바 모집',
                            suffix: _title.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () => setState(() => _title.clear()),
                                  ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? '제목을 입력해주세요' : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _categoryDropdown(),
                      const SizedBox(height: 12),
                      Container(
                        key: _locationKey,
                        child: TextFormField(
                          controller: _location,
                          readOnly: true,
                          decoration: _inputDeco('근무지', hint: '주소를 선택하세요'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? '근무지를 선택해주세요' : null,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => KpostalView(
                                  useLocalServer: false,
                                  callback: (result) {
                                    setState(() {
                                      location = result.address;
                                      _location.text = result.address;
                                    });
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                _sectionCard(
                  title: '사진',
                  subtitle: '선택사항 · 현장 사진이 있으면 지원이 더 잘 와요',
                  icon: Icons.photo_library_outlined,
                  trailing: ElevatedButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.image, size: 18),
                    label: const Text('추가'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                  child: _imageThumbs(),
                ),

                _sectionCard(
                  title: '근무 기간',
                  subtitle: '단기(날짜) / 장기(요일) 중 선택',
                  icon: Icons.event_available_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _pillToggle(
                        left: '단기',
                        right: '1개월 이상',
                        value: isShortTerm,
                        onChanged: (v) {
                          setState(() {
                            isShortTerm = v;
                            if (isShortTerm) {
                              selectedWeekdays.clear();
                            } else {
                              startDateUtc = null;
                              endDateUtc = null;
                            }
                          });
                          _validatePay();
                        },
                      ),
                      const SizedBox(height: 12),
                      if (isShortTerm) _dateRow() else _weekdayChips(),
                    ],
                  ),
                ),

                _sectionCard(
                  title: '근무 시간',
                  subtitle: '안드/IOS 동일 UI로 설정됩니다',
                  icon: Icons.access_time_rounded,
                  child: _timeRangeRow(),
                ),

                _sectionCard(
                  title: '급여',
                  subtitle: '입력한 시간/기간에 따라 최저시급을 자동 체크합니다',
                  icon: Icons.payments_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _payTypeRow(),
                      const SizedBox(height: 12),
                      Container(
                        key: _payKey,
                        child: TextFormField(
                          controller: _pay,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))],
                          decoration: _inputDeco(
                            '급여',
                            hint: '예: 120,000',
                            suffix: _pay.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() => _pay.clear());
                                      _validatePay();
                                    },
                                  ),
                          ).copyWith(
                            errorText: _payWarning,
                            helperText: '최저시급 ${_moneyFmt.format(minWagePerHour)}원 이상 권장',
                            helperStyle: const TextStyle(fontSize: 11),
                          ),
                          validator: (v) {
                            final raw = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                            if (raw.isEmpty) return '급여를 입력해주세요';
                            if (_payWarning != null) return _payWarning;
                            return null;
                          },
                          onChanged: (_) {
                            _formatPayInput();
                            _validatePay();
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                _sectionCard(
                  title: '상세 설명',
                  subtitle: '업무/복장/준비물/주의사항을 간단히 적어주세요',
                  icon: Icons.description_outlined,
                  child: SizedBox(
                    height: 220,
                    child: TextFormField(
                      controller: _desc,
                      maxLines: null,
                      expands: true,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: _inputDeco(
                        '자세한 설명',
                        hint: '예: 업무는 2가지(피킹/포장) · 교육 10분 · 초보 가능',
                        suffix: _desc.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() => _desc.clear()),
                              ),
                      ),
                      validator: (_) => null, // 선택 입력
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 1,
              ),
              child: const Text(
                '공고 수정 완료',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// Unfocus helper
/// ------------------------------------------------------------
class UnfocusOnTap extends StatelessWidget {
  final Widget child;
  const UnfocusOnTap({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final currentFocus = FocusScope.of(context);
        if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
          currentFocus.unfocus();
        }
      },
      child: child,
    );
  }
}
