// lib/presentation/chat/work_confirmation_card.dart
import 'package:flutter/material.dart';
import 'package:iljujob/utils/chat_stage.dart';
import 'package:iljujob/utils/apply_stage.dart';
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../data/services/work_confirmation_service.dart';

// ── 채팅 내 출근 확정 카드 ──────────────────────────────────
class WorkConfirmationCard extends StatelessWidget {
  final WorkConfirmation confirm;
  final String userType; // 'worker' | 'client'
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onNoShow;

  const WorkConfirmationCard({
    super.key,
    required this.confirm,
    required this.userType,
    this.onAccept,
    this.onReject,
    this.onNoShow,
  });

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
              _StatusHint(status: confirm.status),
            ],

            // 액션 버튼 (구직자가 proposed 상태일 때만)
            if (isProposed && userType == 'worker' && !isPast) ...[
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
  const _StatusHint({required this.status});

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
      'accepted' || 'scheduled' => '근무가 확정됐어요. 전날 18시에 확인 알림이 가요.',
      'day_before_confirmed' => '전날 확인 완료. 출근 2시간 전에 당일 확인 알림이 가요.',
      'day_of_confirmed' => '당일 확인 완료. 출근하면 정산 달력에 반영돼요.',
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
class ProposeWorkConfirmationSheet extends StatefulWidget {
  final int chatRoomId;
  final int jobId;
  final int workerId;
  final int clientId;
  final String? jobLocation;
  final int? defaultWage; // 공고 시급 자동 채움
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
    this.defaultStartTime,
    this.defaultEndTime,
    this.weekdays,
    required this.onPropose,
  });

  @override
  State<ProposeWorkConfirmationSheet> createState() =>
      _ProposeWorkConfirmationSheetState();
}

class _ProposeWorkConfirmationSheetState
    extends State<ProposeWorkConfirmationSheet> {
  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final _wageCtrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // 공고 데이터 자동 채움
    if (widget.defaultWage != null && widget.defaultWage! > 0) {
      _wageCtrl.text = widget.defaultWage.toString();
    }
    if (widget.defaultStartTime != null) {
      final parts = widget.defaultStartTime!.split(':');
      if (parts.length >= 2) {
        _startTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 9,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
    if (widget.defaultEndTime != null) {
      final parts = widget.defaultEndTime!.split(':');
      if (parts.length >= 2) {
        _endTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 18,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
  }

  @override
  void dispose() {
    _wageCtrl.dispose();
    super.dispose();
  }

  bool get _isWeekdaysJob =>
      widget.weekdays != null && widget.weekdays!.trim().isNotEmpty;

  bool get _canSubmit =>
      _date != null &&
      _startTime != null &&
      _endTime != null &&
      _wageCtrl.text.trim().isNotEmpty;

  double? get _estimatedHours {
    if (_startTime == null || _endTime == null) return null;
    final diff =
        (_endTime!.hour * 60 + _endTime!.minute) -
        (_startTime!.hour * 60 + _startTime!.minute);
    return diff > 0 ? diff / 60.0 : null;
  }

  int? get _estimatedPay {
    final hours = _estimatedHours;
    final wage = int.tryParse(_wageCtrl.text.replaceAll(',', ''));
    if (hours == null || wage == null) return null;
    return (hours * wage).round();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _loading = true);
    try {
      final wage = int.tryParse(_wageCtrl.text.replaceAll(',', '')) ?? 0;
      await WorkConfirmationService.propose(
        chatRoomId: widget.chatRoomId,
        jobId: widget.jobId,
        workerId: widget.workerId,
        clientId: widget.clientId,
        workDate: DateFormat('yyyy-MM-dd').format(_date!),
        startTime:
            '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}:00',
        endTime:
            '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}:00',
        hourlyWage: wage,
        location: widget.jobLocation,
      );
      if (mounted) {
        widget.onPropose({'success': true});
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad =
        MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;
    final estPay = _estimatedPay;
    final estHours = _estimatedHours;

    String fmt(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(bottom: pad + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 핸들바
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 헤더 카드
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.event_available_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '출근 확정 제안',
                            style: TextStyle(
                              fontSize: AppFontSize.buttonLg,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '알바생이 수락하면 근무가 확정돼요',
                            style: TextStyle(
                              fontSize: AppFontSize.meta,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 필드 영역
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 장기 공고 안내
                  if (_isWeekdaysJob) ...[
                    Text('${widget.weekdays} 공고예요 · 첫 출근 날짜를 골라 주세요', style: AppTextStyles.body2),
                    const SizedBox(height: 16),
                  ],

                  // 근무 날짜
                  _FieldLabel('근무 날짜'),
                  const SizedBox(height: 6),
                  _Tile(
                    text:
                        _date == null
                            ? '날짜를 선택하세요'
                            : DateFormat('M월 d일(E)', 'ko_KR').format(_date!),
                    isEmpty: _date == null,
                    icon: Icons.calendar_today_rounded,
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(
                          const Duration(days: 1),
                        ),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                        locale: const Locale('ko'),
                      );
                      if (d != null) setState(() => _date = d);
                    },
                  ),
                  const SizedBox(height: 16),

                  // 근무 시간
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FieldLabel('시작 시간'),
                            const SizedBox(height: 6),
                            _Tile(
                              text:
                                  _startTime == null
                                      ? '시작 시간'
                                      : fmt(_startTime!),
                              isEmpty: _startTime == null,
                              icon: Icons.access_time_rounded,
                              onTap: () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: const TimeOfDay(
                                    hour: 9,
                                    minute: 0,
                                  ),
                                );
                                if (t != null) setState(() => _startTime = t);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FieldLabel('종료 시간'),
                            const SizedBox(height: 6),
                            _Tile(
                              text: _endTime == null ? '종료 시간' : fmt(_endTime!),
                              isEmpty: _endTime == null,
                              icon: Icons.access_time_rounded,
                              onTap: () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: const TimeOfDay(
                                    hour: 18,
                                    minute: 0,
                                  ),
                                );
                                if (t != null) setState(() => _endTime = t);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 시급
                  _FieldLabel('시급'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _wageCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '시급을 입력하세요',
                      suffixText: '원',
                      filled: true,
                      fillColor: AppColors.bgMuted,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),

                  // 예상 급여 요약
                  if (estPay != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${estHours!.toStringAsFixed(1)}시간 · 총 ${NumberFormat('#,###').format(estPay)}원',
                      style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                    ),
                  ],

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canSubmit && !_loading ? _submit : null,
                      child:
                          _loading
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Text(
                                '제안 보내기'),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
