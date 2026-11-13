import 'dart:convert';
// lib/presentation/chat/work_confirmation_card.dart
import 'package:flutter/material.dart';
import 'package:iljujob/utils/chat_stage.dart';
import 'package:iljujob/utils/apply_stage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/app_theme.dart';
import '../../data/services/work_confirmation_service.dart';
import '../../data/services/contract_service.dart';
import '../contract/contract_sheets.dart';
import '../agent/store_qa_sheet.dart';
import '../../utils/condition_guard.dart';

// ── 채팅 내 출근 확정 카드 ──────────────────────────────────
class WorkConfirmationCard extends StatelessWidget {
  final WorkConfirmation confirm;
  final String userType; // 'worker' | 'client'
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onNoShow;
  /// 알바생 출근 확인 응답: day_before_confirmed / day_of_confirmed / checked_in / cancelled
  final void Function(String status)? onWorkerStatus;

  const WorkConfirmationCard({
    super.key,
    required this.confirm,
    required this.userType,
    this.onAccept,
    this.onReject,
    this.onNoShow,
    this.onWorkerStatus,
  });

  /// 알바생 주 버튼 (라벨, 다음 상태). 근무일 오늘 여부로 갈린다 — 서버 workConfirmationRules와 같은 표
  (String, String)? _workerNext() {
    final s = confirm.status;
    final today = isWorkDateToday(confirm.workDate);
    if (s == 'day_of_confirmed') return ('도착했어요', 'checked_in');
    if (today && ['accepted', 'scheduled', 'day_before_confirmed'].contains(s)) {
      return ('출발해요', 'day_of_confirmed');
    }
    if (!today && !isWorkDatePast(confirm.workDate) && ['accepted', 'scheduled'].contains(s)) {
      return ('갈게요', 'day_before_confirmed');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // 근무일이 지난 '제안'은 수락할 수 없다 — 6월 제안 카드에 지금도 '수락하기'가 떠 있었다
    final expiredProposal =
        confirm.status == 'proposed' && isWorkDatePast(confirm.workDate);
    final isProposed = confirm.status == 'proposed' && !expiredProposal;
    final isPast =
        expiredProposal ||
        ['cancelled', 'completed', 'no_show'].contains(confirm.status);
    final canReportNoShow = [
      'accepted',
      'scheduled',
      'day_before_confirmed',
      'day_of_confirmed',
    ].contains(confirm.status);
    final statusLabel =
        expiredProposal ? '지난 제안' : _statusLabel(confirm.status);
    final statusColor =
        expiredProposal ? AppColors.textTertiary : _statusColor(confirm.status);
    final workerNext =
        userType == 'worker' && onWorkerStatus != null ? _workerNext() : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                Text('근무 약속', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.bgMuted),
            const SizedBox(height: 14),

            // 근무 정보
            _Row(
              icon: Icons.event_rounded,
              label: '날짜',
              value: _formatDate(confirm.workDate),
            ),
            const SizedBox(height: 8),
            _Row(
              icon: Icons.access_time_rounded,
              label: '시간',
              value:
                  '${confirm.startTime.substring(0, 5)} ~ ${confirm.endTime.substring(0, 5)}',
            ),
            const SizedBox(height: 8),
            _Row(
              icon: Icons.payments_rounded,
              // ponytail: 예전 카드는 일급이 '시급' 칸에 들어갔다 — 2만 원 이상이면 '급여'로만 표기.
              // 정확히 하려면 카드에 pay_type 저장 필요
              label: confirm.hourlyWage >= 20000 ? '급여' : '시급',
              value: '${NumberFormat('#,###').format(confirm.hourlyWage)}원',
            ),
            if (confirm.location != null && confirm.location!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _Row(
                icon: Icons.location_on_rounded,
                label: '위치',
                value: confirm.location!,
              ),
            ],
            if (!isPast) ...[
              const SizedBox(height: 16),
              _StatusHint(status: confirm.status, userType: userType),
            ],

            // 근로계약서(자체 전자서명) — 양쪽 모두 언제든 열람·저장(교부)
            if (confirm.contractStatus == 'signed' ||
                (confirm.contractStatus == 'client_signed' && !(isProposed && userType == 'worker'))) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => openLaborContract(context, confirm.id),
                icon: const Icon(Icons.description_outlined, size: 16),
                label: Text(confirm.contractStatus == 'signed' ? '근로계약서 보기 · 서명 완료' : '근로계약서 보기 · 알바생 서명 전'),
              ),
            ],

