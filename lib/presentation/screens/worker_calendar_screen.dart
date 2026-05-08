import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../config/constants.dart';

// =====================
// 색상 팔레트
// =====================
const kBrandBlue = Color(0xFF3B8AFF);
const kBg        = Color(0xFFF7F8FA);
const kCard      = Colors.white;
const kBorder    = Color(0xFFE5E7EB);
const kMuted     = Color(0xFF6B7280);
const kText      = Color(0xFF111827);

// =====================
// 상태 상수
// =====================
const _kScheduled = 'scheduled';
const _kCompleted = 'completed';
const _kCancelled = {'cancelled', 'canceled'};

// =====================
// WorkerCalendarScreen
// =====================
class WorkerCalendarScreen extends StatefulWidget {
  final DateTime? initialFocusDay;
  const WorkerCalendarScreen({super.key, this.initialFocusDay});

  @override
  State<WorkerCalendarScreen> createState() => _WorkerCalendarScreenState();
}

class _WorkerCalendarScreenState extends State<WorkerCalendarScreen> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  bool _loading = true;
  String? _error;

  // ── raw 아이템 목록
  List<Map<String, dynamic>> _items = [];

  // ── 캐시: _items 변경 시만 재계산
  Map<DateTime, List<Map<String, dynamic>>>? _indexCache;
  Map<DateTime, Map<String, int>>? _sumsCache;
  int? _scheduledTotalCache;
  int? _completedTotalCache;

  // ── 진행 중인 fetch를 취소하기 위한 토큰
  int _fetchGeneration = 0;

  // ──────────────────────────────────────────
  // 초기화
  // ──────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _focusedDay  = _dateOnly(widget.initialFocusDay ?? DateTime.now());
    _selectedDay = _dateOnly(_focusedDay);
    _fetchMonth(_focusedDay);
  }

  // ──────────────────────────────────────────
  // tiny helpers
  // ──────────────────────────────────────────
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  String _sourceOf(Map<String, dynamic> it) {
    final raw = (it['source'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    if (it.containsKey('job_id') || it.containsKey('jobId')) return 'job';
    return 'manual';
  }

  bool _isJobSource(Map<String, dynamic> it) => _sourceOf(it) == 'job';

  dynamic _idOf(Map<String, dynamic> it) =>
      it['id'] ?? it['session_id'] ?? it['worker_session_id'] ?? it['job_id'] ?? it['jobId'];

  bool _isCancelled(Map<String, dynamic> it) =>
      _kCancelled.contains((it['status'] ?? '').toString());

  int _amount(Map<String, dynamic> it) {
    final raw = (it['pay'] ?? 0).toString();
    // "120000.0" 같은 소수점 케이스도 안전하게 처리
    return (double.tryParse(raw) ?? 0).toInt();
  }

  DateTime _asDate(dynamic v) {
    final str = (v ?? '').toString().trim();
    final parsed = DateTime.tryParse(str);
    if (parsed != null) return _dateOnly(parsed);

    if (str.length >= 10) {
      final parts = str.substring(0, 10).split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) return DateTime(y, m, d);
      }
    }
    return _dateOnly(DateTime.now());
  }

  TimeOfDay _parseTime(
    dynamic s, {
    TimeOfDay fallback = const TimeOfDay(hour: 9, minute: 0),
  }) {
    final str = (s ?? '').toString().trim();
    if (str.isEmpty) return fallback;
    final parts = str.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]) ?? fallback.hour;
      final m = int.tryParse(parts[1]) ?? fallback.minute;
      return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
    }
    return fallback;
  }

  // ──────────────────────────────────────────
  // 캐시 관리
  // ──────────────────────────────────────────
  void _invalidateCache() {
    _indexCache          = null;
    _sumsCache           = null;
    _scheduledTotalCache = null;
    _completedTotalCache = null;
  }

  /// 날짜 → 아이템 인덱스 (O(1) 조회용)
  Map<DateTime, List<Map<String, dynamic>>> get _index {
    if (_indexCache != null) return _indexCache!;
    final map = <DateTime, List<Map<String, dynamic>>>{};
    for (final it in _items) {
      final key = _asDate(it['work_date']);
      (map[key] ??= []).add(it);
    }
    // 각 날짜의 아이템을 start_time 기준 정렬
    for (final list in map.values) {
      list.sort((a, b) {
        final aT = (a['start_time'] ?? a['start_at'] ?? '').toString();
        final bT = (b['start_time'] ?? b['start_at'] ?? '').toString();
        return aT.compareTo(bT);
      });
    }
    return _indexCache = map;
  }

  /// 날짜별 금액 합계 - 완료/예정 구분 (캘린더 마커용)
  Map<DateTime, Map<String, int>> get _sumByDay {
    if (_sumsCache != null) return _sumsCache!;
    final map = <DateTime, Map<String, int>>{};
    for (final it in _items) {
      if (_isCancelled(it)) continue;
      final key    = _asDate(it['work_date']);
      final status = (it['status'] ?? '').toString();
      final bucket = map[key] ??= {'scheduled': 0, 'completed': 0};
      if (status == _kCompleted) {
        bucket['completed'] = (bucket['completed'] ?? 0) + _amount(it);
      } else if (status == _kScheduled) {
        bucket['scheduled'] = (bucket['scheduled'] ?? 0) + _amount(it);
      }
    }
    return _sumsCache = map;
  }

  /// scheduled 상태만 합계
  int get _scheduledTotal {
    if (_scheduledTotalCache != null) return _scheduledTotalCache!;
    int sum = 0;
    for (final it in _items) {
      if ((it['status'] ?? '').toString() == _kScheduled) sum += _amount(it);
    }
    return _scheduledTotalCache = sum;
  }

  /// completed 상태만 합계
  int get _completedTotal {
    if (_completedTotalCache != null) return _completedTotalCache!;
    int sum = 0;
    for (final it in _items) {
      if ((it['status'] ?? '').toString() == _kCompleted) sum += _amount(it);
    }
    return _completedTotalCache = sum;
  }

  List<Map<String, dynamic>> _itemsOf(DateTime day) =>
      _index[_dateOnly(day)] ?? const [];

  // ── 토큰 캐시 (앱 세션 동안 재사용)
  String? _cachedToken;

  // ──────────────────────────────────────────
  // auth
  // ──────────────────────────────────────────
  Future<String> _token() async {
    if (_cachedToken != null) return _cachedToken!;
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString('authToken') ?? '';
    return _cachedToken!;
  }

  /// 로그아웃 등으로 토큰이 바뀔 때 호출
  void _clearTokenCache() => _cachedToken = null;

  // ──────────────────────────────────────────
  // fetch
  // ──────────────────────────────────────────
  Future<void> _fetchMonth(DateTime day) async {
    final generation = ++_fetchGeneration;

    _safeSetState(() {
      _loading = true;
      _error   = null;
    });

    try {
      final token = await _token();
      if (!mounted || generation != _fetchGeneration) return;

      if (token.isEmpty) {
        _safeSetState(() {
          _items = [];
          _invalidateCache();
          _error = '로그인이 필요해요 🙏';
        });
        return;
      }

      final result = await _fetchMonthRaw(day, token: token);
      if (!mounted || generation != _fetchGeneration) return;

      _safeSetState(() {
        _items = result.ok ? result.items : [];
        _invalidateCache();
        _error = result.ok ? null : (result.errorMessage ?? '조회가 실패했어요 😵');
      });
    } finally {
      if (mounted && generation == _fetchGeneration) {
        _safeSetState(() => _loading = false);
      }
    }
  }

  Future<_FetchMonthResult> _fetchMonthRaw(
    DateTime day, {
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/api/worker-sessions/month').replace(
      queryParameters: {'year': '${day.year}', 'month': '${day.month}'},
    );

    try {
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode != 200) {
        return _FetchMonthResult(
          ok: false,
          items: const [],
          errorMessage: '조회 실패: ${resp.statusCode}',
        );
      }

      final decoded = jsonDecode(resp.body);
      final List rawList = (decoded is Map && decoded['items'] is List)
          ? decoded['items'] as List
          : (decoded is List ? decoded : const []);

      final items = rawList
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      return _FetchMonthResult(ok: true, items: items);
    } catch (_) {
      return _FetchMonthResult(
        ok: false,
        items: const [],
        errorMessage: '네트워크 오류가 났어요 🥲',
      );
    }
  }

  // ──────────────────────────────────────────
  // API helpers
  // ──────────────────────────────────────────
  Future<_ApiResult> _patchBySource({
    required String source,
    required dynamic id,
    required Map<String, dynamic> body,
  }) async {
    final token = await _token();
    final uri   = Uri.parse('$baseUrl/api/worker-sessions/$source/$id');
    try {
      final resp = await http.patch(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      return _ApiResult(ok: resp.statusCode == 200, statusCode: resp.statusCode, body: resp.body);
    } catch (e) {
      return _ApiResult(ok: false, statusCode: null, body: '$e');
    }
  }

  Future<_ApiResult> _deleteBySource({
    required String source,
    required dynamic id,
  }) async {
    final token = await _token();
    final uri   = Uri.parse('$baseUrl/api/worker-sessions/$source/$id');
    try {
      final resp = await http.delete(uri, headers: {'Authorization': 'Bearer $token'});
      return _ApiResult(
        ok: resp.statusCode == 200 || resp.statusCode == 204,
        statusCode: resp.statusCode,
        body: resp.body,
      );
    } catch (e) {
      return _ApiResult(ok: false, statusCode: null, body: '$e');
    }
  }

  Future<_ApiResult> _completeBySource({
    required String source,
    required dynamic id,
  }) async {
    final token = await _token();
    final uri   = Uri.parse('$baseUrl/api/worker-sessions/$source/$id/complete');
    try {
      final resp = await http.patch(
        uri,
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      );
      return _ApiResult(
        ok: resp.statusCode == 200 || resp.statusCode == 204,
        statusCode: resp.statusCode,
        body: resp.body,
      );
    } catch (e) {
      return _ApiResult(ok: false, statusCode: null, body: '$e');
    }
  }

  Future<bool> _createManualSession(Map<String, dynamic> body) async {
    final token = await _token();
    final uri   = Uri.parse('$baseUrl/api/worker-sessions/manual');
    try {
      final resp = await http.post(
        uri,
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // ──────────────────────────────────────────
  // actions
  // ──────────────────────────────────────────
  // ── 액션 진행 중 플래그 (연타 방지)
  bool _actionInProgress = false;

  Future<void> _markCompleted(Map<String, dynamic> it) async {
    if (_actionInProgress) return;
    if (_isCancelled(it)) {
      _snack('취소된 일정은 완료 처리 대신 삭제만 할 수 있어요 🗑️');
      return;
    }
    final id = _idOf(it);
    if (id == null) {
      _snack('id가 없어서 완료 처리가 안돼요 🥲');
      return;
    }
    if ((it['status'] ?? '').toString() == _kCompleted) {
      _snack('이미 완료된 일정이에요 ✅');
      return;
    }

    final source = _sourceOf(it);
    _actionInProgress = true;
    try {
      final r1 = await _completeBySource(source: source, id: id);
      if (r1.ok) {
        _snack('완료 처리됐어요 ✅');
        await _fetchMonth(_focusedDay);
        return;
      }

      final r2 = await _patchBySource(source: source, id: id, body: {'status': _kCompleted});
      if (r2.ok) {
        _snack('완료 처리됐어요 ✅');
        await _fetchMonth(_focusedDay);
      } else {
        _snack('완료 처리가 실패했어요 🥲');
      }
    } finally {
      _actionInProgress = false;
    }
  }

  Future<void> _deleteSession(Map<String, dynamic> it) async {
    if (_actionInProgress) return;
    final id = _idOf(it);
    if (id == null) {
      _snack('id가 없어서 처리가 안돼요 🥲');
      return;
    }

    final source = _sourceOf(it);
    final sure = await _confirm(
      title: '삭제할까요?',
      message: source == 'job'
          ? '공고로 들어온 일정은 서버 정책상 삭제가 막혀있을 수도 있어요.\n그래도 삭제를 시도할게요.'
          : '삭제한 일정은 복구가 어려워요 🥺',
      okText: '삭제',
      danger: true,
    );
    if (sure != true) return;

    _actionInProgress = true;
    try {
      final result = await _deleteBySource(source: source, id: id);
      if (result.ok) {
        _snack('삭제됐어요 🗑️');
        await _fetchMonth(_focusedDay);
      } else {
        _snack(source == 'job'
            ? '공고 일정 삭제가 제한되어 있어요 🥲\n(서버 정책/권한 문제일 수 있어요)'
            : '삭제가 실패했어요 🥲');
      }
    } finally {
      _actionInProgress = false;
    }
  }

  Future<void> _openEditSheet({
    Map<String, dynamic>? item,
    DateTime? forceDate,
  }) async {
    final token = await _token();
    if (token.isEmpty) {
      _snack('로그인이 필요해요 🙏');
      return;
    }
    if (item != null && _isJobSource(item)) {
      _snack('공고로 등록된 일정은 수정할 수 없어요 🙂\n(완료/삭제만 가능해요)');
      return;
    }

    final isEdit   = item != null;
    final initDate = forceDate ??
        (isEdit ? _asDate(item['work_date']) : (_selectedDay ?? _dateOnly(DateTime.now())));

    String normalizedStatus = (item?['status'] ?? _kScheduled).toString();
    if (_kCancelled.contains(normalizedStatus)) normalizedStatus = _kScheduled;

    final init = SessionEditInitial(
      id:       isEdit ? _idOf(item) : null,
      workDate: initDate,
      title:    (item?['title']   ?? '').toString(),
      company:  (item?['company'] ?? item?['company_name'] ?? '').toString(),
      payText:  (item?['pay']     ?? '').toString(),
      start:    _parseTime(item?['start_time'] ?? item?['start_at'], fallback: const TimeOfDay(hour: 9, minute: 0)),
      end:      _parseTime(item?['end_time']   ?? item?['end_at'],   fallback: const TimeOfDay(hour: 18, minute: 0)),
      status:   normalizedStatus,
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (_) => SessionEditSheet(
        brandBlue: kBrandBlue,
        isEdit:    isEdit,
        initial:   init,
        onSave: (payload) async {
          if (!isEdit) return await _createManualSession(payload);

          final source    = _sourceOf(item);
          final id        = _idOf(item);
          if (id == null) { _snack('id가 없어서 저장이 안돼요 🥲'); return false; }

          if ((payload['status'] ?? '').toString() == _kCompleted) {
            final r1 = await _completeBySource(source: source, id: id);
            if (r1.ok) return true;
          }
          final r = await _patchBySource(source: source, id: id, body: payload);
          if (!r.ok) _snack('저장이 실패했어요 🥲');
          return r.ok;
        },
        onDelete: isEdit
            ? () async {
                final source = _sourceOf(item);
                final id     = _idOf(item);
                if (id == null) return false;

                final sure = await _confirm(
                  title:   '삭제할까요?',
                  message: '삭제한 일정은 복구가 어려워요 🥺',
                  okText:  '삭제',
                  danger:  true,
                );
                if (sure != true) return false;

                final r = await _deleteBySource(source: source, id: id);
                if (!r.ok) _snack('삭제가 실패했어요 🥲');
                return r.ok;
              }
            : null,
      ),
    );

    if (saved == true) {
      await _fetchMonth(_focusedDay);
    }
  }

  // ──────────────────────────────────────────
  // build
  // ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomSystem = MediaQuery.of(context).padding.bottom;
    final total        = _scheduledTotal + _completedTotal;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.8,
        title: const Text(
          '내 정산 달력',
          style: TextStyle(
            fontFamily: 'Jalnan2TTF',
            color: kBrandBlue,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _fetchMonth(_focusedDay),
          ),
        ],
      ),
      floatingActionButton: SafeArea(
        child: FloatingActionButton(
          backgroundColor: kBrandBlue,
          foregroundColor: Colors.white,
          onPressed: () => _openEditSheet(
            forceDate: _selectedDay ?? _dateOnly(DateTime.now()),
          ),
          child: const Icon(Icons.add_rounded),
        ),
      ),
      body: SafeArea(
        top:    false,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomSystem),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    if (_error != null) _warningBox(_error!),
                    _buildSummaryCard(total),
                    const SizedBox(height: 12),
                    _buildCalendar(),
                    const SizedBox(height: 10),
                    Expanded(child: _buildDayPanel(_selectedDay)),
                  ],
                ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────
  // 섹션 위젯
  // ──────────────────────────────────────────

  Widget _buildSummaryCard(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            _moneyBox('예정', _scheduledTotal),
            const SizedBox(width: 8),
            _moneyBox('완료', _completedTotal),
            const SizedBox(width: 8),
            _moneyBox('합계', total, strong: true),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      margin:     const EdgeInsets.symmetric(horizontal: 16),
      decoration: _cardDecoration(),
      child: TableCalendar(
        firstDay:           DateTime(2020, 1, 1),
        lastDay:            DateTime(2035, 12, 31),
        focusedDay:         _focusedDay,
        locale:             'ko_KR',
        startingDayOfWeek:  StartingDayOfWeek.monday,
        availableGestures:  AvailableGestures.all,
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered:       true,
          titleTextStyle:      const TextStyle(fontWeight: FontWeight.w900, color: kText),
          titleTextFormatter:  (date, locale) => DateFormat('yyyy년 M월', locale).format(date),
          leftChevronIcon:     const Icon(Icons.chevron_left_rounded,  color: kText),
          rightChevronIcon:    const Icon(Icons.chevron_right_rounded, color: kText),
        ),
        daysOfWeekStyle: const DaysOfWeekStyle(
          weekdayStyle: TextStyle(color: kMuted, fontWeight: FontWeight.w800),
          weekendStyle: TextStyle(color: kMuted, fontWeight: FontWeight.w800),
        ),
        selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
        onDaySelected: (selectedDay, focusedDay) {
          _safeSetState(() {
            _selectedDay = _dateOnly(selectedDay);
            _focusedDay  = _dateOnly(focusedDay);
          });
        },
        onPageChanged: (focusedDay) {
          final today = _dateOnly(DateTime.now());
          final isCurrentMonth =
              focusedDay.year == today.year && focusedDay.month == today.month;
          _safeSetState(() {
            _focusedDay  = _dateOnly(focusedDay);
            _selectedDay = isCurrentMonth ? today : null;
          });
          _fetchMonth(_focusedDay);
        },
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: kBrandBlue.withOpacity(0.10),
            shape: BoxShape.circle,
          ),
          selectedDecoration: const BoxDecoration(
            color: kBrandBlue,
            shape: BoxShape.circle,
          ),
          selectedTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          todayTextStyle:    const TextStyle(color: kBrandBlue,   fontWeight: FontWeight.w900),
        ),
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, day, _) {
            final bucket    = _sumByDay[_dateOnly(day)];
            if (bucket == null) return const SizedBox.shrink();
            final scheduled = bucket['scheduled'] ?? 0;
            final completed = bucket['completed'] ?? 0;
            if (scheduled <= 0 && completed <= 0) return const SizedBox.shrink();

            // 완료만 있으면 초록, 예정만 있으면 파랑, 둘 다 있으면 파랑 (예정 우선 표시)
            final showAmount  = scheduled > 0 ? scheduled : completed;
            final markerColor = completed > 0 && scheduled == 0
                ? const Color(0xFF16A34A)  // 완료 → 초록
                : kBrandBlue;              // 예정(혹은 혼재) → 파랑

            return Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin:  const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color:        markerColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  NumberFormat.compact(locale: 'ko_KR').format(showAmount),
                  style: TextStyle(
                    fontSize:   10,
                    color:      markerColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDayPanel(DateTime? day) {
    return Container(
      margin:     const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding:    const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child:      day == null ? _buildNoDaySelected() : _buildDayList(day),
    );
  }

  Widget _buildNoDaySelected() {
    return const Center(
      child: Text(
        '날짜를 선택하면\n일정을 확인할 수 있어요 📅',
        textAlign: TextAlign.center,
        style: TextStyle(
          color:      Color(0xFF9CA3AF),
          height:     1.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildDayList(DateTime day) {
    final list  = _itemsOf(day);
    final title = DateFormat('yyyy.MM.dd (E)', 'ko_KR').format(day);

    if (list.isEmpty) {
      return Center(
        child: Text(
          '$title\n등록된 일정이 없어요 🙂\n오른쪽 아래 + 로 추가해봐요',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color:      Color(0xFF9CA3AF),
            height:     1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    final hasJob = list.any(_isJobSource);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더
        LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 320;
          return Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize:   14,
                    fontWeight: FontWeight.w900,
                    color:      kText,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.swipe_left_rounded, size: 18, color: kBrandBlue),
              const SizedBox(width: 6),
              if (!narrow)
                Flexible(
                  child: Text(
                    hasJob
                        ? '공고 일정은 수정이 안 돼요 (완료/삭제만 가능)'
                        : '밀어서 완료/수정/삭제',
                    maxLines:  1,
                    overflow:  TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize:   12,
                      color:      Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          );
        }),

        // 공고 안내 배너
        if (hasJob) ...[
          const SizedBox(height: 8),
          Container(
            padding:    const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:        const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border:       Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: kBrandBlue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '공고로 들어온 일정은 회사 정보라서 수정이 어려워요 🙂\n완료 처리하거나, 삭제로 정리해주세요!',
                    style: TextStyle(
                      fontSize:   12,
                      color:      Color(0xFF1D4ED8),
                      fontWeight: FontWeight.w900,
                      height:     1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),

        // 아이템 리스트
        Expanded(
          child: ListView.separated(
            itemCount:        list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder:      (_, i)  => _buildSessionCard(list[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> it) {
    final source    = _sourceOf(it);
    final isJob     = source == 'job';
    final cancelled = _isCancelled(it);
    final completed = (it['status'] ?? '').toString() == _kCompleted;
    final amount    = _amount(it);
    final company   = (it['company']  ?? it['company_name'] ?? '기업').toString();
    final jobTitle  = (it['title']    ?? '공고').toString();
    final start     = (it['start_time'] ?? it['start_at'] ?? '').toString();
    final end       = (it['end_time']   ?? it['end_at']   ?? '').toString();

    final badgeText = completed ? '완료' : cancelled ? '취소됨' : '예정';
    final badgeBg   = completed
        ? const Color(0xFFDCFCE7)
        : cancelled
            ? const Color(0xFFF3F4F6)
            : kBrandBlue.withOpacity(0.12);
    final badgeFg   = completed
        ? const Color(0xFF166534)
        : cancelled
            ? const Color(0xFF6B7280)
            : kBrandBlue;

    return Slidable(
      key: ValueKey('$source-${_idOf(it)}'),
      endActionPane: ActionPane(
        motion:      const StretchMotion(),
        extentRatio: isJob ? 0.46 : 0.70,
        children: [
          SlidableAction(
            onPressed:       (_) => _markCompleted(it),
            backgroundColor: const Color(0xFF16A34A),
            foregroundColor: Colors.white,
            icon:            Icons.check_circle_rounded,
            label:           '완료',
          ),
          if (!isJob)
            SlidableAction(
              onPressed:       (_) => _openEditSheet(item: it),
              backgroundColor: kBrandBlue,
              foregroundColor: Colors.white,
              icon:            Icons.edit_rounded,
              label:           '수정',
            ),
          SlidableAction(
            onPressed:       (_) => _deleteSession(it),
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
            icon:            Icons.delete_rounded,
            label:           '삭제',
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          if (isJob) {
            _snack('공고 일정은 수정할 수 없어요 🙂\n(완료/삭제만 가능해요)');
            return;
          }
          _openEditSheet(item: it);
        },
        borderRadius: BorderRadius.circular(18),
        child: Opacity(
          opacity: cancelled ? 0.68 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:        const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(18),
              border:       Border.all(color: kBorder),
              boxShadow: [
                BoxShadow(
                  color:      Colors.black.withOpacity(0.035),
                  blurRadius: 14,
                  offset:     const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                // 아이콘
                Container(
                  width:  46,
                  height: 46,
                  decoration: BoxDecoration(
                    color:        kBrandBlue.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.event_note_rounded, color: kBrandBlue),
                ),
                const SizedBox(width: 12),
                // 내용
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        jobTitle.isEmpty ? '공고' : jobTitle,
                        maxLines:  1,
                        overflow:  TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize:   14,
                          fontWeight: FontWeight.w900,
                          color:      kText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              company,
                              maxLines:  1,
                              overflow:  TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize:   12,
                                color:      kMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (start.isNotEmpty || end.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${start.isEmpty ? '--:--' : start} ~ ${end.isEmpty ? '--:--' : end}',
                                maxLines:  1,
                                overflow:  TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize:   12,
                                  color:      kMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _pill(label: badgeText, bg: badgeBg, fg: badgeFg),
                          if (isJob) ...[
                            const SizedBox(width: 8),
                            _pill(
                              label: '공고',
                              bg:    const Color(0xFFF3F4F6),
                              fg:    const Color(0xFF6B7280),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Expanded(
                            child: FittedBox( // ✅ 긴 금액 오버플로우 방지
                              fit:       BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${NumberFormat('#,###').format(amount)}원',
                                style: const TextStyle(
                                  fontSize:   14,
                                  fontWeight: FontWeight.w900,
                                  color:      kText,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────
  // small UI atoms
  // ──────────────────────────────────────────
  BoxDecoration _cardDecoration() => BoxDecoration(
    color:        kCard,
    borderRadius: BorderRadius.circular(18),
    border:       Border.all(color: kBorder),
    boxShadow: [
      BoxShadow(
        color:      Colors.black.withOpacity(0.04),
        blurRadius: 18,
        offset:     const Offset(0, 10),
      ),
    ],
  );

  Widget _warningBox(String text) {
    return Container(
      margin:     const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding:    const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFF9A3412)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color:      Color(0xFF9A3412),
                fontSize:   12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyBox(String label, int amount, {bool strong = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:        strong ? kBrandBlue.withOpacity(0.10) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border:       strong ? Border.all(color: kBrandBlue.withOpacity(0.18)) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            FittedBox( // ✅ 긴 숫자 오버플로우 방지
              fit:       BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${NumberFormat('#,###').format(amount)}원',
                style: TextStyle(
                  fontSize:   15,
                  fontWeight: FontWeight.w900,
                  color:      strong ? kBrandBlue : kText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill({required String label, required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w900),
      ),
    );
  }

  // ──────────────────────────────────────────
  // dialogs / snack
  // ──────────────────────────────────────────
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String okText,
    bool danger = false,
  }) {
    return showModalBottomSheet<bool>(
      context:          context,
      backgroundColor:  Colors.transparent,
      isScrollControlled: false,
      useSafeArea:      false,
      builder: (sheetCtx) { // ✅ builder 전용 context 사용
        final safeBottom = MediaQuery.of(sheetCtx).viewPadding.bottom;
        final Color accent   = danger ? const Color(0xFFDC2626) : kBrandBlue;
        final Color accentBg = danger
            ? const Color(0xFFFFE4E6)
            : kBrandBlue.withOpacity(0.10);

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: safeBottom),
            child: Container(
              margin:  const EdgeInsets.fromLTRB(14, 0, 14, 14),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color:        Colors.white,
                borderRadius: BorderRadius.circular(22),
                border:       Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color:      Colors.black.withOpacity(0.12),
                    blurRadius: 30,
                    offset:     const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 드래그 핸들
                  Container(
                    width:  42,
                    height: 5,
                    decoration: BoxDecoration(
                      color:        const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width:  56,
                    height: 56,
                    decoration: BoxDecoration(
                      color:        accentBg,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      danger ? Icons.delete_forever_rounded : Icons.help_outline_rounded,
                      color: accent,
                      size:  28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Jalnan2TTF',
                      fontSize:   16,
                      fontWeight: FontWeight.w800,
                      color:      Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize:   13,
                      height:     1.35,
                      fontWeight: FontWeight.w700,
                      color:      Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF111827),
                            side:            const BorderSide(color: Color(0xFFE5E7EB)),
                            padding:         const EdgeInsets.symmetric(vertical: 14),
                            shape:           RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            backgroundColor: const Color(0xFFF9FAFB),
                          ),
                          onPressed: () => Navigator.pop(sheetCtx, false), // ✅ sheetCtx
                          child: const Text('취소', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            padding:         const EdgeInsets.symmetric(vertical: 14),
                            shape:           RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () => Navigator.pop(sheetCtx, true), // ✅ sheetCtx
                          child: Text(okText, style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// =====================
// Data classes
// =====================
class _ApiResult {
  final bool   ok;
  final int?   statusCode;
  final String body;
  const _ApiResult({required this.ok, required this.statusCode, required this.body});
}

class _FetchMonthResult {
  final bool                        ok;
  final List<Map<String, dynamic>>  items;
  final String?                     errorMessage;
  const _FetchMonthResult({required this.ok, required this.items, this.errorMessage});
}

// =====================
// 금액 실시간 콤마 포매터
// =====================
class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(',', '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final formatted = NumberFormat('#,###').format(int.parse(digits));
    return newValue.copyWith(
      text:      formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// =====================
// SessionEditInitial
// =====================
class SessionEditInitial {
  final dynamic    id;
  final DateTime   workDate;
  final String     title;
  final String     company;
  final String     payText;
  final TimeOfDay  start;
  final TimeOfDay  end;
  final String     status;

  const SessionEditInitial({
    required this.id,
    required this.workDate,
    required this.title,
    required this.company,
    required this.payText,
    required this.start,
    required this.end,
    required this.status,
  });
}

typedef SavePayloadFn  = Future<bool> Function(Map<String, dynamic> payload);
typedef SimpleActionFn = Future<bool> Function();

// =====================
// SessionEditSheet
// =====================
class SessionEditSheet extends StatefulWidget {
  final Color          brandBlue;
  final bool           isEdit;
  final SessionEditInitial initial;
  final SavePayloadFn  onSave;
  final SimpleActionFn? onDelete;

  const SessionEditSheet({
    super.key,
    required this.brandBlue,
    required this.isEdit,
    required this.initial,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<SessionEditSheet> createState() => _SessionEditSheetState();
}

class _SessionEditSheetState extends State<SessionEditSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _companyCtrl;
  late final TextEditingController _payCtrl;

  late DateTime  _workDate;
  late TimeOfDay _startT;
  late TimeOfDay _endT;
  late String    _status;
  bool           _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl   = TextEditingController(text: widget.initial.title);
    _companyCtrl = TextEditingController(text: widget.initial.company);
    _payCtrl     = TextEditingController(text: widget.initial.payText);

    _workDate = DateTime(
      widget.initial.workDate.year,
      widget.initial.workDate.month,
      widget.initial.workDate.day,
    );
    _startT = widget.initial.start;
    _endT   = widget.initial.end;

    final st = widget.initial.status;
    _status = _kCancelled.contains(st) ? _kScheduled : st;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _companyCtrl.dispose();
    _payCtrl.dispose();
    super.dispose();
  }

  String _fmtYmd(DateTime d)  => DateFormat('yyyy-MM-dd').format(d);
  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context:     context,
      initialDate: _workDate,
      firstDate:   DateTime(2020, 1, 1),
      lastDate:    DateTime(2035, 12, 31),
      locale:      const Locale('ko', 'KR'),
    );
    if (picked != null && mounted) {
      setState(() => _workDate = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context:     context,
      initialTime: isStart ? _startT : _endT,
      builder: (context, child) => MediaQuery(
        data:  MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null && mounted) {
      setState(() => isStart ? _startT = picked : _endT = picked);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    // 금액 검사 (콤마 제거 후 파싱)
    final pay = int.tryParse(_payCtrl.text.replaceAll(',', '').trim()) ?? 0;
    if (pay <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('금액을 입력해줘요 🙂')),
      );
      return;
    }

    // 시간 유효성 검사
    final startMinutes = _startT.hour * 60 + _startT.minute;
    final endMinutes   = _endT.hour   * 60 + _endT.minute;
    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('종료 시간이 시작 시간보다 빠르거나 같아요 ⏰')),
      );
      return;
    }

    setState(() => _saving = true);

    final payload = <String, dynamic>{
      'work_date':  _fmtYmd(_workDate),
      'start_time': _fmtTime(_startT),
      'end_time':   _fmtTime(_endT),
      'pay':        pay,
      'title':      _titleCtrl.text.trim(),
      'company':    _companyCtrl.text.trim(),
      'status':     _status == _kCompleted ? _kCompleted : _kScheduled,
    };

    try {
      final ok = await widget.onSave(payload);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장이 실패했어요 🥲')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 중 오류가 났어요: $e')),
      );
    }
  }

  // ──────────────────────────────────────────
  // build
  // ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // ✅ 키보드 패딩을 sheet 내부에서 처리
    final bottomInset  = MediaQuery.of(context).viewInsets.bottom;
    final bottomSystem = MediaQuery.of(context).padding.bottom;

    final isCompleted = _status == _kCompleted;
    final badgeText   = isCompleted ? '완료' : '예정';
    final badgeBg     = isCompleted ? const Color(0xFFDCFCE7) : widget.brandBlue.withOpacity(0.12);
    final badgeFg     = isCompleted ? const Color(0xFF166534) : widget.brandBlue;

    return DraggableScrollableSheet(
      expand:          false,
      initialChildSize: 0.78,
      minChildSize:     0.45,
      maxChildSize:     0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          // ✅ 키보드가 올라오면 sheet 내용이 밀리도록 내부에서 패딩 처리
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset + bottomSystem),
            child: SafeArea(
              top:    false,
              bottom: false,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                children: [
                  // 드래그 핸들
                  Center(
                    child: Container(
                      width:  42,
                      height: 5,
                      decoration: BoxDecoration(
                        color:        const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 헤더
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.isEdit ? '일정 수정' : '일정 추가',
                          maxLines:  1,
                          overflow:  TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Jalnan2TTF',
                            fontSize:   18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color:        badgeBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize:   12,
                            color:      badgeFg,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 텍스트 입력 섹션
                  _formCard(
                    child: Column(
                      children: [
                        _field(label: '공고/메모', hint: '예) 카페 서빙, 쿠팡 상하차', controller: _titleCtrl),
                        const SizedBox(height: 10),
                        _field(label: '회사/가게', hint: '예) 알바일주 사장님', controller: _companyCtrl),
                        const SizedBox(height: 10),
                        _field(
                          label:        '금액(원)',
                          hint:         '예) 120,000',
                          controller:   _payCtrl,
                          keyboardType: TextInputType.number,
                          isMoney:      true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 날짜/시간/상태 섹션
                  _formCard(
                    child: Column(
                      children: [
                        _kvRow(
                          label: '근무일',
                          value: DateFormat('yyyy.MM.dd (E)', 'ko_KR').format(_workDate),
                          onTap: _pickDate,
                        ),
                        const Divider(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _kvBox(
                                label: '시작',
                                value: _fmtTime(_startT),
                                onTap: () => _pickTime(isStart: true),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _kvBox(
                                label: '종료',
                                value: _fmtTime(_endT),
                                onTap: () => _pickTime(isStart: false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _statusChip(
                                text:     '예정',
                                selected: _status != _kCompleted,
                                onTap:    () => setState(() => _status = _kScheduled),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _statusChip(
                                text:     '완료',
                                selected: _status == _kCompleted,
                                onTap:    () => setState(() => _status = _kCompleted),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 버튼 영역
                  Row(
                    children: [
                      if (widget.isEdit && widget.onDelete != null)
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFB91C1C),
                              side:            const BorderSide(color: Color(0xFFFCA5A5)),
                              padding:         const EdgeInsets.symmetric(vertical: 14),
                              shape:           RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _saving
                                ? null
                                : () async {
                                    setState(() => _saving = true);
                                    final ok = await widget.onDelete!();
                                    if (!mounted) return;
                                    if (ok) {
                                      Navigator.pop(context, true);
                                    } else {
                                      setState(() => _saving = false);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('삭제가 실패했어요 🥲')),
                                      );
                                    }
                                  },
                            child: const Text('삭제', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                      if (widget.isEdit && widget.onDelete != null) const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.brandBlue,
                            foregroundColor: Colors.white,
                            padding:         const EdgeInsets.symmetric(vertical: 14),
                            shape:           RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width:  18,
                                  height: 18,
                                  child:  CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:       Colors.white,
                                  ),
                                )
                              : Text(
                                  widget.isEdit ? '저장' : '추가',
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────
  // UI atoms
  // ──────────────────────────────────────────
  Widget _formCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(18),
        border:       Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: child,
    );
  }

  Widget _field({
    required String               label,
    required String               hint,
    required TextEditingController controller,
    TextInputType?                 keyboardType,
    bool                          isMoney = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: kText)),
        const SizedBox(height: 6),
        TextField(
          controller:        controller,
          keyboardType:      keyboardType,
          inputFormatters:   isMoney ? [_ThousandsSeparatorFormatter()] : null,
          decoration: InputDecoration(
            hintText:  hint,
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w700),
            filled:    true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:   const BorderSide(color: kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:   BorderSide(color: widget.brandBlue, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _kvRow({
    required String       label,
    required String       value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w900)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                maxLines:  1,
                overflow:  TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  Widget _kvBox({
    required String       label,
    required String       value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w900)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                maxLines:  1,
                overflow:  TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.schedule_rounded, size: 18, color: widget.brandBlue),
          ],
        ),
      ),
    );
  }

  Widget _statusChip({
    required String       text,
    required bool         selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color:        selected ? widget.brandBlue.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border:       Border.all(color: selected ? widget.brandBlue : kBorder),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontSize:   12,
            fontWeight: FontWeight.w900,
            color:      selected ? widget.brandBlue : kMuted,
          ),
        ),
      ),
    );
  }
}