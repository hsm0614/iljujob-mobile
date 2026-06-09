// lib/presentation/chat/work_confirmation_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../data/services/work_confirmation_service.dart';

// ── 채팅 내 출근 확정 카드 ──────────────────────────────────
class WorkConfirmationCard extends StatelessWidget {
  final WorkConfirmation confirm;
  final String userType; // 'worker' | 'client'
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const WorkConfirmationCard({
    super.key,
    required this.confirm,
    required this.userType,
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isProposed = confirm.status == 'proposed';
    final isPast     = ['cancelled', 'completed', 'no_show'].contains(confirm.status);
    final statusLabel = _statusLabel(confirm.status);
    final statusColor = _statusColor(confirm.status);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                const Text(
                  '출근 확정 카드',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            const SizedBox(height: 14),

            // 근무 정보
            _Row(icon: Icons.event_rounded, label: '날짜', value: _formatDate(confirm.workDate)),
            const SizedBox(height: 8),
            _Row(icon: Icons.access_time_rounded, label: '시간', value: '${confirm.startTime.substring(0,5)} ~ ${confirm.endTime.substring(0,5)}'),
            const SizedBox(height: 8),
            _Row(
              icon: Icons.payments_rounded,
              label: '시급',
              value: '${NumberFormat('#,###').format(confirm.hourlyWage)}원',
              valueColor: AppColors.primary,
            ),
            if (confirm.location != null && confirm.location!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _Row(icon: Icons.location_on_rounded, label: '위치', value: confirm.location!),
            ],

            // 액션 버튼 (구직자가 proposed 상태일 때만)
            if (isProposed && userType == 'worker' && !isPast) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: const Text('거절', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: const Text('수락하기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
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
      return DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(dt);
    } catch (_) {
      return raw;
    }
  }

  String _statusLabel(String s) => switch (s) {
    'proposed'             => '제안됨',
    'accepted'             => '수락됨',
    'scheduled'            => '예정',
    'day_before_confirmed' => 'D-1 확인',
    'day_of_confirmed'     => '당일 확인',
    'checked_in'           => '출근 완료',
    'completed'            => '근무 완료',
    'cancelled'            => '취소됨',
    'no_show'              => '노쇼',
    _                      => s,
  };

  Color _statusColor(String s) => switch (s) {
    'proposed'  => const Color(0xFFFF9500),
    'accepted' || 'scheduled' || 'day_before_confirmed' || 'day_of_confirmed' => AppColors.primary,
    'checked_in' || 'completed' => const Color(0xFF22C55E),
    'cancelled' || 'no_show'   => const Color(0xFFEF4444),
    _                          => const Color(0xFF6B7280),
  };
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _Row({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF9CA3AF)),
          const SizedBox(width: 6),
          Text('$label  ', style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor ?? const Color(0xFF111827))),
        ],
      );
}

// ── 근무 확정 제안 바텀시트 (사장님용) ────────────────────────
class ProposeWorkConfirmationSheet extends StatefulWidget {
  final int chatRoomId;
  final int jobId;
  final int workerId;
  final int clientId;
  final String? jobLocation;
  final Function(Map<String, dynamic>) onPropose;

  const ProposeWorkConfirmationSheet({
    super.key,
    required this.chatRoomId,
    required this.jobId,
    required this.workerId,
    required this.clientId,
    this.jobLocation,
    required this.onPropose,
  });

  @override
  State<ProposeWorkConfirmationSheet> createState() => _ProposeWorkConfirmationSheetState();
}

class _ProposeWorkConfirmationSheetState extends State<ProposeWorkConfirmationSheet> {
  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final _wageCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _wageCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => _date != null && _startTime != null && _endTime != null && _wageCtrl.text.trim().isNotEmpty;

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
        startTime: '${_startTime!.hour.toString().padLeft(2,'0')}:${_startTime!.minute.toString().padLeft(2,'0')}:00',
        endTime:   '${_endTime!.hour.toString().padLeft(2,'0')}:${_endTime!.minute.toString().padLeft(2,'0')}:00',
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, pad + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('출근 확정 제안', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
            const SizedBox(height: 4),
            const Text('알바생에게 근무 일정을 제안해요. 알바생이 수락하면 확정됩니다.', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
            const SizedBox(height: 24),

            // 날짜
            _FieldLabel('근무 날짜'),
            const SizedBox(height: 6),
            _Tile(
              text: _date == null ? '날짜 선택' : DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(_date!),
              isEmpty: _date == null,
              icon: Icons.calendar_today_rounded,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 1)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 60)),
                  locale: const Locale('ko'),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: 16),

            // 시간
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('시작 시간'),
                      const SizedBox(height: 6),
                      _Tile(
                        text: _startTime == null
                            ? '시작 시간'
                            : '${_startTime!.hour.toString().padLeft(2,'0')}:${_startTime!.minute.toString().padLeft(2,'0')}',
                        isEmpty: _startTime == null,
                        icon: Icons.access_time_rounded,
                        onTap: () async {
                          final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
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
                        text: _endTime == null
                            ? '종료 시간'
                            : '${_endTime!.hour.toString().padLeft(2,'0')}:${_endTime!.minute.toString().padLeft(2,'0')}',
                        isEmpty: _endTime == null,
                        icon: Icons.access_time_rounded,
                        onTap: () async {
                          final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 18, minute: 0));
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
                hintText: '시급 입력 (원)',
                suffixText: '원',
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSubmit && !_loading ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('제안 보내기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)));
}

class _Tile extends StatelessWidget {
  final String text;
  final bool isEmpty;
  final IconData icon;
  final VoidCallback onTap;
  const _Tile({required this.text, required this.isEmpty, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: isEmpty ? const Color(0xFF9CA3AF) : AppColors.primary),
              const SizedBox(width: 8),
              Text(text, style: TextStyle(fontSize: 13, color: isEmpty ? const Color(0xFF9CA3AF) : const Color(0xFF111827))),
            ],
          ),
        ),
      );
}