            // 알바생: 매장에 물어보기(사장님 매장 안내서 기반 AI)
            if (userType == 'worker' && !isPast &&
                ['proposed', 'accepted', 'scheduled', 'day_before_confirmed', 'day_of_confirmed', 'checked_in'].contains(confirm.status))
              TextButton.icon(
                onPressed: () => showStoreQaSheet(context, confirm.id),
                icon: const Icon(Icons.storefront_outlined, size: 16),
                label: const Text('매장에 물어보기'),
              ),

            // 사장님: 알바생이 취소했거나 아직 출근 확인 전이면 대체 후보 찾기 (결원 복구)
            if (userType == 'client' && !isWorkDatePast(confirm.workDate) &&
                ['cancelled', 'accepted', 'scheduled'].contains(confirm.status)) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pushNamed(context, '/vacancy-recovery', arguments: confirm.id),
                  child: Text(confirm.status == 'cancelled' ? '대체 후보 찾기' : '답이 없나요? 대체 후보 보기'),
                ),
              ),
            ],

            // 알바생 출근 확인 (수락 이후 ~ 출근 전)
            if (workerNext != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onWorkerStatus!('cancelled'),
                      child: const Text('못 가요'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => onWorkerStatus!(workerNext.$2),
                      child: Text(workerNext.$1),
                    ),
                  ),
                ],
              ),
            ],

            // 알바생 조건 지킴이 — 수락 전에 최저시급·공고 조건과 비교
            if (isProposed && userType == 'worker' && !isPast)
              _ConditionGuard(checks: checkConditions(
                hourly: confirm.hourlyWage,
                start: confirm.startTime.substring(0, 5),
                end: confirm.endTime.substring(0, 5),
                jobPay: confirm.jobPay,
                jobPayType: confirm.jobPayType,
              )),

            // 액션 버튼 (구직자가 proposed 상태일 때만)
            if (isProposed && userType == 'worker' && !isPast) ...[
              // 클릭 동의 고지 — 버튼 바로 위에 있어야 [수락하기]가 서명 의사표시가 된다
              if (confirm.contractStatus == 'client_signed') ...[
                const SizedBox(height: 12),
                _ContractNotice(onView: () => openLaborContract(context, confirm.id)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      child: const Text(
                        '거절'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: onAccept,
                      child: const Text(
                        '수락하기'),
                    ),
                  ),
                ],
              ),
            ],

            // 노쇼 신고 버튼 (사장님 전용, 수락 이후 ~ 출근 완료 전)
            if (userType == 'client' &&
                canReportNoShow &&
                onNoShow != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onNoShow,
                  icon: const Icon(Icons.person_off_rounded, size: 15),
                  label: const Text(
                    '노쇼 신고'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                ),
              ),
              const SizedBox(height: 6),
              // 서버 workConfirmationController.AUTO_COMPLETE_HOURS 와 같은 값
              const Text('근무가 끝나고 48시간 안에 신고가 없으면 출근한 것으로 완료돼요', style: AppTextStyles.caption),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('M월 d일(E)', 'ko_KR').format(dt);
    } catch (_) {
      return raw;
    }
  }

  // 내 활동과 같은 이름 (utils/apply_stage.dart)
  String _statusLabel(String s) => workStatusLabel(s);

  Color _statusColor(String s) => switch (s) {
    'proposed' => AppColors.pending,
    'accepted' ||
    'scheduled' ||
    'day_before_confirmed' ||
    'day_of_confirmed' => AppColors.textPrimary,
    'checked_in' || 'completed' => AppColors.badgeSameDay,
    'cancelled' || 'no_show' => AppColors.error,
    _ => AppColors.textSecondary,
  };
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Row({required this.icon, required this.label, required this.value});

  // 라벨 길이가 달라 값이 들쭉날쭉했다 — 라벨 칸을 고정폭으로
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 44, child: Text(label, style: AppTextStyles.body2)),
      Expanded(
        child: Text(value, style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ),
    ],
  );
}

/// 출근확정 진행 단계. 배달 앱 주문 추적처럼 지금 어디인지 한눈에 보이게 한다.
/// 상태값 순서는 work_confirmations.status 와 같다.
class _StatusHint extends StatelessWidget {
  final String status;
  final String userType;
  const _StatusHint({required this.status, required this.userType});

  static const _steps = ['제안', '수락', '전날', '당일', '출근', '완료'];

  int get _current => switch (status) {
    'proposed' => 0,
    'accepted' || 'scheduled' => 1,
    'day_before_confirmed' => 2,
    'day_of_confirmed' => 3,
    'checked_in' => 4,
    'completed' => 5,
    _ => 0,
  };

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      'proposed' => '수락하면 근무가 확정돼요.',
      'accepted' || 'scheduled' when userType == 'client' =>
        '알바생이 아직 출근 확인 전이에요. 전날 18시에 알바생에게 물어봐요.',
      'accepted' || 'scheduled' => '근무가 확정됐어요. 전날 18시에 출근 확인을 물어봐요.',
      'day_before_confirmed' => '내일 출근 확인 완료. 당일 시작 3시간 전에 한 번 더 물어봐요.',
      'day_of_confirmed' => '출발 확인 완료.',
      'checked_in' => '출근 확인 완료. 근무 완료 처리만 남았어요.',
      _ => '출근 확정이 진행 중이에요.',
    };
    final cur = _current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < _steps.length; i++) ...[
              _dot(done: i < cur, now: i == cur),
              if (i < _steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    color: i < cur ? AppColors.primary : AppColors.border,
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < _steps.length; i++)
              Text(
                _steps[i],
                style: AppTextStyles.caption.copyWith(
                  color:
                      i == cur
                          ? AppColors.textPrimary
                          : i < cur
                          ? AppColors.textSecondary
                          : AppColors.textTertiary,
                  fontWeight: i == cur ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(text, style: AppTextStyles.body2),
      ],
    );
  }

  Widget _dot({required bool done, required bool now}) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.primary : AppColors.bgCard,
        border: Border.all(
          color:
              done
                  ? AppColors.primary
                  : now
                  ? AppColors.badgeUrgent
                  : AppColors.border,
          width: now ? 4 : 2,
        ),
      ),
      child:
          done
              ? const Icon(Icons.check_rounded, size: 10, color: Colors.white)
              : null,
    );
  }
}

// ── 근무 확정 제안 바텀시트 (사장님용) ────────────────────────
// 공고 값(근무일·시간·급여)으로 자동 채움. 근로계약서 정보도 이 시트 안에서 확인·수정(중첩 시트 없음)
class ProposeWorkConfirmationSheet extends StatefulWidget {
  final int chatRoomId;
  final int jobId;
  final int workerId;
  final int clientId;
  final String? jobLocation;
  final int? defaultWage; // 공고 급여 그대로 — 시급이 아니면 시트가 시급으로 바꾼다
  final String? payType; // 시급·일급·주급·월급
  final String? defaultDate; // 공고 start_date
  final String? defaultStartTime; // "09:00"
  final String? defaultEndTime; // "18:00"
  final String? weekdays; // 장기 공고 여부 ("월화수" 등, 있으면 장기)
  final Function(Map<String, dynamic>) onPropose;

  const ProposeWorkConfirmationSheet({
    super.key,
    required this.chatRoomId,
    required this.jobId,
    required this.workerId,
    required this.clientId,
    this.jobLocation,
    this.defaultWage,
    this.payType,
    this.defaultDate,
    this.defaultStartTime,
    this.defaultEndTime,
    this.weekdays,
    required this.onPropose,
  });

  @override
  State<ProposeWorkConfirmationSheet> createState() =>
      _ProposeWorkConfirmationSheetState();
}

// 급여 지급일 — 당일·다음 날·매주 N요일·매월 N일(숫자로 고른다). 저장은 계약서에 그대로 들어갈 문장
const _payModes = ['근무 당일', '근무 다음 날', '매주', '매월'];
const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

class _ProposeWorkConfirmationSheetState
    extends State<ProposeWorkConfirmationSheet> {
  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final _wageCtrl = TextEditingController();
  String? _wageNote; // 일급 → 시급 환산 안내
  bool _loading = false;
  bool _withContract = true;
  bool _contractsAvailable = false; // 서버가 허용할 때만 계약서 칸을 보인다
  String? _error;

  // 근로계약서 정보 (사장님 1회 입력)
  bool _profileLoaded = false;
  bool _profileEditing = false;
  final _bizName = TextEditingController(); // 상호 — 앱 계정 이름과 사업자등록증 상호가 다를 수 있다
  final _rep = TextEditingController();
  final _biz = TextEditingController();
  bool _hasCertificate = false;
  bool _scanning = false;
  final _addr = TextEditingController();
  final _placeCtrl = TextEditingController(); // 근무 장소 — 공고 주소로 채우고, 비었거나 틀리면 직접 고친다
  final _dutyCtrl = TextEditingController(); // 계약서 업무 내용 — 비우면 공고 분야·제목
  int? _breakMinutes; // 계약서 휴게시간 — null이면 공고 값 또는 법정 최소
  int? _minBreak; // 미리보기에서 받은 법정 최소
  bool _previewing = false;
  String _payMode = _payModes.first;
  String _payWeekday = '금';
  String _payMonthDay = '10'; // '1'~'31' 또는 '말일'
  String get _payDay => switch (_payMode) {
        '매주' => '매주 $_payWeekday요일',
        '매월' => _payMonthDay == '말일' ? '매월 말일' : '매월 $_payMonthDay일',
        _ => _payMode,
      };
  // 저장된 문장 → 고르는 값. 못 알아보면 false(펼쳐서 다시 고르게)
  bool _readPayDay(String s) {
    if (s == '근무 당일' || s == '근무 다음 날') { _payMode = s; return true; }
    final w = RegExp(r'^매주 ([월화수목금토일])요일$').firstMatch(s);
    if (w != null) { _payMode = '매주'; _payWeekday = w.group(1)!; return true; }
    final m = RegExp(r'^매월 (\d{1,2})일$').firstMatch(s);
    if (m != null && int.parse(m.group(1)!) >= 1 && int.parse(m.group(1)!) <= 31) { _payMode = '매월'; _payMonthDay = m.group(1)!; return true; }
    if (s == '매월 말일') { _payMode = '매월'; _payMonthDay = '말일'; return true; }
    return false;
  }
  String _payMethod = '계좌이체';

  static TimeOfDay? _parseTime(String? s) {
    final p = (s ?? '').split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
  }

  @override
  void initState() {
    super.initState();
    _placeCtrl.text = widget.jobLocation?.trim() ?? '';
    _startTime = _parseTime(widget.defaultStartTime);
    _endTime = _parseTime(widget.defaultEndTime);

    // 근무일: 공고 첫 근무일이 오늘 이후면 그대로
    final d = DateTime.tryParse((widget.defaultDate ?? '').trim());
    if (d != null) {
      final day = DateTime(d.year, d.month, d.day);
      final now = DateTime.now();
      if (!day.isBefore(DateTime(now.year, now.month, now.day))) _date = day;
    }

    // 급여: 시급은 그대로, 일급은 공고 근무시간으로 나눠 시급으로(10원 단위 올림)
    final pay = widget.defaultWage ?? 0;
    final type = widget.payType ?? '시급';
    if (pay > 0 && type == '시급') {
      _wageCtrl.text = '$pay';
    } else if (pay > 0 && type == '일급' && _estimatedHours != null) {
      // 계약서는 휴게를 뺀 시간으로 급여를 계산한다 → 같은 기준으로 나눠야 일급만큼 받는다
      final span = (_estimatedHours! * 60).round();
      final workH = (span - legalBreakMinutes(span)) / 60.0;
      final hourly = ((pay / workH) / 10).ceil() * 10;
      _wageCtrl.text = '$hourly';
      _wageNote = '일급 ${NumberFormat('#,###').format(pay)}원 ÷ 실근로 ${_fmtHours(workH)}시간(휴게 ${legalBreakMinutes(span)}분 뺌)으로 계산했어요';
    }
    _loadProfile();
  }

  // 사업자등록증 → 상호·사업자번호·대표자·주소. 등록한 서류가 있으면 그걸, 없거나 못 읽으면 사진을 받는다
  Future<void> _scanCertificate() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      Map<String, dynamic>? d;
      if (_hasCertificate) {
        try {
          d = await ContractService.scanCertificate();
        } catch (_) {}
      }
      if (d == null) {
        final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2000);
        if (x == null) return;
        final bytes = await x.readAsBytes();
        d = await ContractService.scanCertificate(imageBase64: base64Encode(bytes), mime: 'image/jpeg');
      }
      if (!mounted) return;
      setState(() {
        if (d!['bizName'] != null) _bizName.text = d['bizName'].toString();
        if (d['bizNumber'] != null) _biz.text = d['bizNumber'].toString();
        if (d['repName'] != null) _rep.text = d['repName'].toString();
        if (d['bizAddress'] != null) _addr.text = d['bizAddress'].toString();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final p = await ContractService.profile();
      _contractsAvailable = p.available;
      if (!p.available) _withContract = false;
      final m = p.profile;
      _hasCertificate = p.hasCertificate;
      _bizName.text = m['bizName']?.toString() ?? '';
      _rep.text = m['repName']?.toString() ?? '';
      _biz.text = m['bizNumber']?.toString() ?? '';
      _addr.text = m['bizAddress']?.toString() ?? '';
      final pdOk = _readPayDay(m['payDay']?.toString() ?? '');
      final pm = m['payMethod']?.toString() ?? '';
      if (pm == '현금' || pm == '계좌이체') _payMethod = pm;
      // 처음이거나 지급일이 고를 수 있는 값이 아니면 펼쳐서 확인받는다
      _profileEditing = !p.complete || !pdOk;
    } catch (_) {
      _withContract = false; // 계약서 정보를 못 불러오면 계약서 없이 제안
    }
    if (mounted) setState(() => _profileLoaded = true);
  }

  @override
  void dispose() {
    _wageCtrl.dispose();
    _bizName.dispose();
    _rep.dispose();
    _biz.dispose();
    _addr.dispose();
    _placeCtrl.dispose();
    _dutyCtrl.dispose();
    super.dispose();
  }

  bool get _isWeekdaysJob =>
      widget.weekdays != null && widget.weekdays!.trim().isNotEmpty;

  // 서버가 형식까지 검사한다(대표자 숫자 금지·사업자번호 10자리·주소). 여기선 빈 칸만 막는다
  bool get _profileReady =>
      _bizName.text.trim().isNotEmpty &&
      _rep.text.trim().isNotEmpty &&
      _biz.text.replaceAll(RegExp(r'\D'), '').length == 10 &&
      _addr.text.trim().isNotEmpty;

  bool get _canSubmit =>
      _date != null &&
      _startTime != null &&
      _endTime != null &&
      _wageCtrl.text.trim().isNotEmpty &&
      (!_withContract || _placeCtrl.text.trim().length >= 2) &&
      (!_withContract || (_profileLoaded && _profileReady));

  // 밤샘 근무(종료 < 시작)는 다음 날 종료로 계산
  double? get _estimatedHours {
    if (_startTime == null || _endTime == null) return null;
    var diff = (_endTime!.hour * 60 + _endTime!.minute) -
        (_startTime!.hour * 60 + _startTime!.minute);
    if (diff <= 0) diff += 24 * 60;
    return diff / 60.0;
  }

  // 계약서와 같은 기준: 고른 휴게시간, 없으면 법정 최소
  int _breakFor(double spanH) => _breakMinutes ?? legalBreakMinutes((spanH * 60).round());
  double _workHours(double spanH) => ((spanH * 60).round() - _breakFor(spanH)) / 60.0;

  static String _fmtHours(double h) =>
      h == h.roundToDouble() ? h.toInt().toString() : h.toStringAsFixed(1);

  int? get _wage => int.tryParse(_wageCtrl.text.replaceAll(',', ''));

  static String _hm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
  String? get _location => _placeCtrl.text.trim().isEmpty ? widget.jobLocation : _placeCtrl.text.trim();
  Map<String, dynamic> get _contractTerms => {
        if (_dutyCtrl.text.trim().isNotEmpty) 'contractDuty': _dutyCtrl.text.trim(),
        if (_breakMinutes != null) 'contractBreakMinutes': _breakMinutes,
      };

  Future<void> _saveProfileIfEditing() async {
    if (!_withContract || !_profileEditing) return;
    await ContractService.saveProfile({
      'bizName': _bizName.text.trim(),
      'repName': _rep.text.trim(),
      'bizNumber': _biz.text.trim(),
      'bizAddress': _addr.text.trim(),
      'payDay': _payDay,
      'payMethod': _payMethod,
    });
  }

  // 보내기 전에 실제 계약서를 본다 — 서버가 제안과 같은 규칙으로 만든다(저장·서명 없음)
  Future<void> _preview() async {
    if (!_canSubmit) return;
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      await _saveProfileIfEditing();
      final r = await ContractService.preview({
        'jobId': widget.jobId,
        'workerId': widget.workerId,
        'workDate': DateFormat('yyyy-MM-dd').format(_date!),
        'startTime': _hm(_startTime!),
        'endTime': _hm(_endTime!),
        'hourlyWage': _wage ?? 0,
        'location': _location,
        ..._contractTerms,
      });
      if (!mounted) return;
      setState(() {
        _previewing = false;
        if (_dutyCtrl.text.trim().isEmpty) _dutyCtrl.text = r['duty']?.toString() ?? '';
        _minBreak = (r['minBreakMinutes'] as num?)?.toInt();
        _breakMinutes ??= (r['breakMinutes'] as num?)?.toInt();
        if (_profileEditing) _profileEditing = false; // 저장됐다
      });
      await showContractPreview(context, r['html'].toString());
    } catch (e) {
      if (mounted) {
        setState(() {
          _previewing = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _saveProfileIfEditing();
      // 계약서를 붙이면 사장님도 본인인증 후 서명(누가 서명했는지 계약서에 남는다)
      String? impUid;
      if (_withContract) {
        if (!mounted) return;
        impUid = await verifyIdentityForSigning(context);
        if (impUid == null) throw Exception('본인인증을 마쳐야 근로계약서와 함께 보낼 수 있어요.');
      }
      await WorkConfirmationService.propose(
        chatRoomId: widget.chatRoomId,
        jobId: widget.jobId,
        workerId: widget.workerId,
        clientId: widget.clientId,
        workDate: DateFormat('yyyy-MM-dd').format(_date!),
        startTime: _hm(_startTime!),
        endTime: _hm(_endTime!),
        hourlyWage: _wage ?? 0,
        location: _location,
        contract: _withContract,
        contractTerms: _contractTerms,
        identityImpUid: impUid,
      );
      if (mounted) {
        widget.onPropose({'success': true});
        Navigator.pop(context);
      }
    } catch (e) {
      // 스낵바는 시트 뒤에 가려져 안 보였다 — 시트 안에 보여준다
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
          // 사업주 정보가 형식에 안 맞으면 그 칸들을 펼쳐서 고치게 한다
          if (e is WorkConfirmationException && e.code == 'NEED_CONTRACT_PROFILE') _profileEditing = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad =
        MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;
    final hours = _estimatedHours;
    final wage = _wage;
    final lowWage = wage != null && wage > 0 && wage < _minWage;

    String fmt(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    Future<void> pickTime(bool start) async {
      final t = await showTimePicker(
        context: context,
        initialTime: (start ? _startTime : _endTime) ??
            TimeOfDay(hour: start ? 9 : 18, minute: 0),
      );
      if (t != null) setState(() => start ? _startTime = t : _endTime = t);
    }

    return Padding(
      padding: EdgeInsets.only(bottom: pad + 16),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('출근 확정 제안', style: AppTextStyles.h2),
            const SizedBox(height: 4),
            Text(
              _isWeekdaysJob
                  ? '${widget.weekdays} 공고예요 · 첫 출근 날짜를 골라 주세요'
                  : '공고 조건으로 채워 뒀어요. 알바생이 수락하면 근무가 확정돼요',
              style: AppTextStyles.body2,
            ),
            const SizedBox(height: 20),

            _FieldLabel('근무 날짜'),
            const SizedBox(height: 6),
            _Tile(
              text: _date == null
                  ? '날짜를 선택하세요'
                  : DateFormat('M월 d일(E)', 'ko_KR').format(_date!),
              isEmpty: _date == null,
              icon: Icons.calendar_today_rounded,
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date ?? now.add(const Duration(days: 1)),
                  firstDate: DateTime(now.year, now.month, now.day),
                  lastDate: now.add(const Duration(days: 60)),
                  locale: const Locale('ko'),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('시작'),
                      const SizedBox(height: 6),
                      _Tile(
                        text: _startTime == null ? '시작 시간' : fmt(_startTime!),
                        isEmpty: _startTime == null,
                        icon: Icons.access_time_rounded,
                        onTap: () => pickTime(true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('종료'),
                      const SizedBox(height: 6),
                      _Tile(
                        text: _endTime == null ? '종료 시간' : fmt(_endTime!),
                        isEmpty: _endTime == null,
                        icon: Icons.access_time_rounded,
                        onTap: () => pickTime(false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _FieldLabel('근무 장소'),
            const SizedBox(height: 6),
            TextField(
              controller: _placeCtrl,
              decoration: _inputDeco('근무할 곳 주소'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            _FieldLabel('시급'),
            const SizedBox(height: 6),
            TextField(
              controller: _wageCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDeco('시급을 입력하세요', suffix: '원'),
              onChanged: (_) => setState(() => _wageNote = null),
            ),
            const SizedBox(height: 6),
            if (lowWage)
              Text(
                '최저시급(${NumberFormat('#,###').format(_minWage)}원)보다 낮아요',
                style: AppTextStyles.caption.copyWith(color: AppColors.error),
              )
            else if (_wageNote != null)
              Text(_wageNote!, style: AppTextStyles.caption),
            if (hours != null && wage != null && wage > 0) ...[
              const SizedBox(height: 2),
              Text(
                '실근로 ${_fmtHours(_workHours(hours))}시간(휴게 ${_breakFor(hours)}분) · 총 ${NumberFormat('#,###').format((_workHours(hours) * wage).round())}원',
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),

            // 근로계약서 — 서버가 허용한 계정만
            if (_contractsAvailable) ...[
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('근로계약서 함께 보내기', style: AppTextStyles.body1),
                      SizedBox(height: 2),
                      Text('보낼 때 본인인증으로 사장님 서명, 알바생이 수락하면 서명 완료',
                          style: AppTextStyles.caption),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _withContract,
                  onChanged: (v) => setState(() => _withContract = v),
                ),
              ],
            ),
            ],
            if (_withContract) ...[
              const SizedBox(height: 10),
              if (!_profileLoaded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              else if (!_profileEditing)
                _profileSummary()
              else
                _profileForm(),
              const SizedBox(height: 12),
              _FieldLabel('업무 내용'),
              const SizedBox(height: 6),
              TextField(
                controller: _dutyCtrl,
                maxLength: 100,
                decoration: _inputDeco('비우면 공고 분야·제목으로 들어가요').copyWith(counterText: ''),
              ),
              const SizedBox(height: 12),
              _FieldLabel(_minBreak == null ? '휴게시간' : '휴게시간 (법정 최소 $_minBreak분)'),
              const SizedBox(height: 6),
              _Choices(
                options: const ['자동', '30분', '60분', '90분'],
                value: _breakMinutes == null ? '자동' : '$_breakMinutes분',
                onChanged: (o) => setState(() => _breakMinutes = o == '자동' ? null : int.parse(o.replaceAll('분', ''))),
              ),
              const SizedBox(height: 4),
              const Text('자동은 공고의 휴게시간, 없으면 법정 최소(4시간 근무 30분·8시간 근무 60분)예요.',
                  style: AppTextStyles.caption),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _canSubmit && !_previewing && !_loading ? _preview : null,
                  icon: _previewing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('계약서 미리보기'),
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.errorBorder),
                ),
                child: Text(_error!,
                    style: AppTextStyles.body2.copyWith(color: AppColors.error)),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSubmit && !_loading ? _submit : null,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('제안 보내기'),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _profileSummary() => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: BoxDecoration(
          color: AppColors.bgMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_bizName.text} · 대표 ${_rep.text} · ${_biz.text}',
                      style: AppTextStyles.body2
                          .copyWith(color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('$_payDay 지급 · $_payMethod · ${_addr.text}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _profileEditing = true),
              child: const Text('수정'),
            ),
          ],
        ),
      );

  Widget _profileForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('계약서에 들어갈 사업장 정보예요. 한 번 저장하면 다음부터 자동으로 채워져요.',
              style: AppTextStyles.caption),
          const SizedBox(height: 8),
          // 사업자등록증을 AI가 읽어 채운다 — 사업자번호는 검증번호까지 맞을 때만. 다르면 아래에서 직접 고친다
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _scanning ? null : _scanCertificate,
              icon: _scanning
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_outlined, size: 18),
              label: Text(_hasCertificate ? '등록한 사업자등록증으로 채우기' : '사업자등록증 찍어서 채우기'),
            ),
          ),
          const SizedBox(height: 12),
          _FieldLabel('상호 (사업자등록증 기준)'),
          const SizedBox(height: 6),
          TextField(
            controller: _bizName,
            decoration: _inputDeco('사업자등록증의 상호 — 앱 가게 이름과 달라도 돼요'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _FieldLabel('대표자 이름'),
          const SizedBox(height: 6),
          TextField(
            controller: _rep,
            decoration: _inputDeco('사업자등록증의 대표자 실명'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _FieldLabel('사업자등록번호'),
          const SizedBox(height: 6),
          TextField(
            controller: _biz,
            keyboardType: TextInputType.number,
            decoration: _inputDeco('숫자 10자리'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _FieldLabel('사업장 주소'),
          const SizedBox(height: 6),
          TextField(
            controller: _addr,
            decoration: _inputDeco('도로명·지번까지 (예: 인천 연수구 송도동 1)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _FieldLabel('급여 지급일'),
          const SizedBox(height: 6),
          _Choices(
            options: _payModes,
            value: _payMode,
            onChanged: (v) => setState(() => _payMode = v),
          ),
          if (_payMode == '매주') ...[
            const SizedBox(height: 8),
            _Choices(options: _weekdays, value: _payWeekday, onChanged: (v) => setState(() => _payWeekday = v)),
          ],
          if (_payMode == '매월') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: AppColors.bgMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _payMonthDay,
                      items: [
                        for (var d = 1; d <= 31; d++) DropdownMenuItem(value: '$d', child: Text('$d일')),
                        const DropdownMenuItem(value: '말일', child: Text('말일')),
                      ],
                      onChanged: (v) => setState(() => _payMonthDay = v ?? _payMonthDay),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('에 지급', style: AppTextStyles.body2),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text('계약서에 "$_payDay 지급"으로 들어가요', style: AppTextStyles.caption),
          const SizedBox(height: 12),
          _FieldLabel('지급 방법'),
          const SizedBox(height: 6),
          _Choices(
            options: const ['계좌이체', '현금'],
            value: _payMethod,
            onChanged: (v) => setState(() => _payMethod = v),
          ),
        ],
      );
}

const _minWage = 10320; // 2026 최저시급 — 서버 lib/laborContract.js MIN_WAGE 와 같이

InputDecoration _inputDeco(String hint, {String? suffix}) => InputDecoration(
      hintText: hint,
      suffixText: suffix,
      filled: true,
      fillColor: AppColors.bgMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );

/// 고르는 칸 — 선택된 것만 파랑(선택 표시)
class _Choices extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  const _Choices({required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (final o in options) ...[
            Expanded(
              child: Material(
                color: o == value ? AppColors.primaryLight : AppColors.bgMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: () => onChanged(o),
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: o == value ? AppColors.primary : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      o,
                      style: AppTextStyles.body2.copyWith(
                        color: o == value ? AppColors.primary : AppColors.textSecondary,
                        fontWeight: o == value ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (o != options.last) const SizedBox(width: 8),
          ],
        ],
      );
}

class _ConditionGuard extends StatelessWidget {
  final List<(bool, String)> checks;
  const _ConditionGuard({required this.checks});

  @override
  Widget build(BuildContext context) {
    if (checks.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: AppColors.bgMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('조건 확인', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final (ok, text) in checks)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                      size: 16, color: ok ? AppColors.textSecondary : AppColors.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(text,
                        style: AppTextStyles.body2.copyWith(color: ok ? AppColors.textSecondary : AppColors.error)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ContractNotice extends StatelessWidget {
  final VoidCallback onView;
  const _ContractNotice({required this.onView});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: AppColors.bgMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '수락하면 본인인증 후 위 조건의 근로계약서에 전자서명돼요. 서명한 계약서는 언제든 다시 볼 수 있어요.',
                style: AppTextStyles.caption,
              ),
            ),
            TextButton(onPressed: onView, child: const Text('계약서 보기')),
          ],
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: AppFontSize.body2,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    ),
  );
}

/// 값 칸은 채워도 회색 그대로 — 채우면 파랑+테두리+체크로 바뀌던 것이 화면을 파랗게 만들었다(값 칸 규칙)
class _Tile extends StatelessWidget {
  final String text;
  final bool isEmpty;
  final IconData icon;
  final VoidCallback onTap;
  const _Tile({
    required this.text,
    required this.isEmpty,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.bgMuted,
    borderRadius: BorderRadius.circular(AppRadius.md),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body2.copyWith(
                  fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w600,
                  color: isEmpty ? AppColors.textTertiary : AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
